import asyncio
from importlib import import_module
import json
import time
from pathlib import Path

import pytest
from fastapi import WebSocketDisconnect
from fastapi.testclient import TestClient

from backend.core.config import settings
from backend.main import app
from backend.schemas.llm import ChatMessage, ChatTaskRequest, LLMConfig
from backend.services.harness_service import harness_service
from backend.services.terminal_service import terminal_service

harness_service_module = import_module("backend.services.harness_service")
main_module = import_module("backend.main")

client = TestClient(app)


def _receive_terminal_output_until(websocket, expected: str, max_messages: int = 100) -> str:
    output = ""
    for _ in range(max_messages):
        message = websocket.receive_json()
        if message["type"] == "output":
            output += message["data"]
            if expected in output:
                return output
        elif message["type"] == "error":
            pytest.fail(message["error"])
        elif message["type"] == "exit":
            pytest.fail(f"Shell exited before producing {expected!r}")
    pytest.fail(f"Terminal did not produce {expected!r}; output was {output!r}")


def test_health_endpoint():
    resp = client.get("/api/v1/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"


def test_system_snapshot_and_stream():
    resp = client.get("/api/v1/system/snapshot")
    assert resp.status_code == 200
    data = resp.json()
    assert data["identity"]["hostname"]
    assert data["identity"]["architecture"]
    assert data["cpu"]["logical_cores"] > 0
    assert data["memory"]["total_bytes"] > 0
    assert data["backend_process"]["pid"] > 0

    with client.websocket_connect(
        "/api/v1/system/ws",
        params={"interval": 1},
    ) as websocket:
        streamed = websocket.receive_json()
        assert streamed["timestamp"]
        assert streamed["cpu"]["usage_percent"] >= 0


def test_access_token_protects_capability_endpoints():
    previous_token = settings.ACCESS_TOKEN
    settings.ACCESS_TOKEN = "test-access-token"
    try:
        denied = client.get("/api/v1/system/snapshot")
        assert denied.status_code == 401
        assert client.get("/api/v1/health").status_code == 200

        allowed = client.get(
            "/api/v1/system/snapshot",
            headers={"Authorization": "Bearer test-access-token"},
        )
        assert allowed.status_code == 200

        with pytest.raises(WebSocketDisconnect) as denied_websocket:
            with client.websocket_connect("/api/v1/system/ws") as websocket:
                websocket.receive_json()
        assert denied_websocket.value.code == 4401
    finally:
        settings.ACCESS_TOKEN = previous_token


def test_chat_stream_reports_exact_accumulated_usage(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
):
    class FakeResponse:
        status_code = 200

        async def aiter_lines(self):
            yield 'data: {"choices":[{"delta":{"content":"Hello"}}]}'
            yield (
                'data: {"choices":[{"delta":{"content":""}}],'
                '"usage":{"prompt_tokens":120,"completion_tokens":8,'
                '"total_tokens":128,"cost":0.002,'
                '"prompt_tokens_details":{"cached_tokens":20},'
                '"completion_tokens_details":{"reasoning_tokens":3}}}'
            )
            yield "data: [DONE]"

    class FakeStream:
        async def __aenter__(self):
            return FakeResponse()

        async def __aexit__(self, *_args):
            return False

    class FakeClient:
        def __init__(self, **_kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return False

        def stream(self, *_args, **_kwargs):
            return FakeStream()

    monkeypatch.setattr(harness_service_module.httpx, "AsyncClient", FakeClient)
    request = ChatTaskRequest(
        project_path=str(tmp_path),
        messages=[ChatMessage(role="user", content="Say hello")],
        llm_config=LLMConfig(model="test/model"),
    )

    async def collect_events():
        events = []
        async for event in harness_service.run_agentic_task_stream(request):
            events.append(json.loads(event.removeprefix("data: ").strip()))
        return events

    events = asyncio.run(collect_events())
    usage = next(event["usage"] for event in events if event["type"] == "usage")
    assert usage == {
        "prompt_tokens": 120,
        "completion_tokens": 8,
        "total_tokens": 128,
        "reasoning_tokens": 3,
        "cached_tokens": 20,
        "cost": 0.002,
        "context_tokens": 128,
        "exact": True,
    }
    assert events[-1] == {"type": "done", "total_steps": 1}


def test_terminal_run_endpoint(tmp_path: Path):
    resp = client.post(
        "/api/v1/terminal/run",
        json={
            "project_path": str(tmp_path),
            "command": "echo 'Hello from Terminal'",
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["exit_code"] == 0
    assert "Hello from Terminal" in data["stdout"]


def test_terminal_websocket_runs_persistent_resizable_pty(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
):
    child = tmp_path / "child"
    child.mkdir()
    monkeypatch.setenv("SHELL", "/bin/sh")

    with client.websocket_connect(
        "/api/v1/terminal/ws",
        params={"project_path": str(tmp_path)},
    ) as websocket:
        ready = websocket.receive_json()
        assert ready["type"] == "ready"
        assert ready["shell"] == "/bin/sh"
        assert ready["cols"] == 80
        assert ready["rows"] == 24

        websocket.send_json({"type": "resize", "cols": 93, "rows": 31})
        websocket.send_json({
            "type": "input",
            "data": (
                "stty -echo; "
                "printf '\\137\\137SIZE\\137\\137'; "
                "stty size\n"
            ),
        })
        size_output = _receive_terminal_output_until(websocket, "__SIZE__31 93")
        assert "__SIZE__31 93" in size_output

        websocket.send_json({
            "type": "input",
            "data": (
                "python -c 'import os; "
                'print("__TTY__", os.isatty(0), os.tcgetpgrp(0))\'\n'
            ),
        })
        tty_output = _receive_terminal_output_until(websocket, "__TTY__ True ")
        assert "__TTY__ True " in tty_output

        websocket.send_json({
            "type": "input",
            "data": (
                "cd child; "
                "printf '\\137\\137CWD\\137\\137'; "
                "pwd\n"
            ),
        })
        cwd_output = _receive_terminal_output_until(websocket, "__CWD__")
        while str(child) not in cwd_output:
            cwd_output += _receive_terminal_output_until(websocket, str(child))
        assert str(child) in cwd_output

        websocket.send_json({
            "type": "input",
            "data": "printf '\\137\\137SLEEPING\\137\\137\\n'; sleep 30\n",
        })
        _receive_terminal_output_until(websocket, "__SLEEPING__")
        interrupt_started = time.monotonic()
        time.sleep(0.1)
        websocket.send_json({"type": "input", "data": "\u0003"})
        websocket.send_json({
            "type": "input",
            "data": "printf '\\137\\137ALIVE\\137\\137\\n'\n",
        })
        alive_output = _receive_terminal_output_until(websocket, "__ALIVE__")
        assert "__ALIVE__" in alive_output
        assert time.monotonic() - interrupt_started < 3

        websocket.send_json({"type": "input", "data": "exit\n"})
        for _ in range(20):
            message = websocket.receive_json()
            if message["type"] == "exit":
                assert message["exit_code"] == 0
                break
        else:
            pytest.fail("Terminal did not report shell exit")


def test_terminal_websockets_have_independent_ptys(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
):
    monkeypatch.setenv("SHELL", "/bin/sh")

    class QueueWebSocket:
        def __init__(self):
            self.incoming: asyncio.Queue[str | None] = asyncio.Queue()
            self.outgoing: asyncio.Queue[dict] = asyncio.Queue()

        async def accept(self):
            pass

        async def receive_text(self):
            message = await self.incoming.get()
            if message is None:
                raise WebSocketDisconnect()
            return message

        async def send_json(self, message):
            await self.outgoing.put(message)

        async def close(self):
            pass

    async def receive_until(websocket: QueueWebSocket, expected: str) -> str:
        output = ""
        while expected not in output:
            message = await asyncio.wait_for(websocket.outgoing.get(), timeout=5)
            if message["type"] == "output":
                output += message["data"]
            elif message["type"] == "error":
                pytest.fail(message["error"])
        return output

    async def run_concurrent_terminals():
        first = QueueWebSocket()
        second = QueueWebSocket()
        first_task = asyncio.create_task(
            terminal_service.handle_websocket(first, str(tmp_path)),
        )
        second_task = asyncio.create_task(
            terminal_service.handle_websocket(second, str(tmp_path)),
        )

        try:
            first_ready = await asyncio.wait_for(first.outgoing.get(), timeout=5)
            second_ready = await asyncio.wait_for(second.outgoing.get(), timeout=5)
            assert first_ready["type"] == "ready"
            assert second_ready["type"] == "ready"
            assert first_ready["pid"] != second_ready["pid"]

            await first.incoming.put(json.dumps({
                "type": "input",
                "data": "stty -echo; printf '\\137\\137ONE\\137\\137\\n'\n",
            }))
            await second.incoming.put(json.dumps({
                "type": "input",
                "data": "stty -echo; printf '\\137\\137TWO\\137\\137\\n'\n",
            }))

            first_output, second_output = await asyncio.gather(
                receive_until(first, "__ONE__"),
                receive_until(second, "__TWO__"),
            )
            assert "__TWO__" not in first_output
            assert "__ONE__" not in second_output
        finally:
            await first.incoming.put(None)
            await second.incoming.put(None)
            await asyncio.gather(first_task, second_task)

    asyncio.run(run_concurrent_terminals())


def test_fs_file_operations(tmp_path: Path):
    # 1. Create file
    create_resp = client.post(
        "/api/v1/fs/create",
        json={
            "project_path": str(tmp_path),
            "relative_path": "hello.txt",
            "is_dir": False,
        },
    )
    assert create_resp.status_code == 200

    # 2. Write file
    write_resp = client.post(
        "/api/v1/fs/file",
        json={
            "project_path": str(tmp_path),
            "relative_path": "hello.txt",
            "content": "Line 1\nLine 2\nLine 3",
        },
    )
    assert write_resp.status_code == 200

    # 3. Read file
    read_resp = client.get(
        "/api/v1/fs/file",
        params={
            "project_path": str(tmp_path),
            "relative_path": "hello.txt",
        },
    )
    assert read_resp.status_code == 200
    assert "Line 2" in read_resp.json()["content"]

    # 4. Delete file
    del_resp = client.request(
        "DELETE",
        "/api/v1/fs/file",
        json={
            "project_path": str(tmp_path),
            "relative_path": "hello.txt",
        },
    )
    assert del_resp.status_code == 200


def test_fs_project_file_index_is_relative_filtered_and_bounded(tmp_path: Path):
    (tmp_path / "lib").mkdir()
    (tmp_path / "lib" / "main.dart").write_text("void main() {}")
    (tmp_path / "README.md").write_text("# Project")
    (tmp_path / ".git").mkdir()
    (tmp_path / ".git" / "config").write_text("[core]")

    response = client.get(
        "/api/v1/fs/project-files",
        params={"project_path": str(tmp_path), "limit": 1},
    )

    assert response.status_code == 200
    assert response.json() == {"files": ["README.md"], "truncated": True}

    full_response = client.get(
        "/api/v1/fs/project-files",
        params={"project_path": str(tmp_path)},
    )
    assert full_response.status_code == 200
    assert full_response.json() == {
        "files": ["README.md", "lib/main.dart"],
        "truncated": False,
    }


def test_fs_binary_upload_and_download(tmp_path: Path):
    assets = tmp_path / "assets"
    assets.mkdir()
    binary = b"\x00\x01\xffWorkFromPhone\x00"

    upload = client.post(
        "/api/v1/fs/upload",
        data={
            "project_path": str(tmp_path),
            "relative_directory": "assets",
            "overwrite": "false",
        },
        files={"files": ("sample.bin", binary, "application/octet-stream")},
    )
    assert upload.status_code == 200
    assert upload.json()["files"][0]["path"] == "assets/sample.bin"
    assert (assets / "sample.bin").read_bytes() == binary

    conflict = client.post(
        "/api/v1/fs/upload",
        data={
            "project_path": str(tmp_path),
            "relative_directory": "assets",
            "overwrite": "false",
        },
        files={"files": ("sample.bin", b"replacement")},
    )
    assert conflict.status_code == 409
    assert (assets / "sample.bin").read_bytes() == binary

    download = client.get(
        "/api/v1/fs/download",
        params={
            "project_path": str(tmp_path),
            "relative_path": "assets/sample.bin",
        },
    )
    assert download.status_code == 200
    assert download.content == binary
    assert 'filename="sample.bin"' in download.headers["content-disposition"]

    traversal = client.post(
        "/api/v1/fs/upload",
        data={
            "project_path": str(tmp_path),
            "relative_directory": "../outside",
        },
        files={"files": ("nope.txt", b"blocked")},
    )
    assert traversal.status_code == 400


def test_fs_binary_upload_and_download(tmp_path: Path):
    nested = tmp_path / "assets"
    nested.mkdir()
    content = b"\x00\x01\xffWorkFromPhone\x00binary"

    upload = client.post(
        "/api/v1/fs/upload",
        data={
            "project_path": str(tmp_path),
            "relative_directory": "assets",
            "overwrite": "false",
        },
        files={
            "files": (
                "sample.bin",
                content,
                "application/octet-stream",
            ),
        },
    )
    assert upload.status_code == 200
    assert upload.json()["files"][0]["path"] == "assets/sample.bin"
    assert (nested / "sample.bin").read_bytes() == content

    duplicate = client.post(
        "/api/v1/fs/upload",
        data={
            "project_path": str(tmp_path),
            "relative_directory": "assets",
            "overwrite": "false",
        },
        files={"files": ("sample.bin", b"replacement")},
    )
    assert duplicate.status_code == 409

    download = client.get(
        "/api/v1/fs/download",
        params={
            "project_path": str(tmp_path),
            "relative_path": "assets/sample.bin",
        },
    )
    assert download.status_code == 200
    assert download.content == content
    assert 'filename="sample.bin"' in download.headers["content-disposition"]

    traversal = client.get(
        "/api/v1/fs/download",
        params={
            "project_path": str(tmp_path),
            "relative_path": "../outside.bin",
        },
    )
    assert traversal.status_code == 400


def test_cors_does_not_grant_arbitrary_origins():
    resp = client.get(
        "/api/v1/health",
        headers={"Origin": "https://evil.example"},
    )
    assert resp.status_code == 200
    assert "access-control-allow-origin" not in resp.headers
    assert "access-control-allow-credentials" not in resp.headers

    preflight = client.options(
        "/api/v1/terminal/run",
        headers={
            "Origin": "https://evil.example",
            "Access-Control-Request-Method": "POST",
        },
    )
    assert preflight.headers.get("access-control-allow-origin") != (
        "https://evil.example"
    )

    assert "*" not in main_module.resolve_cors_origins()
    assert "*" not in settings.CORS_ORIGINS


def test_wildcard_cors_origin_is_stripped(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(
        settings,
        "CORS_ORIGINS",
        ["http://localhost:3000", "*"],
    )
    assert main_module.resolve_cors_origins() == ["http://localhost:3000"]


@pytest.mark.parametrize(
    ("host", "expected"),
    [
        ("127.0.0.1", True),
        ("localhost", True),
        ("::1", True),
        ("[::1]", True),
        ("0.0.0.0", False),
        ("192.168.1.10", False),
        ("example.com", False),
    ],
)
def test_is_loopback_host(host: str, expected: bool):
    assert main_module.is_loopback_host(host) is expected


def test_public_bind_without_access_token_is_refused(
    monkeypatch: pytest.MonkeyPatch,
):
    monkeypatch.setattr(settings, "HOST", "0.0.0.0")
    monkeypatch.setattr(settings, "ACCESS_TOKEN", "")
    with pytest.raises(RuntimeError, match="ACCESS_TOKEN"):
        main_module.create_app()

    # A token, or staying on loopback, makes the same bind acceptable.
    monkeypatch.setattr(settings, "ACCESS_TOKEN", "token")
    main_module.verify_network_exposure()
    monkeypatch.setattr(settings, "ACCESS_TOKEN", "")
    monkeypatch.setattr(settings, "HOST", "127.0.0.1")
    main_module.verify_network_exposure()


def test_fs_errors_keep_their_status_codes(tmp_path: Path):
    missing = client.get(
        "/api/v1/fs/file",
        params={"project_path": str(tmp_path), "relative_path": "nope.txt"},
    )
    assert missing.status_code == 404

    traversal = client.get(
        "/api/v1/fs/file",
        params={
            "project_path": str(tmp_path),
            "relative_path": "../../etc/passwd",
        },
    )
    assert traversal.status_code == 400

    delete_missing = client.request(
        "DELETE",
        "/api/v1/fs/file",
        json={"project_path": str(tmp_path), "relative_path": "nope.txt"},
    )
    assert delete_missing.status_code == 404

    delete_root = client.request(
        "DELETE",
        "/api/v1/fs/file",
        json={"project_path": str(tmp_path), "relative_path": "."},
    )
    assert delete_root.status_code == 400
    assert tmp_path.is_dir()


def test_search_project_does_not_execute_shell_metacharacters(tmp_path: Path):
    (tmp_path / "notes.txt").write_text("harmless content\n", encoding="utf-8")
    marker = tmp_path / "injected.txt"

    output = asyncio.run(
        harness_service.execute_tool(
            tmp_path,
            "search_project",
            {"query": f"`touch {marker}`"},
        ),
    )

    assert not marker.exists(), "search query escaped into the shell"
    assert "No matches found" in output

    literal = asyncio.run(
        harness_service.execute_tool(
            tmp_path,
            "search_project",
            {"query": "harmless"},
        ),
    )
    assert "notes.txt" in literal


def test_search_project_accepts_a_query_starting_with_a_dash(tmp_path: Path):
    (tmp_path / "flags.txt").write_text("value --verbose here\n", encoding="utf-8")

    output = asyncio.run(
        harness_service.execute_tool(
            tmp_path,
            "search_project",
            {"query": "--verbose"},
        ),
    )
    assert "flags.txt" in output
