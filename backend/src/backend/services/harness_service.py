import asyncio
import json
import os
import random
import re
from pathlib import Path
from typing import Any, AsyncGenerator, Dict, List, Optional

import httpx

from backend.services.preview_service import preview_registry
from backend.services.terminal_service import terminate_process_group
from backend.schemas.llm import (
    ChatMessage,
    ChatTaskRequest,
    FetchModelsRequest,
    FetchModelsResponse,
    LLMConfig,
    ModelInfo,
)


HARNESS_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "run_terminal_command",
            "description": "Execute a shell command inside the project root directory. Use this to run builds, tests, git commands, package managers, linter, etc.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "The exact shell command line to run (e.g. 'flutter analyze', 'pytest', 'git status', 'ls -la')",
                    },
                },
                "required": ["command"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read the contents of a file inside the project directory.",
            "parameters": {
                "type": "object",
                "properties": {
                    "relative_path": {
                        "type": "string",
                        "description": "File path relative to the project root directory",
                    },
                    "start_line": {
                        "type": "integer",
                        "description": "Optional 1-indexed starting line number",
                    },
                    "end_line": {
                        "type": "integer",
                        "description": "Optional 1-indexed ending line number",
                    },
                },
                "required": ["relative_path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": "Create a new file or overwrite an existing file with new content inside the project directory.",
            "parameters": {
                "type": "object",
                "properties": {
                    "relative_path": {
                        "type": "string",
                        "description": "File path relative to the project root directory",
                    },
                    "content": {
                        "type": "string",
                        "description": "The complete text content to write to the file",
                    },
                },
                "required": ["relative_path", "content"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "edit_file",
            "description": "Replace a specific text snippet with new text in a file inside the project directory.",
            "parameters": {
                "type": "object",
                "properties": {
                    "relative_path": {
                        "type": "string",
                        "description": "File path relative to the project root directory",
                    },
                    "target_text": {
                        "type": "string",
                        "description": "Exact snippet of text in the file to be replaced",
                    },
                    "replacement_text": {
                        "type": "string",
                        "description": "The replacement text",
                    },
                },
                "required": ["relative_path", "target_text", "replacement_text"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "list_directory",
            "description": "List files and folders in a subdirectory relative to the project root.",
            "parameters": {
                "type": "object",
                "properties": {
                    "relative_path": {
                        "type": "string",
                        "description": "Subdirectory path relative to project root (default empty for root)",
                    },
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "search_project",
            "description": "Search for a keyword or regex pattern in the project files.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search keyword or pattern",
                    },
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "register_preview",
            "description": (
                "Register a running local dev/preview server so the user can "
                "open it in the in-app browser. Call this AFTER starting a "
                "long-running HTTP server with run_terminal_command (e.g. "
                "`npm run dev`, `python -m http.server 8000`, "
                "`flutter run -d web-server --web-port=8080`). The "
                "registered port becomes immediately available as a "
                "previewable target with SPA-rewrite support."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "port": {
                        "type": "integer",
                        "description": "Loopback TCP port the server is listening on.",
                    },
                    "label": {
                        "type": "string",
                        "description": (
                            "Short human-readable label (e.g. 'Vite dev "
                            "server', 'Static demo')."
                        ),
                    },
                    "base_path": {
                        "type": "string",
                        "description": (
                            "Optional URL prefix the app is served under "
                            "(e.g. '/my-app/'). Leave empty for root."
                        ),
                    },
                    "id": {
                        "type": "string",
                        "description": (
                            "Optional explicit id; defaults to a stable id "
                            "derived from project_path + port."
                        ),
                    },
                },
                "required": ["port", "label"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "unregister_preview",
            "description": (
                "Remove a previously registered preview target when the "
                "underlying server has been stopped, or when the user no "
                "longer wants it listed."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "id": {
                        "type": "string",
                        "description": (
                            "Identifier returned by register_preview. If "
                            "omitted, every preview registered for the "
                            "current project is removed."
                        ),
                    },
                    "all": {
                        "type": "boolean",
                        "description": (
                            "If true, remove every preview registered for "
                            "the current project. Overrides `id`."
                        ),
                    },
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "task_completed",
            "description": (
                "Call this tool when you have fully accomplished the user's task, "
                "verified your changes with terminal commands or tests, and are ready "
                "to conclude the session. Provide a final summary of what was accomplished."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "summary": {
                        "type": "string",
                        "description": "Summary of the completed work, changes made, and verification results.",
                    },
                },
                "required": ["summary"],
            },
        },
    },
]


class HarnessService:
    MAX_RETRIES: int = 5
    INITIAL_BACKOFF_SECONDS: float = 1.0
    BACKOFF_FACTOR: float = 2.0
    MAX_BACKOFF_SECONDS: float = 30.0

    @classmethod
    def _extract_text_tool_calls(cls, text: str) -> List[Dict[str, Any]]:
        """
        Extracts tool calls from raw LLM text when open models (e.g. DeepSeek R1,
        Qwen 2.5 Coder, Llama 3.3) embed tool calls in text/XML format instead of
        native OpenAI tool_calls delta.
        """
        valid_tool_names = {t["function"]["name"] for t in HARNESS_TOOLS}
        extracted: List[Dict[str, Any]] = []
        call_idx = 0

        # Pattern 1: <function=tool_name>...</function>
        xml_func_pattern = re.compile(
            r"<function=([a-zA-Z0-9_-]+)>\s*(.*?)\s*</function>",
            re.DOTALL | re.IGNORECASE,
        )
        for match in xml_func_pattern.finditer(text):
            tool_name = match.group(1).strip()
            raw_args = match.group(2).strip()
            if tool_name in valid_tool_names:
                extracted.append({
                    "id": f"call_text_{call_idx}",
                    "type": "function",
                    "function": {"name": tool_name, "arguments": raw_args},
                })
                call_idx += 1

        if extracted:
            return extracted

        # Pattern 2: <tool_call>\s*{"name": ..., "arguments": ...}\s*</tool_call>
        tool_tag_pattern = re.compile(
            r"<tool_call>\s*(.*?)\s*</tool_call>",
            re.DOTALL | re.IGNORECASE,
        )
        for match in tool_tag_pattern.finditer(text):
            raw_json = match.group(1).strip()
            try:
                data = json.loads(raw_json)
                tool_name = data.get("name") or data.get("tool") or data.get("function")
                args = data.get("arguments") or data.get("args") or data.get("parameters") or {}
                if tool_name in valid_tool_names:
                    args_str = json.dumps(args) if isinstance(args, dict) else str(args)
                    extracted.append({
                        "id": f"call_text_{call_idx}",
                        "type": "function",
                        "function": {"name": tool_name, "arguments": args_str},
                    })
                    call_idx += 1
            except json.JSONDecodeError:
                pass

        if extracted:
            return extracted

        # Pattern 3: ```tool_call ... ``` or ```json with {"tool" or "name" or "action": ...}
        code_block_pattern = re.compile(
            r"```(?:tool_call|json|function_call)?\s*(\{.*?\})\s*```",
            re.DOTALL,
        )
        for match in code_block_pattern.finditer(text):
            raw_json = match.group(1).strip()
            try:
                data = json.loads(raw_json)
                tool_name = data.get("name") or data.get("tool") or data.get("action") or data.get("function")
                args = data.get("arguments") or data.get("args") or data.get("parameters") or data.get("action_input") or {}
                if tool_name in valid_tool_names:
                    args_str = json.dumps(args) if isinstance(args, dict) else str(args)
                    extracted.append({
                        "id": f"call_text_{call_idx}",
                        "type": "function",
                        "function": {"name": tool_name, "arguments": args_str},
                    })
                    call_idx += 1
            except json.JSONDecodeError:
                pass

        return extracted

    @classmethod
    def _parse_retry_after(cls, raw: Optional[str]) -> Optional[float]:
        if not raw:
            return None
        try:
            val = float(raw.strip())
            return val if val > 0 else None
        except (ValueError, TypeError):
            pass
        try:
            from datetime import datetime, timezone
            from email.utils import parsedate_to_datetime

            dt = parsedate_to_datetime(raw)
            now = datetime.now(timezone.utc)
            diff = (dt - now).total_seconds()
            return max(0.0, diff) if diff > 0 else None
        except Exception:
            return None

    @classmethod
    def _calculate_backoff(
        cls,
        attempt: int,
        retry_after: Optional[float] = None,
    ) -> float:
        calc_delay = cls.INITIAL_BACKOFF_SECONDS * (cls.BACKOFF_FACTOR ** attempt)
        jitter = random.uniform(0, min(0.5, calc_delay * 0.25))
        delay = min(calc_delay + jitter, cls.MAX_BACKOFF_SECONDS)
        if retry_after is not None and retry_after > 0:
            delay = min(max(delay, retry_after), cls.MAX_BACKOFF_SECONDS)
        return delay

    @staticmethod
    def _sanitize_path(project_root: Path, relative_path_str: str) -> Path:
        resolved = (project_root / relative_path_str.strip()).resolve()
        # Ensure path stays within or is root
        try:
            resolved.relative_to(project_root)
        except ValueError:
            raise ValueError(f"Path '{relative_path_str}' is outside project root directory.")
        return resolved

    @classmethod
    async def execute_tool(cls, project_root: Path, tool_name: str, args: Dict[str, Any]) -> str:
        try:
            if tool_name == "run_terminal_command":
                cmd = args.get("command", "")
                if not cmd.strip():
                    return "Error: Command cannot be empty."

                # Execute in project root
                process = await asyncio.create_subprocess_shell(
                    cmd,
                    cwd=str(project_root),
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                    start_new_session=True,
                )
                try:
                    stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=90.0)
                    out_str = stdout.decode("utf-8", errors="replace")
                    err_str = stderr.decode("utf-8", errors="replace")
                    exit_code = process.returncode

                    result = []
                    if out_str:
                        result.append(out_str)
                    if err_str:
                        result.append(f"[stderr]:\n{err_str}")
                    if exit_code != 0:
                        result.append(f"\n[Command exited with code {exit_code}]")
                    if not result:
                        result.append("(Command executed successfully with no output)")
                    return "\n".join(result)
                except asyncio.TimeoutError:
                    await terminate_process_group(process)
                    return "Error: Command timed out after 90 seconds."

            elif tool_name == "read_file":
                rel_path = args.get("relative_path", "")
                target_file = cls._sanitize_path(project_root, rel_path)
                if not target_file.exists() or not target_file.is_file():
                    return f"Error: File '{rel_path}' does not exist."

                start_line = args.get("start_line")
                end_line = args.get("end_line")

                with open(target_file, "r", encoding="utf-8", errors="replace") as f:
                    lines = f.readlines()

                if start_line is not None or end_line is not None:
                    s = max(1, start_line or 1)
                    e = min(len(lines), end_line or len(lines))
                    selected_lines = lines[s - 1 : e]
                    indexed = [f"{s + i}: {line}" for i, line in enumerate(selected_lines)]
                    return "".join(indexed)
                else:
                    return "".join(lines)

            elif tool_name == "write_file":
                rel_path = args.get("relative_path", "")
                content = args.get("content", "")
                target_file = cls._sanitize_path(project_root, rel_path)
                target_file.parent.mkdir(parents=True, exist_ok=True)
                with open(target_file, "w", encoding="utf-8") as f:
                    f.write(content)
                return f"Successfully wrote {len(content)} characters to '{rel_path}'."

            elif tool_name == "edit_file":
                rel_path = args.get("relative_path", "")
                target_text = args.get("target_text", "")
                replacement_text = args.get("replacement_text", "")

                target_file = cls._sanitize_path(project_root, rel_path)
                if not target_file.exists() or not target_file.is_file():
                    return f"Error: File '{rel_path}' does not exist."

                with open(target_file, "r", encoding="utf-8", errors="replace") as f:
                    content = f.read()

                if target_text not in content:
                    return f"Error: Target text not found in '{rel_path}'."

                count = content.count(target_text)
                new_content = content.replace(target_text, replacement_text, 1)
                with open(target_file, "w", encoding="utf-8") as f:
                    f.write(new_content)

                return f"Successfully updated '{rel_path}' (replaced 1 occurrence, {count - 1} remaining occurrences)."

            elif tool_name == "list_directory":
                rel_path = args.get("relative_path", "") or ""
                target_dir = cls._sanitize_path(project_root, rel_path) if rel_path else project_root
                if not target_dir.exists() or not target_dir.is_dir():
                    return f"Error: Directory '{rel_path}' does not exist."

                entries = []
                for entry in sorted(os.listdir(target_dir)):
                    if entry.startswith(".") and entry != ".gitignore":
                        continue
                    full = target_dir / entry
                    kind = "[DIR]" if full.is_dir() else "[FILE]"
                    entries.append(f"{kind} {entry}")

                return "\n".join(entries) if entries else "(Empty directory)"

            elif tool_name == "search_project":
                query = args.get("query", "")
                if not query:
                    return "Error: Query cannot be empty."

                # Run the search without a shell: the query is model-supplied,
                # and interpolating it into a command line would let it break
                # out into arbitrary shell syntax. `-e` also keeps a query
                # starting with "-" from being read as an option.
                async def run_search(command: List[str]) -> tuple[int, str]:
                    process = await asyncio.create_subprocess_exec(
                        *command,
                        cwd=str(project_root),
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.DEVNULL,
                    )
                    stdout, _ = await process.communicate()
                    return (
                        process.returncode or 0,
                        stdout.decode("utf-8", errors="replace").strip(),
                    )

                code, out = await run_search(
                    ["git", "grep", "-n", "-I", "-e", query],
                )
                if code != 0:
                    _, out = await run_search(
                        [
                            "grep",
                            "-rn",
                            "--exclude-dir=.git",
                            "--exclude-dir=node_modules",
                            "--exclude-dir=.venv",
                            "-e",
                            query,
                            ".",
                        ],
                    )
                return out if out else f"No matches found for '{query}'."

            elif tool_name == "register_preview":
                port = args.get("port")
                label = args.get("label")
                if not isinstance(port, int) or not (1 <= port <= 65535):
                    return "Error: 'port' must be an integer between 1 and 65535."
                if not isinstance(label, str) or not label.strip():
                    return "Error: 'label' is required and must be non-empty."
                base_path = args.get("base_path") or ""
                if not isinstance(base_path, str):
                    return "Error: 'base_path' must be a string."
                explicit_id = args.get("id")
                if explicit_id is not None and not isinstance(explicit_id, str):
                    return "Error: 'id' must be a string when provided."

                entry = await preview_registry.register(
                    project_path=str(project_root),
                    port=port,
                    label=label,
                    base_path=base_path,
                    source="llm",
                    entry_id=explicit_id,
                )
                return (
                    f"Registered preview '{entry.label}' on port {entry.port} "
                    f"with id {entry.id}. The user can now open it in the "
                    "in-app browser."
                )

            elif tool_name == "unregister_preview":
                remove_all = bool(args.get("all"))
                target_id = args.get("id")
                if remove_all:
                    removed = await preview_registry.clear_project(str(project_root))
                    return f"Removed {removed} preview registration(s) for the current project."

                if not isinstance(target_id, str) or not target_id:
                    return "Error: either 'id' or 'all: true' must be provided."

                removed = await preview_registry.unregister(target_id)
                if not removed:
                    return (
                        f"Error: no preview registered with id '{target_id}'. "
                        "It may have already been removed."
                    )
                return f"Removed preview '{target_id}'."

            elif tool_name == "task_completed":
                summary = args.get("summary") or "Task completed."
                return f"Task completed: {summary}"

            else:
                return f"Error: Unknown tool '{tool_name}'."
        except Exception as e:
            return f"Error executing tool '{tool_name}': {str(e)}"

    @classmethod
    async def fetch_models(cls, req: FetchModelsRequest) -> FetchModelsResponse:
        base_url = req.base_url.rstrip("/")
        url = f"{base_url}/models"

        headers = {
            "HTTP-Referer": "https://workfromphone.local",
            "X-Title": "WorkFromPhone",
        }
        if req.api_key:
            headers["Authorization"] = f"Bearer {req.api_key.strip()}"

        try:
            for attempt in range(cls.MAX_RETRIES + 1):
                async with httpx.AsyncClient(timeout=15.0) as client:
                    resp = await client.get(url, headers=headers)
                    if resp.status_code == 429 and attempt < cls.MAX_RETRIES:
                        retry_after = cls._parse_retry_after(resp.headers.get("retry-after"))
                        delay = cls._calculate_backoff(attempt, retry_after)
                        await asyncio.sleep(delay)
                        continue
                    if resp.status_code != 200:
                        # Fallback to curated popular models list if /models is restricted or failed
                        return cls._get_default_models(f"Provider returned HTTP {resp.status_code}")

                    data = resp.json()
                    raw_models = data.get("data", []) if isinstance(data, dict) else []

                    models: List[ModelInfo] = []
                    for m in raw_models:
                        m_id = m.get("id", "")
                        m_name = m.get("name", m_id)
                        description = m.get("description")
                        context_length = m.get("context_length")
                        pricing = m.get("pricing")
                        if m_id:
                            models.append(
                                ModelInfo(
                                    id=m_id,
                                    name=m_name,
                                    description=description,
                                    context_length=context_length,
                                    pricing=pricing,
                                )
                            )

                    if not models:
                        return cls._get_default_models("Empty model list returned")

                    return FetchModelsResponse(models=models, count=len(models))
        except Exception as e:
            return cls._get_default_models(str(e))

    @staticmethod
    def _get_default_models(note: str = "") -> FetchModelsResponse:
        curated = [
            ModelInfo(
                id="anthropic/claude-3.5-sonnet",
                name="Claude 3.5 Sonnet (Anthropic)",
                description="Industry leading model for coding, refactoring, and agentic tool use.",
                context_length=200000,
            ),
            ModelInfo(
                id="openai/gpt-4o",
                name="GPT-4o (OpenAI)",
                description="Flagship multimodal omni model with strong reasoning & tool calling.",
                context_length=128000,
            ),
            ModelInfo(
                id="openai/gpt-4o-mini",
                name="GPT-4o Mini (OpenAI)",
                description="Fast and cost-efficient intelligent model for general coding tasks.",
                context_length=128000,
            ),
            ModelInfo(
                id="deepseek/deepseek-chat",
                name="DeepSeek V3 (DeepSeek)",
                description="High-performance open-weight architecture model for coding and reasoning.",
                context_length=64000,
            ),
            ModelInfo(
                id="deepseek/deepseek-r1",
                name="DeepSeek R1 (DeepSeek)",
                description="Advanced reasoning and reflection model for complex programming problems.",
                context_length=64000,
            ),
            ModelInfo(
                id="meta-llama/llama-3.3-70b-instruct",
                name="Llama 3.3 70B Instruct (Meta)",
                description="High-capacity open model matching top tier benchmarks.",
                context_length=131072,
            ),
            ModelInfo(
                id="google/gemini-2.0-flash-001",
                name="Gemini 2.0 Flash (Google)",
                description="Ultra-fast, next-gen coding & multimodal agentic model.",
                context_length=1000000,
            ),
        ]
        return FetchModelsResponse(models=curated, count=len(curated))

    @classmethod
    async def run_agentic_task_stream(
        cls,
        req: ChatTaskRequest,
    ) -> AsyncGenerator[str, None]:
        """
        Executes the agentic loop against an OpenAI-compatible / OpenRouter endpoint.
        Streams JSON lines formatted as Server-Sent Events (SSE).
        """
        project_root = Path(os.path.expanduser(req.project_path)).resolve()
        if not project_root.exists() or not project_root.is_dir():
            yield f"data: {json.dumps({'type': 'error', 'message': f'Project root directory does not exist: {req.project_path}'})}\n\n"
            return

        base_url = req.llm_config.base_url.rstrip("/")
        completions_url = f"{base_url}/chat/completions"

        headers = {
            "Content-Type": "application/json",
            "HTTP-Referer": "https://workfromphone.local",
            "X-Title": "WorkFromPhone",
        }
        if req.llm_config.api_key:
            headers["Authorization"] = f"Bearer {req.llm_config.api_key.strip()}"

        system_instruction = (
            f"You are WorkFromPhone AI Assistant, an autonomous coding agent operating on the user's computer.\n"
            f"Active Project Directory: {str(project_root)}\n\n"
            "You have access to tools to inspect files, edit code, search the repository, run terminal commands, and control preview servers in the project directory.\n\n"
            "Operating Directives:\n"
            "1. AUTONOMOUS ACTION: Work proactively and continuously. Perform all necessary tool steps (search, read, edit, write, run tests, fix errors) until the user's task is completely fulfilled.\n"
            "2. DIRECT TOOL USAGE: Do not merely output code snippets in chat or describe manual steps. Use `edit_file`, `write_file`, and `run_terminal_command` directly.\n"
            "3. CONTINUOUS PROGRESSION: Never stop after just reading files or planning changes; immediately execute the next step.\n"
            "4. VERIFICATION: Verify your changes by executing terminal commands (e.g. `flutter analyze`, `flutter test`, `pytest`, `cargo test`, `npm test`, `git status`, `git diff`).\n"
            "5. COMPLETION: When all changes are implemented, tested, and verified, call the `task_completed` tool with a summary of the work done.\n"
        )

        conversation: List[Dict[str, Any]] = [
            {"role": "system", "content": system_instruction}
        ]

        for m in req.messages:
            msg_dict: Dict[str, Any] = {"role": m.role}
            if m.content is not None:
                msg_dict["content"] = m.content
            if m.tool_calls:
                msg_dict["tool_calls"] = m.tool_calls
            if m.tool_call_id:
                msg_dict["tool_call_id"] = m.tool_call_id
            if m.name:
                msg_dict["name"] = m.name
            conversation.append(msg_dict)

        step = 0
        consecutive_text_turns = 0
        max_steps = req.max_steps
        accumulated_usage = {
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "total_tokens": 0,
            "reasoning_tokens": 0,
            "cached_tokens": 0,
            "cost": 0.0,
        }
        has_usage_cost = False

        yield f"data: {json.dumps({'type': 'status', 'content': f'Connecting to {req.llm_config.model}...'})}\n\n"

        async with httpx.AsyncClient(timeout=180.0) as client:
            while max_steps is None or step < max_steps:
                step += 1
                payload = {
                    "model": req.llm_config.model,
                    "messages": conversation,
                    "tools": HARNESS_TOOLS,
                    "temperature": req.llm_config.temperature,
                    "stream": True,
                    "stream_options": {"include_usage": True},
                }
                if req.llm_config.max_tokens is not None:
                    payload["max_tokens"] = req.llm_config.max_tokens

                success = False
                full_content = ""
                tool_calls_acc: Dict[int, Dict[str, Any]] = {}
                step_usage: Dict[str, Any] | None = None

                for attempt in range(cls.MAX_RETRIES + 1):
                    full_content = ""
                    tool_calls_acc = {}
                    step_usage = None
                    stream_started = False
                    should_retry = False

                    try:
                        async with client.stream(
                            "POST", completions_url, headers=headers, json=payload
                        ) as response:
                            if response.status_code == 429:
                                err_body = await response.aread()
                                err_msg = err_body.decode("utf-8", errors="replace")
                                if attempt < cls.MAX_RETRIES:
                                    retry_after = cls._parse_retry_after(response.headers.get("retry-after"))
                                    delay = cls._calculate_backoff(attempt, retry_after)
                                    yield f"data: {json.dumps({'type': 'status', 'content': f'Rate limited (429). Retrying in {delay:.1f}s (attempt {attempt + 1}/{cls.MAX_RETRIES})...'})}\n\n"
                                    await asyncio.sleep(delay)
                                    continue
                                else:
                                    yield f"data: {json.dumps({'type': 'error', 'message': f'API error (429): Rate limit exceeded after {cls.MAX_RETRIES} retries: {err_msg}'})}\n\n"
                                    return

                            if response.status_code != 200:
                                err_body = await response.aread()
                                err_msg = err_body.decode("utf-8", errors="replace")
                                yield f"data: {json.dumps({'type': 'error', 'message': f'API error ({response.status_code}): {err_msg}'})}\n\n"
                                return

                            async for line in response.aiter_lines():
                                if not line or not line.startswith("data:"):
                                    continue
                                line_data = line[5:].strip()
                                if line_data == "[DONE]":
                                    break

                                try:
                                    chunk_json = json.loads(line_data)
                                    if "error" in chunk_json:
                                        err_obj = chunk_json["error"]
                                        err_msg = (
                                            err_obj.get("message", str(err_obj))
                                            if isinstance(err_obj, dict)
                                            else str(err_obj)
                                        )
                                        if (
                                            not stream_started
                                            and attempt < cls.MAX_RETRIES
                                            and ("rate" in err_msg.lower() or "429" in str(err_obj))
                                        ):
                                            delay = cls._calculate_backoff(attempt)
                                            yield f"data: {json.dumps({'type': 'status', 'content': f'Rate limited. Retrying in {delay:.1f}s (attempt {attempt + 1}/{cls.MAX_RETRIES})...'})}\n\n"
                                            await asyncio.sleep(delay)
                                            should_retry = True
                                            break
                                        yield f"data: {json.dumps({'type': 'error', 'message': f'API stream error: {err_msg}'})}\n\n"
                                        return

                                    if isinstance(chunk_json.get("usage"), dict):
                                        step_usage = chunk_json["usage"]
                                    choices = chunk_json.get("choices", [])
                                    if not choices:
                                        continue
                                    delta = choices[0].get("delta", {})

                                    # Content chunk
                                    content_piece = delta.get("content")
                                    if content_piece:
                                        full_content += content_piece
                                        stream_started = True
                                        yield f"data: {json.dumps({'type': 'chunk', 'content': content_piece})}\n\n"

                                    # Tool calls delta
                                    delta_tool_calls = delta.get("tool_calls", [])
                                    for tc in delta_tool_calls:
                                        idx = tc.get("index", 0)
                                        if idx not in tool_calls_acc:
                                            tool_calls_acc[idx] = {
                                                "id": tc.get("id", f"call_{idx}"),
                                                "type": "function",
                                                "function": {
                                                    "name": tc.get("function", {}).get("name", ""),
                                                    "arguments": "",
                                                },
                                            }
                                        fn = tc.get("function", {})
                                        if fn.get("name"):
                                            tool_calls_acc[idx]["function"]["name"] = fn["name"]
                                        if fn.get("arguments"):
                                            tool_calls_acc[idx]["function"]["arguments"] += fn["arguments"]

                                except json.JSONDecodeError:
                                    pass

                        if should_retry:
                            continue

                        success = True
                        break

                    except httpx.RequestError as exc:
                        if not stream_started and attempt < cls.MAX_RETRIES:
                            delay = cls._calculate_backoff(attempt)
                            yield f"data: {json.dumps({'type': 'status', 'content': f'Network error ({exc}). Retrying in {delay:.1f}s (attempt {attempt + 1}/{cls.MAX_RETRIES})...'})}\n\n"
                            await asyncio.sleep(delay)
                            continue
                        else:
                            yield f"data: {json.dumps({'type': 'error', 'message': f'Harness execution error: {str(exc)}'})}\n\n"
                            return
                    except Exception as e:
                        yield f"data: {json.dumps({'type': 'error', 'message': f'Harness execution error: {str(e)}'})}\n\n"
                        return

                if not success:
                    return

                # If no structured tool calls were emitted in delta, check for text-embedded tool calls
                if not tool_calls_acc and full_content:
                    text_calls = cls._extract_text_tool_calls(full_content)
                    for idx, tc in enumerate(text_calls):
                        tool_calls_acc[idx] = tc

                if step_usage is not None:
                    prompt_tokens = int(step_usage.get("prompt_tokens") or 0)
                    completion_tokens = int(step_usage.get("completion_tokens") or 0)
                    total_tokens = int(
                        step_usage.get("total_tokens")
                        or prompt_tokens + completion_tokens
                    )
                    prompt_details = step_usage.get("prompt_tokens_details") or {}
                    completion_details = (
                        step_usage.get("completion_tokens_details") or {}
                    )
                    accumulated_usage["prompt_tokens"] += prompt_tokens
                    accumulated_usage["completion_tokens"] += completion_tokens
                    accumulated_usage["total_tokens"] += total_tokens
                    accumulated_usage["cached_tokens"] += int(
                        prompt_details.get("cached_tokens") or 0
                    )
                    accumulated_usage["reasoning_tokens"] += int(
                        completion_details.get("reasoning_tokens") or 0
                    )
                    if step_usage.get("cost") is not None:
                        accumulated_usage["cost"] += float(step_usage["cost"])
                        has_usage_cost = True

                    usage_event = {
                        "type": "usage",
                        "usage": {
                            **accumulated_usage,
                            "cost": (
                                accumulated_usage["cost"]
                                if has_usage_cost
                                else None
                            ),
                            "context_tokens": prompt_tokens + completion_tokens,
                            "exact": True,
                        },
                    }
                    yield f"data: {json.dumps(usage_event)}\n\n"

                # Check if model requested tool calls
                if tool_calls_acc:
                    consecutive_text_turns = 0
                    constructed_tool_calls = [tool_calls_acc[k] for k in sorted(tool_calls_acc.keys())]
                    conversation.append(
                        {
                            "role": "assistant",
                            "content": full_content or None,
                            "tool_calls": constructed_tool_calls,
                        }
                    )

                    has_task_completed = False

                    # Execute each tool call
                    for tc in constructed_tool_calls:
                        fn_name = tc["function"]["name"]
                        fn_args_raw = tc["function"]["arguments"]
                        call_id = tc.get("id", "call_0")

                        try:
                            fn_args = json.loads(fn_args_raw) if fn_args_raw else {}
                        except json.JSONDecodeError:
                            fn_args = {"raw": fn_args_raw}

                        if fn_name == "task_completed":
                            has_task_completed = True

                        yield f"data: {json.dumps({'type': 'tool_call_start', 'tool': fn_name, 'args': fn_args})}\n\n"

                        output = await cls.execute_tool(project_root, fn_name, fn_args)

                        yield f"data: {json.dumps({'type': 'tool_call_result', 'tool': fn_name, 'output': output})}\n\n"

                        # Append tool response to conversation
                        conversation.append(
                            {
                                "role": "tool",
                                "tool_call_id": call_id,
                                "name": fn_name,
                                "content": output,
                            }
                        )

                    if has_task_completed:
                        yield f"data: {json.dumps({'type': 'done', 'total_steps': step})}\n\n"
                        return

                    # Continue loop to get model's next turn
                    yield f"data: {json.dumps({'type': 'status', 'content': 'Processing tool results...'})}\n\n"
                    continue

                else:
                    # No tool calls: model provided final response
                    yield f"data: {json.dumps({'type': 'done', 'total_steps': step})}\n\n"
                    return

            yield f"data: {json.dumps({'type': 'done', 'total_steps': step, 'message': 'Reached max steps limit.'})}\n\n"


harness_service = HarnessService()
