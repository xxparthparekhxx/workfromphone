import asyncio
import codecs
import contextlib
import fcntl
import json
import os
import pty
import signal
import struct
import sys
import termios
import time
from pathlib import Path
from fastapi import WebSocket, WebSocketDisconnect
from backend.core.security import sanitized_child_env
from backend.schemas.terminal import TerminalRunRequest, TerminalRunResponse


async def terminate_process_group(process: asyncio.subprocess.Process) -> None:
    """Kill a session leader and every process it spawned.

    Requires the process to have been started with `start_new_session=True`
    (or to have called `setsid` itself), so that its pid is also its process
    group id. Killing only the process would orphan its children.
    """
    if process.returncode is not None:
        return

    with contextlib.suppress(ProcessLookupError):
        os.killpg(process.pid, signal.SIGTERM)

    try:
        await asyncio.wait_for(process.wait(), timeout=1)
    except asyncio.TimeoutError:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGKILL)
        await process.wait()


async def communicate_with_cap(
    process: asyncio.subprocess.Process,
    max_bytes: int,
    *,
    on_limit_exceeded=None,
    chunk_size: int = 64 * 1024,
) -> tuple[bytes, bytes, bool]:
    """Stream a subprocess's stdout/stderr into bounded buffers.

    Unlike ``process.communicate()``, memory stays bounded: the two streams
    together stop accumulating once ``max_bytes`` is reached. When the cap is
    hit, ``on_limit_exceeded`` is invoked (sync or async; callers should kill
    the process) and the remaining output is drained and discarded so the
    process can exit without filling the pipe buffers.

    Returns ``(stdout, stderr, truncated)``.
    """
    stdout_buf = bytearray()
    stderr_buf = bytearray()
    truncated = False

    async def _pump(stream, buf: bytearray) -> None:
        nonlocal truncated
        if stream is None:
            return
        while True:
            chunk = await stream.read(chunk_size)
            if not chunk:
                return
            space = max_bytes - len(stdout_buf) - len(stderr_buf)
            if len(chunk) <= space:
                buf.extend(chunk)
                continue
            if space > 0:
                buf.extend(chunk[:space])
            truncated = True
            callback = on_limit_exceeded() if on_limit_exceeded is not None else None
            if callback is not None:
                await callback
            while await stream.read(chunk_size):
                pass
            return

    await asyncio.gather(
        _pump(process.stdout, stdout_buf),
        _pump(process.stderr, stderr_buf),
    )
    with contextlib.suppress(Exception):
        await process.wait()
    return bytes(stdout_buf), bytes(stderr_buf), truncated


