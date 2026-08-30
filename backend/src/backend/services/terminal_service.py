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
from backend.schemas.terminal import TerminalRunRequest, TerminalRunResponse


class TerminalService:
    _DEFAULT_COLS = 80
    _DEFAULT_ROWS = 24
    _PTY_SHELL_BOOTSTRAP = (
        "import fcntl, os, sys, termios;"
        "os.setsid();"
        "fcntl.ioctl(0, termios.TIOCSCTTY, 0);"
        "os.execv(sys.argv[1], [sys.argv[1], '-i'])"
    )

    @classmethod
    def _get_process_env(cls) -> dict:
        env = os.environ.copy()
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
        env = os.environ.copy()
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        return env

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
        configured_shell = os.environ.get("SHELL", "")
        if configured_shell and Path(configured_shell).is_file() and os.access(configured_shell, os.X_OK):
            return configured_shell
        return "/bin/bash"

    @staticmethod
    async def _terminate_process(process: asyncio.subprocess.Process) -> None:
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

    @classmethod
    async def run_command(cls, req: TerminalRunRequest) -> TerminalRunResponse:
        project_root = Path(os.path.expanduser(req.project_path)).resolve()
        if not project_root.exists() or not project_root.is_dir():
            return TerminalRunResponse(
                command=req.command,
                exit_code=-1,
                stdout="",
                stderr=f"Directory '{req.project_path}' does not exist.",
                duration_ms=0,
                timed_out=False,
            )

        start_time = time.time()
        process = await asyncio.create_subprocess_shell(
            req.command,
            cwd=str(project_root),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=cls._get_process_env(),
        )

        timed_out = False
        try:
            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=req.timeout_seconds,
            )
            out_str = stdout.decode("utf-8", errors="replace")
            err_str = stderr.decode("utf-8", errors="replace")
            exit_code = process.returncode if process.returncode is not None else 0
        except asyncio.TimeoutError:
            process.kill()
            timed_out = True
            out_str = ""
            err_str = f"Command timed out after {req.timeout_seconds} seconds."
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
        project_root = Path(os.path.expanduser(project_path)).resolve()

        if not project_root.exists() or not project_root.is_dir():
            await websocket.send_json({
                "type": "error",
                "error": f"Directory '{project_path}' does not exist or is not accessible.",
            })
            await websocket.close()
            return

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
                    chunk = await asyncio.to_thread(os.read, master_fd, 4096)
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
            assert master_fd is not None
            while True:
                msg_text = await websocket.receive_text()
                try:
                    msg = json.loads(msg_text)
                except (TypeError, json.JSONDecodeError):
                    continue

                msg_type = msg.get("type")
                if msg_type == "input":
                    data = msg.get("data")
                    if isinstance(data, str) and data:
                        os.write(master_fd, data.encode("utf-8"))
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
            master_fd, slave_fd = pty.openpty()
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
                await output_task
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
            if process is not None:
                await cls._terminate_process(process)
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
