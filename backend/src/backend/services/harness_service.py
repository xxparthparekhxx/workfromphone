import asyncio
import json
import os
import re
from pathlib import Path
from typing import Any, AsyncGenerator, Dict, List, Optional

import httpx

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
]


class HarnessService:
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
                    process.kill()
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

                # Use ripgrep or python fallback
                cmd = f"git grep -n -I {json.dumps(query)} 2>/dev/null || grep -rn --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='.venv' {json.dumps(query)} ."
                process = await asyncio.create_subprocess_shell(
                    cmd,
                    cwd=str(project_root),
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                stdout, _ = await process.communicate()
                out = stdout.decode("utf-8", errors="replace").strip()
                return out if out else f"No matches found for '{query}'."

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
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.get(url, headers=headers)
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
            f"Active Project Directory: {str(project_root)}\n"
            "You have access to tools to inspect files, edit code, search the repository, and run terminal commands in the project directory.\n"
            "Guidelines:\n"
            "- Always investigate the project structure before modifying files.\n"
            "- Run terminal commands (e.g. git status, tests, build) when needed to verify your changes.\n"
            "- Provide clear explanations of your actions and reasoning to the user.\n"
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
        max_steps = req.max_steps

        yield f"data: {json.dumps({'type': 'status', 'content': f'Connecting to {req.llm_config.model}...'})}\n\n"

        async with httpx.AsyncClient(timeout=180.0) as client:
            while step < max_steps:
                step += 1
                payload = {
                    "model": req.llm_config.model,
                    "messages": conversation,
                    "tools": HARNESS_TOOLS,
                    "temperature": req.llm_config.temperature,
                    "stream": True,
                }

                try:
                    async with client.stream(
                        "POST", completions_url, headers=headers, json=payload
                    ) as response:
                        if response.status_code != 200:
                            err_body = await response.aread()
                            err_msg = err_body.decode("utf-8", errors="replace")
                            yield f"data: {json.dumps({'type': 'error', 'message': f'API error ({response.status_code}): {err_msg}'})}\n\n"
                            return

                        full_content = ""
                        tool_calls_acc: Dict[int, Dict[str, Any]] = {}

                        async for line in response.aiter_lines():
                            if not line or not line.startswith("data:"):
                                continue
                            line_data = line[5:].strip()
                            if line_data == "[DONE]":
                                break

                            try:
                                chunk_json = json.loads(line_data)
                                choices = chunk_json.get("choices", [])
                                if not choices:
                                    continue
                                delta = choices[0].get("delta", {})

                                # Content chunk
                                content_piece = delta.get("content")
                                if content_piece:
                                    full_content += content_piece
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

                    # Check if model requested tool calls
                    if tool_calls_acc:
                        # Append assistant message with tool calls
                        constructed_tool_calls = [tool_calls_acc[k] for k in sorted(tool_calls_acc.keys())]
                        conversation.append(
                            {
                                "role": "assistant",
                                "content": full_content or None,
                                "tool_calls": constructed_tool_calls,
                            }
                        )

                        # Execute each tool call
                        for tc in constructed_tool_calls:
                            fn_name = tc["function"]["name"]
                            fn_args_raw = tc["function"]["arguments"]
                            call_id = tc.get("id", "call_0")

                            try:
                                fn_args = json.loads(fn_args_raw) if fn_args_raw else {}
                            except json.JSONDecodeError:
                                fn_args = {"raw": fn_args_raw}

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

                        # Continue loop to get model's next turn
                        yield f"data: {json.dumps({'type': 'status', 'content': 'Processing tool results...'})}\n\n"
                        continue

                    else:
                        # No tool calls: model provided final response
                        yield f"data: {json.dumps({'type': 'done', 'total_steps': step})}\n\n"
                        return

                except Exception as e:
                    yield f"data: {json.dumps({'type': 'error', 'message': f'Harness execution error: {str(e)}'})}\n\n"
                    return

            yield f"data: {json.dumps({'type': 'done', 'total_steps': step, 'message': 'Reached max steps limit.'})}\n\n"


harness_service = HarnessService()