class TerminalService:
    _DEFAULT_COLS = 80
    _DEFAULT_ROWS = 24
    _MAX_INPUT_BYTES = 64 * 1024
    _IDLE_TIMEOUT_SECONDS = 10 * 60
    _active_ptys = 0
    _PTY_SHELL_BOOTSTRAP = (
        "import fcntl, os, sys, termios;"
        "os.setsid();"
        "fcntl.ioctl(0, termios.TIOCSCTTY, 0);"
        "os.execv(sys.argv[1], [sys.argv[1], '-i'])"
    )

    @classmethod
    def _get_process_env(cls) -> dict:
        env = sanitized_child_env()
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["FORCE_COLOR"] = "1"
        env["PAGER"] = "cat"
        env["GIT_PAGER"] = "cat"
        env["CI"] = "true"
        env["PYTHONUNBUFFERED"] = "1"
        env["NPM_CONFIG_COLOR"] = "always"
        env["YARN_ENABLE_COLORS"] = "true"
        env["DEBIAN_FRONTEND"] = "noninteractive"
        return env

    @classmethod
    def _get_pty_env(cls) -> dict:
        env = sanitized_child_env()
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        return env

    @staticmethod
    async def _read_from_fd(fd: int, size: int) -> bytes:
        """Read from the pty master via the event loop's selector.

        A thread blocked in ``os.read`` is not woken when the fd is closed
        (the open file stays alive until the peer closes), so a
        ``to_thread(os.read)`` worker can pin its thread-pool slot for the
        lifetime of a background child holding the slave. Waiting on the
        selector's readable event is cancellable and pins nothing.
        """
        loop = asyncio.get_running_loop()
        readable: asyncio.Future = loop.create_future()

        def _mark_readable() -> None:
            if not readable.done():
                readable.set_result(None)

        loop.add_reader(fd, _mark_readable)
        try:
            await readable
        finally:
            loop.remove_reader(fd)
        return os.read(fd, size)

    @staticmethod
    def _set_pty_size(
        master_fd: int,
        cols: int,
        rows: int,
        pixel_width: int = 0,
        pixel_height: int = 0,
    ) -> None:
        winsize = struct.pack("HHHH", rows, cols, pixel_width, pixel_height)
        fcntl.ioctl(master_fd, termios.TIOCSWINSZ, winsize)

    @staticmethod
    def _resolve_shell() -> str:
        # Preferred shell first; minimal rootfs images (proot on Android)
        # may only ship /bin/sh, so fall back instead of failing outright.
        candidates = []
        configured_shell = os.environ.get("SHELL", "")
        if configured_shell:
            candidates.append(configured_shell)
        candidates.extend(["/bin/bash", "/bin/sh"])
        for candidate in candidates:
            if candidate and Path(candidate).is_file() and os.access(candidate, os.X_OK):
                return candidate
        return "/bin/sh"

    @classmethod
    async def run_command(cls, req: TerminalRunRequest) -> TerminalRunResponse:
        from backend.core.config import settings as _settings
        from backend.core.security import resolve_project_root as _resolve_root

        try:
            resolved = _resolve_root(req.project_path)
            assert isinstance(resolved, Path)
            project_root = resolved
        except ValueError as exc:
            return TerminalRunResponse(
                command=req.command,
                exit_code=-1,
                stdout="",
                stderr=str(exc),
                duration_ms=0,
                timed_out=False,
            )
        if not project_root.exists() or not project_root.is_dir():
            return TerminalRunResponse(
                command=req.command,
                exit_code=-1,
                stdout="",
                stderr=f"Directory '{req.project_path}' does not exist.",
                duration_ms=0,
                timed_out=False,
            )

        timeout = min(float(req.timeout_seconds), float(_settings.MAX_TERMINAL_TIMEOUT_SECONDS))
        max_bytes = int(_settings.MAX_TERMINAL_OUTPUT_BYTES)
        start_time = time.time()
        process = await asyncio.create_subprocess_shell(
            req.command,
            cwd=str(project_root),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=cls._get_process_env(),
            start_new_session=True,
            limit=max(64 * 1024, min(max_bytes, 4 * 1024 * 1024)),
        )

        timed_out = False
        try:
            # Stream stdout/stderr with a running byte cap (e.g. `cat
            # /dev/zero`) instead of buffering the full output in memory.
            stdout, stderr, truncated = await asyncio.wait_for(
                communicate_with_cap(
                    process,
                    max_bytes,
                    on_limit_exceeded=lambda: terminate_process_group(process),
                ),
                timeout=timeout,
            )
            out_str = stdout.decode("utf-8", errors="replace")
            err_str = stderr.decode("utf-8", errors="replace")
            if truncated:
                err_str += f"\n[Output truncated at {max_bytes} bytes]"
            exit_code = process.returncode if process.returncode is not None else 0
        except asyncio.TimeoutError:
            await terminate_process_group(process)
            timed_out = True
            out_str = ""
            err_str = f"Command timed out after {timeout} seconds."
            exit_code = -1

        duration_ms = int((time.time() - start_time) * 1000)

        return TerminalRunResponse(
            command=req.command,
            exit_code=exit_code,
            stdout=out_str,
            stderr=err_str,
            duration_ms=duration_ms,
            timed_out=timed_out,
        )

    @classmethod
    async def handle_websocket(cls, websocket: WebSocket, project_path: str):
        await websocket.accept()
        from backend.core.config import settings as _settings
        from backend.core.security import resolve_project_root as _resolve_root

        try:
            resolved = _resolve_root(project_path)
            assert isinstance(resolved, Path)
            project_root = resolved
        except ValueError as exc:
            await websocket.send_json({"type": "error", "error": str(exc)})
            await websocket.close()
            return

        if not project_root.exists() or not project_root.is_dir():
            await websocket.send_json({
                "type": "error",
                "error": f"Directory '{project_path}' does not exist or is not accessible.",
            })
            await websocket.close()
            return

        if cls._active_ptys >= int(_settings.MAX_PTYS):
            await websocket.send_json({
                "type": "error",
                "error": f"Too many interactive terminals (limit {_settings.MAX_PTYS}). Close one and retry.",
            })
            await websocket.close()
            return
        cls._active_ptys += 1
        last_activity = time.monotonic()

        master_fd: int | None = None
        process: asyncio.subprocess.Process | None = None
        output_task: asyncio.Task | None = None
        receive_task: asyncio.Task | None = None
        wait_task: asyncio.Task | None = None

        async def stream_output() -> None:
            assert master_fd is not None
            decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
            while True:
                try:
                    chunk = await cls._read_from_fd(master_fd, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                text = decoder.decode(chunk)
                if text:
                    await websocket.send_json({"type": "output", "data": text})

            remaining = decoder.decode(b"", final=True)
            if remaining:
                await websocket.send_json({"type": "output", "data": remaining})

        async def receive_input() -> None:
            nonlocal last_activity
            assert master_fd is not None
            while True:
                if time.monotonic() - last_activity > cls._IDLE_TIMEOUT_SECONDS:
                    with contextlib.suppress(Exception):
                        await websocket.send_json({
                            "type": "error",
                            "error": "Terminal closed after 10 minutes of inactivity.",
                        })
                    break
                try:
                    msg_text = await asyncio.wait_for(websocket.receive_text(), timeout=60.0)
                except asyncio.TimeoutError:
                    continue
                last_activity = time.monotonic()
                try:
                    msg = json.loads(msg_text)
                except (TypeError, json.JSONDecodeError):
                    continue

                msg_type = msg.get("type")
                if msg_type == "input":
                    data = msg.get("data")
                    if isinstance(data, str) and data:
                        encoded = data.encode("utf-8")
                        if len(encoded) > cls._MAX_INPUT_BYTES:
                            with contextlib.suppress(Exception):
                                await websocket.send_json({
                                    "type": "error",
                                    "error": f"Input exceeds the {cls._MAX_INPUT_BYTES}-byte limit and was dropped.",
                                })
                            continue
                        # Never block the event loop on a full pty buffer.
                        await asyncio.to_thread(os.write, master_fd, encoded)
                elif msg_type == "resize":
                    cols = msg.get("cols")
                    rows = msg.get("rows")
                    if not isinstance(cols, int) or not isinstance(rows, int):
                        continue
                    if cols <= 0 or rows <= 0 or cols > 1000 or rows > 1000:
                        continue
                    pixel_width = msg.get("pixel_width", 0)
                    pixel_height = msg.get("pixel_height", 0)
                    cls._set_pty_size(
                        master_fd,
                        cols,
                        rows,
                        pixel_width if isinstance(pixel_width, int) else 0,
                        pixel_height if isinstance(pixel_height, int) else 0,
                    )

        try:
            try:
                master_fd, slave_fd = pty.openpty()
            except OSError as exc:
                # proot on Android may not provide /dev/pts. Report a
                # structured error instead of dropping the connection.
                await websocket.send_json({
                    "type": "error",
                    "error": (
                        "Interactive terminal is unavailable in this runtime "
                        f"(no PTY device: {exc}). Non-interactive commands "
                        "via POST /api/v1/terminal/run still work."
                    ),
                })
                await websocket.close()
                return
            cls._set_pty_size(master_fd, cls._DEFAULT_COLS, cls._DEFAULT_ROWS)

            shell = cls._resolve_shell()
            try:
                process = await asyncio.create_subprocess_exec(
                    sys.executable,
                    "-c",
                    cls._PTY_SHELL_BOOTSTRAP,
                    shell,
                    cwd=str(project_root),
                    stdin=slave_fd,
                    stdout=slave_fd,
                    stderr=slave_fd,
                    env=cls._get_pty_env(),
                )
            finally:
                os.close(slave_fd)

            await websocket.send_json({
                "type": "ready",
                "shell": shell,
                "pid": process.pid,
                "cols": cls._DEFAULT_COLS,
                "rows": cls._DEFAULT_ROWS,
            })

            output_task = asyncio.create_task(stream_output())
            receive_task = asyncio.create_task(receive_input())
            wait_task = asyncio.create_task(process.wait())

            done, _ = await asyncio.wait(
                {receive_task, wait_task},
                return_when=asyncio.FIRST_COMPLETED,
            )

            if wait_task in done:
                # A background child (e.g. `sleep 3600 &`) keeps the PTY slave
                # open, so stream_output never sees EIO. Give it a grace
                # period, then force-finalize instead of leaking the slot.
                try:
                    await asyncio.wait_for(output_task, timeout=5.0)
                except asyncio.TimeoutError:
                    await terminate_process_group(process)
                    with contextlib.suppress(OSError):
                        os.close(master_fd)
                    master_fd = None
                    output_task.cancel()
                await websocket.send_json({
                    "type": "exit",
                    "exit_code": process.returncode or 0,
                })
                await websocket.close()
            else:
                await receive_task
        except WebSocketDisconnect:
            pass
        except Exception as exc:
            with contextlib.suppress(Exception):
                await websocket.send_json({"type": "error", "error": str(exc)})
        finally:
            cls._active_ptys = max(0, cls._active_ptys - 1)
            if process is not None:
                await terminate_process_group(process)
            if master_fd is not None:
                with contextlib.suppress(OSError):
                    os.close(master_fd)
            for task in (output_task, receive_task, wait_task):
                if task is not None and not task.done():
                    task.cancel()
            tasks = [task for task in (output_task, receive_task, wait_task) if task is not None]
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)


terminal_service = TerminalService()
