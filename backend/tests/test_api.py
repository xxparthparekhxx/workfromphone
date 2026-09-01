import asyncio
from importlib import import_module
import json
import subprocess
import time
from pathlib import Path

import pytest
from fastapi import WebSocketDisconnect
from fastapi.testclient import TestClient

from backend.core.config import settings
from backend.core.security import (
    assert_safe_outbound_url,
    is_public_path,
    sanitized_child_env,
)
from backend.main import app
from backend.schemas.llm import (
    ChatMessage,
    ChatTaskRequest,
    FetchModelsRequest,
    GeneralChatRequest,
    LLMConfig,
)
from backend.services.git_service import git_service
from backend.services.harness_service import harness_service
from backend.services.terminal_service import terminal_service

harness_service_module = import_module("backend.services.harness_service")
main_module = import_module("backend.main")
system_service_module = import_module("backend.services.system_service")

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


def test_chat_stream_handles_429_with_exponential_backoff(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
):
    attempts = 0
    sleeps = []

    async def fake_sleep(duration):
        sleeps.append(duration)

    monkeypatch.setattr(harness_service_module.asyncio, "sleep", fake_sleep)

    class FakeRateLimitedResponse:
        status_code = 429
        headers = {"retry-after": "0.1"}

        async def aread(self):
            return b'{"error":{"message":"Rate limit exceeded","code":429}}'

    class FakeSuccessResponse:
        status_code = 200

        async def aiter_lines(self):
            yield 'data: {"choices":[{"delta":{"content":"Recovered from 429"}}]}'
            yield "data: [DONE]"

    class FakeStream:
        def __init__(self, resp):
            self._resp = resp

        async def __aenter__(self):
            return self._resp

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
            nonlocal attempts
            attempts += 1
            if attempts == 1:
                return FakeStream(FakeRateLimitedResponse())
            return FakeStream(FakeSuccessResponse())

    monkeypatch.setattr(harness_service_module.httpx, "AsyncClient", FakeClient)
    request = ChatTaskRequest(
        project_path=str(tmp_path),
        messages=[ChatMessage(role="user", content="Hello")],
        llm_config=LLMConfig(model="test/model"),
    )

    async def collect_events():
        events = []
        async for event in harness_service.run_agentic_task_stream(request):
            events.append(json.loads(event.removeprefix("data: ").strip()))
        return events

    events = asyncio.run(collect_events())
    assert attempts == 2
    assert len(sleeps) == 1
    assert any("Rate limited (429)" in event.get("content", "") for event in events if event.get("type") == "status")
    assert any(event.get("content") == "Recovered from 429" for event in events if event.get("type") == "chunk")
    assert events[-1] == {"type": "done", "total_steps": 1}


def test_chat_stream_429_max_retries_exceeded(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
):
    attempts = 0

    async def fake_sleep(duration):
        pass

    monkeypatch.setattr(harness_service_module.asyncio, "sleep", fake_sleep)

    class FakeRateLimitedResponse:
        status_code = 429
        headers = {}

        async def aread(self):
            return b"Too Many Requests"

    class FakeStream:
        async def __aenter__(self):
            return FakeRateLimitedResponse()

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
            nonlocal attempts
            attempts += 1
            return FakeStream()

    monkeypatch.setattr(harness_service_module.httpx, "AsyncClient", FakeClient)
    request = ChatTaskRequest(
        project_path=str(tmp_path),
        messages=[ChatMessage(role="user", content="Hello")],
        llm_config=LLMConfig(model="test/model"),
    )

    async def collect_events():
        events = []
        async for event in harness_service.run_agentic_task_stream(request):
            events.append(json.loads(event.removeprefix("data: ").strip()))
        return events

    events = asyncio.run(collect_events())
    assert attempts == harness_service.MAX_RETRIES + 1
    error_event = next(e for e in events if e.get("type") == "error")
    assert "Rate limit exceeded after" in error_event["message"]


def test_fetch_models_handles_429_with_retry(monkeypatch: pytest.MonkeyPatch):
    attempts = 0

    async def fake_sleep(duration):
        pass

    monkeypatch.setattr(harness_service_module.asyncio, "sleep", fake_sleep)

    class FakeResponse:
        def __init__(self, status_code, json_data=None):
            self.status_code = status_code
            self._json = json_data or {}
            self.headers = {}

        def json(self):
            return self._json

    class FakeClient:
        def __init__(self, **_kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return False

        async def get(self, *_args, **_kwargs):
            nonlocal attempts
            attempts += 1
            if attempts == 1:
                return FakeResponse(429)
            return FakeResponse(200, {"data": [{"id": "custom/model", "name": "Custom Model"}]})

    monkeypatch.setattr(harness_service_module.httpx, "AsyncClient", FakeClient)
    req = FetchModelsRequest(base_url="https://openrouter.ai/api/v1", api_key="sk-test")
    resp = asyncio.run(harness_service.fetch_models(req))
    assert attempts == 2
    assert resp.count == 1
    assert resp.models[0].id == "custom/model"


def test_fetch_models_does_not_return_curated_fallback(
    monkeypatch: pytest.MonkeyPatch,
):
    class FakeResponse:
        status_code = 401
        text = '{"error":{"message":"Unauthorized"}}'
        headers = {}

        def json(self):
            return {"error": {"message": "Unauthorized"}}

    class FakeClient:
        def __init__(self, **_kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return False

        async def get(self, *_args, **_kwargs):
            return FakeResponse()

    monkeypatch.setattr(harness_service_module.httpx, "AsyncClient", FakeClient)
    req = FetchModelsRequest(base_url="https://openrouter.ai/api/v1", api_key="sk-bad")
    with pytest.raises(ValueError, match="Unauthorized"):
        asyncio.run(harness_service.fetch_models(req))


def test_fetch_models_skips_malformed_entries(
    monkeypatch: pytest.MonkeyPatch,
):
    class FakeResponse:
        status_code = 200
        headers = {}

        def json(self):
            return {
                "data": [
                    "not-a-dict",
                    {"id": "openai/gpt-4o", "name": "GPT-4o", "context_length": 128000.0},
                    {"name": "missing id"},
                    {"id": "anthropic/claude-sonnet-4", "pricing": "invalid"},
                ]
            }

    class FakeClient:
        def __init__(self, **_kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return False

        async def get(self, *_args, **_kwargs):
            return FakeResponse()

    monkeypatch.setattr(harness_service_module.httpx, "AsyncClient", FakeClient)
    req = FetchModelsRequest(base_url="https://openrouter.ai/api/v1", api_key="sk-test")
    resp = asyncio.run(harness_service.fetch_models(req))
    assert [model.id for model in resp.models] == [
        "openai/gpt-4o",
        "anthropic/claude-sonnet-4",
    ]


def test_general_chat_stream_sends_openrouter_api_key(
    monkeypatch: pytest.MonkeyPatch,
):
    captured: dict = {}

    class FakeResponse:
        status_code = 200

        async def aiter_lines(self):
            yield 'data: {"choices":[{"delta":{"content":"Hi there"}}]}'
            yield (
                'data: {"choices":[{"delta":{"content":""}}],'
                '"usage":{"prompt_tokens":4,"completion_tokens":2,"total_tokens":6}}'
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

        def stream(self, method, url, headers=None, json=None):
            captured["method"] = method
            captured["url"] = url
            captured["headers"] = headers
            captured["json"] = json
            return FakeStream()

    monkeypatch.setattr(harness_service_module.httpx, "AsyncClient", FakeClient)
    request = GeneralChatRequest(
        messages=[ChatMessage(role="user", content="Hello")],
        llm_config=LLMConfig(
            api_key="  sk-or-test-key  ",
            model="openai/gpt-4o",
            base_url="https://openrouter.ai/api/v1",
        ),
        enable_web_search=True,
    )

    async def collect_events():
        events = []
        async for event in harness_service.run_general_chat_stream(request):
            events.append(json.loads(event.removeprefix("data: ").strip()))
        return events

    events = asyncio.run(collect_events())
    assert captured["method"] == "POST"
    assert captured["url"] == "https://openrouter.ai/api/v1/chat/completions"
    assert captured["headers"]["Authorization"] == "Bearer sk-or-test-key"
    assert captured["json"]["model"] == "openai/gpt-4o"
    assert "plugins" not in captured["json"]
    assert {"role": "user", "content": "Hello"} in captured["json"]["messages"]
    assert any(event.get("type") == "chunk" and event.get("content") == "Hi there" for event in events)
    assert events[-1]["type"] == "done"


def test_chat_stream_continuous_loop_with_tools_and_text(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
):
    step = 0
    demo_file = tmp_path / "hello.txt"
    demo_file.write_text("initial content", encoding="utf-8")

    class Step1Response:
        status_code = 200

        async def aiter_lines(self):
            # Model outputs text thought AND tool call
            yield 'data: {"choices":[{"delta":{"content":"I will inspect the file first.\\n"}}]}'
            yield (
                'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1",'
                '"type":"function","function":{"name":"read_file",'
                '"arguments":"{\\"relative_path\\":\\"hello.txt\\"}"}}]}}]}'
            )
            yield "data: [DONE]"

    class Step2Response:
        status_code = 200

        async def aiter_lines(self):
            # Model outputs text thought AND final task_completed tool call
            yield 'data: {"choices":[{"delta":{"content":"File verified. All work is complete."}}]}'
            yield (
                'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_2",'
                '"type":"function","function":{"name":"task_completed",'
                '"arguments":"{\\"summary\\":\\"Read and verified hello.txt\\"}"}}]}}]}'
            )
            yield "data: [DONE]"

    class FakeStream:
        def __init__(self, resp):
            self._resp = resp

        async def __aenter__(self):
            return self._resp

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
            nonlocal step
            step += 1
            if step == 1:
                return FakeStream(Step1Response())
            return FakeStream(Step2Response())

    monkeypatch.setattr(harness_service_module.httpx, "AsyncClient", FakeClient)
    request = ChatTaskRequest(
        project_path=str(tmp_path),
        messages=[ChatMessage(role="user", content="Inspect hello.txt")],
        llm_config=LLMConfig(model="test/model"),
    )

    async def collect_events():
        events = []
        async for event in harness_service.run_agentic_task_stream(request):
            events.append(json.loads(event.removeprefix("data: ").strip()))
        return events

    events = asyncio.run(collect_events())
    assert step == 2
    tool_starts = [e["tool"] for e in events if e.get("type") == "tool_call_start"]
    assert tool_starts == ["read_file", "task_completed"]
    assert any("I will inspect the file first" in e.get("content", "") for e in events if e.get("type") == "chunk")
    assert any("File verified. All work is complete" in e.get("content", "") for e in events if e.get("type") == "chunk")
    assert events[-1] == {"type": "done", "total_steps": 2}


def test_chat_stream_extracts_text_embedded_tool_calls(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
):
    step = 0
    demo_file = tmp_path / "hello.txt"
    demo_file.write_text("some content", encoding="utf-8")

    class Step1Response:
        status_code = 200

        async def aiter_lines(self):
            # Model outputs XML-style tool call in text stream (e.g. DeepSeek R1 style)
            yield 'data: {"choices":[{"delta":{"content":"Let me check <function=read_file>{\\"relative_path\\": \\"hello.txt\\"}</function>"}}]}'
            yield "data: [DONE]"

    class Step2Response:
        status_code = 200

        async def aiter_lines(self):
            # Final text response
            yield 'data: {"choices":[{"delta":{"content":"Content is some content."}}]}'
            yield "data: [DONE]"

    class FakeStream:
        def __init__(self, resp):
            self._resp = resp

        async def __aenter__(self):
            return self._resp

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
            nonlocal step
            step += 1
            if step == 1:
                return FakeStream(Step1Response())
            return FakeStream(Step2Response())

    monkeypatch.setattr(harness_service_module.httpx, "AsyncClient", FakeClient)
    request = ChatTaskRequest(
        project_path=str(tmp_path),
        messages=[ChatMessage(role="user", content="Read hello.txt")],
        llm_config=LLMConfig(model="test/model"),
    )

    async def collect_events():
        events = []
        async for event in harness_service.run_agentic_task_stream(request):
            events.append(json.loads(event.removeprefix("data: ").strip()))
        return events

    events = asyncio.run(collect_events())
    assert step == 2
    tool_starts = [e["tool"] for e in events if e.get("type") == "tool_call_start"]
    assert tool_starts == ["read_file"]
    assert events[-1] == {"type": "done", "total_steps": 2}


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


def _run_git(repo: Path, *args: str) -> None:
    subprocess.run(
        ["git", *args],
        cwd=repo,
        check=True,
        capture_output=True,
    )


@pytest.fixture
def git_repo(tmp_path: Path) -> Path:
    _run_git(tmp_path, "init", "-q", ".")
    _run_git(tmp_path, "config", "user.email", "test@example.com")
    _run_git(tmp_path, "config", "user.name", "Test")
    (tmp_path / "old name.txt").write_text("a\n", encoding="utf-8")
    (tmp_path / "café.txt").write_text("b\n", encoding="utf-8")
    (tmp_path / "plain.txt").write_text("c\n", encoding="utf-8")
    _run_git(tmp_path, "add", "-A")
    _run_git(tmp_path, "commit", "-qm", "init")
    return tmp_path


def test_git_status_reports_renames_as_usable_paths(git_repo: Path):
    _run_git(git_repo, "mv", "old name.txt", "new name.txt")

    status = asyncio.run(git_service.get_status(str(git_repo)))
    assert status.is_repo

    renamed = [change for change in status.staged if change.status == "R"]
    assert len(renamed) == 1
    # The path must be the new name alone, not "old -> new", so that it can be
    # handed straight back to git diff/restore.
    assert renamed[0].path == "new name.txt"
    assert renamed[0].old_path == "old name.txt"

    diff = asyncio.run(
        git_service.get_diff(str(git_repo), renamed[0].path, staged=True),
    )
    assert diff.diff.strip(), "the reported path did not resolve to a diff"


def test_git_status_reports_unquoted_non_ascii_paths(git_repo: Path):
    (git_repo / "café.txt").write_text("b\nchanged\n", encoding="utf-8")
    (git_repo / "unt räcked.txt").write_text("d\n", encoding="utf-8")
    (git_repo / "plain.txt").unlink()

    status = asyncio.run(git_service.get_status(str(git_repo)))

    unstaged = {change.path for change in status.unstaged}
    untracked = {change.path for change in status.untracked}
    # git C-quotes these without -z, e.g. "caf\303\251.txt".
    assert "café.txt" in unstaged
    assert "plain.txt" in unstaged
    assert "unt räcked.txt" in untracked
    assert not any('\\' in path or path.startswith('"') for path in unstaged | untracked)

    diff = asyncio.run(git_service.get_diff(str(git_repo), "café.txt"))
    assert "changed" in diff.diff


def test_git_status_preserves_surrounding_spaces_in_paths(git_repo: Path):
    (git_repo / " padded .txt").write_text("e\n", encoding="utf-8")

    status = asyncio.run(git_service.get_status(str(git_repo)))

    assert " padded .txt" in {change.path for change in status.untracked}


def test_git_status_is_clean_on_a_fresh_checkout(git_repo: Path):
    status = asyncio.run(git_service.get_status(str(git_repo)))
    assert status.is_repo
    assert status.is_clean
    assert status.branch
    assert not status.staged and not status.unstaged and not status.untracked


def test_top_processes_are_ranked_by_measured_cpu():
    service = system_service_module.SystemService()
    assert not service._processes_primed

    snapshot = asyncio.run(service.snapshot())
    processes = snapshot.top_processes

    assert processes
    assert service._processes_primed
    # Priming means the very first snapshot already carries real readings
    # rather than the all-zero values psutil returns for a first sample.
    assert any(process.cpu_percent > 0.0 for process in processes)
    assert processes == sorted(
        processes,
        key=lambda process: (process.cpu_percent, process.memory_percent),
        reverse=True,
    )


# ---------------------------------------------------------------------------
# Preview registry / proxy
# ---------------------------------------------------------------------------


from backend.services.preview_service import preview_registry  # noqa: E402
from backend.services.preview_service import PreviewRegistry  # noqa: E402
from backend.services import preview_service as preview_service_module  # noqa: E402


@pytest.fixture
def reset_preview_registry():
    """Ensure each preview test starts with an empty registry."""
    snapshot = list(preview_registry._entries.values())
    listeners = list(preview_registry._listeners)
    preview_registry._entries.clear()
    yield
    preview_registry._entries.clear()
    for entry in snapshot:
        preview_registry._entries[entry.id] = entry
    preview_registry._listeners.clear()
    for listener in listeners:
        preview_registry._listeners.add(listener)


def _start_preview_upstream(directory: Path, routes: dict[str, tuple[int, str, str]]) -> int:
    """Spin up a tiny HTTP server in a background thread for proxy tests."""

    import http.server
    import socketserver
    import threading

    class _Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802
            route = routes.get(self.path)
            if route is None:
                self.send_response(404)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(b"not found")
                return
            status, content_type, body = route
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body.encode("utf-8"))))
            self.end_headers()
            self.wfile.write(body.encode("utf-8"))

        def log_message(self, format: str, *args) -> None:  # noqa: A002
            return

    server = socketserver.TCPServer(("127.0.0.1", 0), _Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread


def test_preview_register_and_list_round_trip(tmp_path: Path, reset_preview_registry):
    project = tmp_path / "demo"
    project.mkdir()

    register = client.post(
        "/api/v1/preview/register",
        json={
            "project_path": str(project),
            "port": 8080,
            "label": "Vite dev server",
            "source": "llm",
        },
    )
    assert register.status_code == 200
    entry = register.json()["entry"]
    assert entry["label"] == "Vite dev server"
    assert entry["port"] == 8080
    assert entry["source"] == "llm"
    assert entry["id"].startswith("prev_8080_")

    listing = client.get(
        "/api/v1/preview",
        params={"project_path": str(project)},
    )
    assert listing.status_code == 200
    ids = [item["id"] for item in listing.json()["entries"]]
    assert ids == [entry["id"]]

    other_listing = client.get(
        "/api/v1/preview",
        params={"project_path": "/tmp/some/other/project"},
    )
    assert other_listing.status_code == 200
    assert other_listing.json()["entries"] == []

    removed = client.post(
        "/api/v1/preview/unregister",
        json={"id": entry["id"]},
    )
    assert removed.status_code == 200

    after = client.get(
        "/api/v1/preview",
        params={"project_path": str(project)},
    )
    assert after.json()["entries"] == []


def test_preview_register_persists_across_instances(tmp_path: Path):
    """Two registries should be backed by independent state in production."""
    project = tmp_path / "demo"
    project.mkdir()
    registry_a = PreviewRegistry()
    registry_b = PreviewRegistry()
    asyncio.run(registry_a.register(
        project_path=str(project),
        port=9000,
        label="a-only",
    ))
    assert registry_a.list_for_project(str(project))
    assert not registry_b.list_for_project(str(project))


def test_preview_unregister_missing_returns_404(tmp_path: Path, reset_preview_registry):
    resp = client.post(
        "/api/v1/preview/unregister",
        json={"id": "does-not-exist"},
    )
    assert resp.status_code == 404


def test_preview_proxy_proxies_assets_and_rewrites_spa_paths(
    tmp_path: Path, reset_preview_registry
):
    project = tmp_path / "demo"
    project.mkdir()

    server, thread = _start_preview_upstream(
        project,
        routes={
            "/": (200, "text/html", "<h1>SPA root</h1>"),
            "/assets/app.js": (200, "application/javascript", "console.log('hi')"),
            "/dashboard": (404, "text/plain", "not found"),
            "/favicon.ico": (404, "text/plain", "not found"),
        },
    )
    try:
        port = server.server_address[1]
        registered = client.post(
            "/api/v1/preview/register",
            json={
                "project_path": str(project),
                "port": port,
                "label": "test",
            },
        )
        entry_id = registered.json()["entry"]["id"]

        # Static asset passes through untouched.
        asset = client.get(f"/api/v1/preview/proxy/{entry_id}/assets/app.js")
        assert asset.status_code == 200
        assert asset.headers["content-type"].startswith("application/javascript")
        assert asset.text == "console.log('hi')"

        # Root returns the actual index.
        root = client.get(f"/api/v1/preview/proxy/{entry_id}/")
        assert root.status_code == 200
        assert "<h1>SPA root</h1>" in root.text

        # SPA client route falls back to / (SPA rewrite).
        spa = client.get(f"/api/v1/preview/proxy/{entry_id}/dashboard")
        assert spa.status_code == 200
        assert "<h1>SPA root</h1>" in spa.text

        # An asset-shaped 404 stays a 404 (we never rewrite file paths).
        favicon = client.get(f"/api/v1/preview/proxy/{entry_id}/favicon.ico")
        assert favicon.status_code == 404
    finally:
        server.shutdown()
        thread.join(timeout=2)


def test_preview_proxy_unknown_entry_returns_404(tmp_path: Path, reset_preview_registry):
    resp = client.get("/api/v1/preview/proxy/nope/")
    assert resp.status_code == 404


def test_preview_register_preview_tool_uses_llm_source(tmp_path: Path, reset_preview_registry):
    project = tmp_path / "demo"
    project.mkdir()

    output = asyncio.run(
        harness_service.execute_tool(
            project,
            "register_preview",
            {"port": 4200, "label": "ng serve", "base_path": "/app/"},
        ),
    )
    assert "Registered preview" in output

    listing = client.get(
        "/api/v1/preview",
        params={"project_path": str(project)},
    )
    entries = listing.json()["entries"]
    assert len(entries) == 1
    assert entries[0]["source"] == "llm"
    assert entries[0]["label"] == "ng serve"
    assert entries[0]["base_path"] == "/app/"


def test_preview_unregister_tool_supports_all(tmp_path: Path, reset_preview_registry):
    project = tmp_path / "demo"
    project.mkdir()

    asyncio.run(harness_service.execute_tool(
        project, "register_preview", {"port": 7000, "label": "a"},
    ))
    asyncio.run(harness_service.execute_tool(
        project, "register_preview", {"port": 7001, "label": "b"},
    ))

    listing = client.get(
        "/api/v1/preview",
        params={"project_path": str(project)},
    )
    assert len(listing.json()["entries"]) == 2

    output = asyncio.run(
        harness_service.execute_tool(project, "unregister_preview", {"all": True}),
    )
    assert "Removed 2" in output

    listing = client.get(
        "/api/v1/preview",
        params={"project_path": str(project)},
    )
    assert listing.json()["entries"] == []


def test_preview_register_tool_rejects_bad_port(tmp_path: Path, reset_preview_registry):
    project = tmp_path / "demo"
    project.mkdir()

    output = asyncio.run(
        harness_service.execute_tool(
            project,
            "register_preview",
            {"port": "nope", "label": "x"},
        ),
    )
    assert "Error" in output
    assert client.get(
        "/api/v1/preview",
        params={"project_path": str(project)},
    ).json()["entries"] == []


def test_robots_txt_anti_crawling():
    resp = client.get("/robots.txt")
    assert resp.status_code == 200
    assert "Disallow: /" in resp.text
    assert "noindex" in resp.headers.get("X-Robots-Tag", "")


def _install_artifact_service(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("WFP_STORAGE_DIR", str(tmp_path / "artifacts"))
    from backend.api.v1.endpoints import artifacts as artifacts_ep
    from backend.services.artifact_service import ArtifactService
    import backend.services.artifact_service as art_module

    service = ArtifactService()
    art_module.artifact_service = service
    artifacts_ep.artifact_service = service
    main_module.artifact_service = service
    return service


def test_publish_and_view_artifact(tmp_path: Path, monkeypatch):
    _install_artifact_service(tmp_path, monkeypatch)

    payload = {
        "title": "Interactive React Demo",
        "content": "<h1>Hello Artifact</h1><script>console.log('test');</script>",
        "content_type": "text/html",
        "is_sandboxed": True,
    }

    pub_resp = client.post("/api/v1/artifacts/publish", json=payload)
    assert pub_resp.status_code == 200
    data = pub_resp.json()
    token = data["token"]
    assert token
    assert "/share/" in data["share_url"]

    # View shared artifact via public route
    view_resp = client.get(f"/share/{token}")
    assert view_resp.status_code == 200
    assert "<h1>Hello Artifact</h1>" in view_resp.text
    assert "noindex" in view_resp.headers.get("X-Robots-Tag", "")
    assert "sandbox allow-scripts" in view_resp.headers.get("Content-Security-Policy", "")
    assert "unsafe-eval" not in view_resp.headers.get("Content-Security-Policy", "")


def test_pin_protected_artifact(tmp_path: Path, monkeypatch):
    _install_artifact_service(tmp_path, monkeypatch)

    payload = {
        "title": "Secret Dashboard",
        "content": "<p>Secret Content</p>",
        "content_type": "text/html",
        "is_sandboxed": True,
        "pin_code": "9876",
    }

    pub_resp = client.post("/api/v1/artifacts/publish", json=payload)
    assert pub_resp.status_code == 200
    token = pub_resp.json()["token"]

    # View without PIN shows unlock form
    view_resp = client.get(f"/share/{token}")
    assert view_resp.status_code == 200
    assert "Protected Artifact" in view_resp.text
    assert "Secret Content" not in view_resp.text

    # Query-string PINs must not unlock the artifact.
    leaked = client.get(f"/share/{token}?pin=9876")
    assert leaked.status_code == 200
    assert "Secret Content" not in leaked.text

    unlocked_resp = client.post(f"/share/{token}", data={"pin": "9876"})
    assert unlocked_resp.status_code == 200
    assert "<p>Secret Content</p>" in unlocked_resp.text


def test_web_search_endpoint():
    resp = client.post("/api/v1/search", json={"query": "fastapi python", "limit": 3})
    assert resp.status_code == 200
    data = resp.json()
    assert "query" in data
    assert "results" in data
    assert isinstance(data["results"], list)


def test_docs_require_auth_when_access_token_is_set():
    previous_token = settings.ACCESS_TOKEN
    settings.ACCESS_TOKEN = "test-access-token"
    try:
        assert client.get("/docs").status_code == 401
        assert client.get("/openapi.json").status_code == 401
        assert client.get("/redoc").status_code == 401
        assert client.get("/api/v1/health").status_code == 200
    finally:
        settings.ACCESS_TOKEN = previous_token


def test_share_prefix_is_not_an_auth_bypass():
    assert is_public_path("/share/abc") is True
    assert is_public_path("/share/../api/v1/system/snapshot") is False
    assert is_public_path("/share/foo/extra") is False

    previous_token = settings.ACCESS_TOKEN
    settings.ACCESS_TOKEN = "test-access-token"
    try:
        assert client.get("/share/../api/v1/system/snapshot").status_code == 401
    finally:
        settings.ACCESS_TOKEN = previous_token


def test_websocket_rejects_foreign_browser_origin():
    with pytest.raises(WebSocketDisconnect) as denied:
        with client.websocket_connect(
            "/api/v1/system/ws",
            headers={"Origin": "https://evil.example"},
        ) as websocket:
            websocket.receive_json()
    assert denied.value.code == 4403


def test_sanitized_child_env_drops_access_token(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("ACCESS_TOKEN", "super-secret")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    env = sanitized_child_env({"TERM": "xterm-256color"})
    assert "ACCESS_TOKEN" not in env
    assert "OPENAI_API_KEY" not in env
    assert env["TERM"] == "xterm-256color"


def test_outbound_url_blocks_cloud_metadata():
    with pytest.raises(ValueError, match="link-local|metadata|not allowed"):
        assert_safe_outbound_url("http://169.254.169.254/latest/meta-data")
    with pytest.raises(ValueError, match="not allowed"):
        assert_safe_outbound_url("http://metadata.google.internal/")
    with pytest.raises(ValueError, match="http or https"):
        assert_safe_outbound_url("file:///etc/passwd")
    assert_safe_outbound_url("http://127.0.0.1:11434/v1")


def test_preview_register_rejects_privileged_ports(reset_preview_registry):
    resp = client.post(
        "/api/v1/preview/register",
        json={
            "project_path": "/tmp",
            "port": 22,
            "label": "ssh",
        },
    )
    assert resp.status_code == 400


def test_preview_proxy_strips_authorization(
    tmp_path: Path, reset_preview_registry
):
    captured: dict[str, str] = {}

    import http.server
    import socketserver
    import threading

    class _Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802
            captured["authorization"] = self.headers.get("Authorization", "")
            body = b"ok"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format: str, *args) -> None:  # noqa: A002
            return

    server = socketserver.TCPServer(("127.0.0.1", 0), _Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        port = server.server_address[1]
        registered = client.post(
            "/api/v1/preview/register",
            json={
                "project_path": str(tmp_path),
                "port": port,
                "label": "echo",
            },
        )
        entry_id = registered.json()["entry"]["id"]
        proxied = client.get(
            f"/api/v1/preview/proxy/{entry_id}/",
            headers={"Authorization": "Bearer leaked-token"},
        )
        assert proxied.status_code == 200
        assert captured["authorization"] == ""
    finally:
        server.shutdown()
        thread.join(timeout=2)


def test_git_diff_does_not_follow_symlink_outside_project(tmp_path: Path):
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init"], cwd=repo, check=True, capture_output=True)
    secret = tmp_path / "secret.txt"
    secret.write_text("top-secret-value\n", encoding="utf-8")
    (repo / "leaked").symlink_to(secret)

    diff = asyncio.run(git_service.get_diff(str(repo), "leaked"))
    assert "top-secret-value" not in diff.diff

