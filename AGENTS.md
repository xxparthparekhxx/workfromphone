# WorkFromPhone Agent & Developer Guide

This document serves as the operational and architectural guide for AI coding agents and human developers working in the **WorkFromPhone** repository.

---

## 1. Project Overview & Architecture

**WorkFromPhone** is a cross-platform Flutter application (mobile & desktop) paired with a high-performance, Linux-only FastAPI backend service. It enables developers to monitor remote Linux machines, manage files and Git repositories, execute commands in persistent PTY terminals, run AI agent coding tasks, preview running web development servers, and provision remote backend instances over SSH.

```
┌────────────────────────────────────────────────────────┐
│                   Flutter Client (lib/)                │
│  - Projects & File Manager     - Persistent Terminals  │
│  - Git Staging & Diff Viewer   - System Monitor        │
│  - Agentic Chat Harness        - In-App Web Preview    │
│  - Remote SSH Provisioning     - Tokyo Night Theme     │
└───────────────▲────────────────────────▲───────────────┘
                │ HTTP REST / SSE        │ WebSockets
                │ (Bearer Auth)          │ (PTY / Metrics / LLM)
┌───────────────▼────────────────────────▼───────────────┐
│               FastAPI Backend (backend/src/)           │
│  - Linux PTY Manager           - Safe Path Sandboxing  │
│  - Real-time System Metrics    - Git CLI Wrappers      │
│  - LLM Agent Task Loop         - Dev Server Proxy      │
│  - Artifact Sharing (PIN/CSP)  - SearXNG Search        │
└────────────────────────────────────────────────────────┘
```

### Repository Layout

- `lib/`: Flutter client application code (Dart).
  - `lib/models/`: Strongly-typed data models and JSON serialization.
  - `lib/services/`: Network, storage, SSH provisioning, and WebSocket transport sessions.
  - `lib/screens/`: Feature screens (Chat, Files, Git, Terminal, System, Preview, Settings).
  - `lib/widgets/`: Reusable UI components (Code editor, Git diffs, Markdown renderer, sheets).
  - `lib/utils/`: ANSI parser, icon mappers, theme definitions (Tokyo Night).
- `test/`: Flutter unit and widget tests.
- `backend/src/backend/`: FastAPI backend implementation (Python >=3.13).
  - `api/v1/`: API route controllers (`endpoints/`) and top-level router (`router.py`).
  - `core/`: Application configuration (`config.py`), auth middleware (`auth.py`), and security primitives (`security.py`).
  - `schemas/`: Pydantic v2 validation and serialization schemas.
  - `services/`: Core business logic (PTY, System, Filesystem, Git, LLM Harness, Preview, Artifacts, Search).
  - `frozen_main.py` & `main.py`: Application entrypoints for development and PyInstaller release binaries.
- `backend/tests/`: Backend test suite using `pytest` and `httpx`.
- `backend/workfromphone-backend.spec`: PyInstaller specification for standalone Linux executables.
- `.github/workflows/backend-release.yml`: Release matrix build workflow for `x86_64` and `aarch64` binaries with automatic SHA-256 manifest generation.

---

## 2. Core Subsystems & Technical Details

### 2.1. LLM Agentic Harness (`HarnessService`)
- **Location**: `backend/src/backend/services/harness_service.py`, `backend/src/backend/api/v1/endpoints/llm.py`, `lib/services/chat_service.py`
- **Capabilities**:
  - Executes autonomous agent loops with OpenAI-compatible providers (e.g., OpenRouter, OpenAI, Local LLMs).
  - Supports streaming via Server-Sent Events (SSE) at `/api/v1/llm/chat` and WebSockets at `/api/v1/llm/ws`.
  - Built-in tool calling inventory:
    1. `run_terminal_command`: Executes bash commands inside the project root directory.
    2. `read_file`: Reads file content with optional line slicing.
    3. `write_file`: Creates or overwrites files.
    4. `edit_file`: Performs exact substring replacement.
    5. `list_directory`: Lists directory contents safely.
    6. `search_project`: Keyword / regex searches across the project tree.
    7. `register_preview`: Registers loopback web dev server ports for in-app browser preview.
    8. `unregister_preview`: Deregisters dev server preview targets.
    9. `task_completed`: Finalizes the agent run with a summary of accomplishments.
  - **Tool-call Fallback Parsers**: Employs multi-pattern regex extraction (XML `<function=...>`, `<tool_call>` JSON blocks, and Markdown code blocks) to parse tool calls from open-weight models (DeepSeek R1, Qwen 2.5 Coder, Llama) that output tool calls in plaintext rather than standard OpenAI tool-call deltas.
  - **Resilience**: Jittered exponential backoff for rate limits (HTTP 429) and transient network disconnects.

### 2.2. Linux PTY & Interactive Terminal (`TerminalService`)
- **Location**: `backend/src/backend/services/terminal_service.py`, `lib/services/terminal_session.dart`, `lib/screens/terminal/`
- **Capabilities**:
  - Manages real Linux pseudo-terminals using `pty.openpty()`, `fcntl` (non-blocking I/O), and `termios`.
  - Bidirectional WebSocket protocol supporting stdin, stdout/stderr framing, window resizing (`cols`, `rows`), and keep-alive pings.
  - Process group tracking with clean teardown (`os.killpg(os.getpgid(pid), signal.SIGKILL)`).
  - Environment sanitization: Purges sensitive environment variables (`*TOKEN*`, `*KEY*`, `*SECRET*`, `*PASSWORD*`) when spawning terminal subshells while retaining `TERM`, `COLORTERM`, and `SSH_AUTH_SOCK`.

### 2.3. System Monitoring (`SystemService`)
- **Location**: `backend/src/backend/services/system_service.py`, `lib/services/system_monitor_session.dart`, `lib/screens/system/`
- **Capabilities**:
  - Live metric streams over WebSocket (`/api/v1/system/ws`) and REST snapshots (`/api/v1/system/snapshot`).
  - Collects CPU total/per-core utilization, memory/swap usage, disk partitions/IO, network throughput, top process consumption, system temperatures, and NVIDIA/AMD GPU metrics.
  - **Privacy Guard**: Never exposes command-line arguments, environment variables, or private host details over monitoring endpoints.

### 2.4. Sandboxed Filesystem Operations (`FsService`)
- **Location**: `backend/src/backend/services/fs_service.py`, `backend/src/backend/api/v1/endpoints/fs.py`, `lib/screens/files/`
- **Capabilities**:
  - Directory browsing, folder creation, safe deletion, file read/write.
  - **Path Traversal Defense**: All target file and directory paths are canonicalized (`Path.resolve()`) and strictly verified to reside within the designated project root.
  - **Binary-Safe Chunked Uploads**: Multipart uploads stream into a temporary spool file, validate file size against `MAX_UPLOAD_BYTES`, and atomically replace the destination file.

### 2.5. Git Management Subsystem (`GitService`)
- **Location**: `backend/src/backend/services/git_service.py`, `lib/screens/git/`
- **Capabilities**:
  - Status inspect, staged and unstaged diffs, branch listing.
  - Staging (`git add`), unstaging (`git restore --staged`), discarding changes (`git restore`), committing, pushing, and pulling.
  - All operations execute inside the validated repository path.

### 2.6. In-App Web Preview & Reverse Proxy (`PreviewService`)
- **Location**: `backend/src/backend/services/preview_service.py`, `lib/screens/preview/`
- **Capabilities**:
  - Proxies running local web dev servers (Vite, Next.js, Flutter Web, Python HTTP servers) through the backend to Flutter's in-app webview.
  - SPA routing rewrites and path resolution.
  - **Security Controls**: Port whitelist enforcement (restricts to 1024-65535, blocks system ports and backend port), SSRF protection via `assert_safe_outbound_url`, and sensitive header stripping (`Authorization`, `Cookie`, `X-Access-Token`).

### 2.7. Protected Artifact Sharing (`ArtifactService`)
- **Location**: `backend/src/backend/services/artifact_service.py`, `backend/src/backend/main.py`
- **Capabilities**:
  - Publish build outputs, HTML reports, or media with unique share tokens.
  - Optional numeric PIN protection with PBKDF2-HMAC-SHA256 hashing and rate-limited unlock attempts (`AttemptLimiter`).
  - Strict Content-Security-Policy (CSP) headers sandbox shared HTML rendering.

### 2.8. Remote SSH Provisioning Wizard (`RemoteSetupService`)
- **Location**: `lib/services/remote_setup_service.dart`, `lib/screens/settings/remote_backend_setup_screen.dart`
- **Capabilities**:
  - Connects via SSH (`dartssh2`), verifies and pins remote host fingerprints.
  - Detects remote CPU architecture (`uname -m` -> `x86_64` vs `aarch64`).
  - Downloads release tarball from GitHub Releases matching version manifest (`backend-manifest.json`).
  - Validates SHA-256 checksum, extracts binary to `~/.local/share/workfromphone/backend/`.
  - Generates secure random `ACCESS_TOKEN`, configures systemd user service (`~/.config/systemd/user/workfromphone-backend.service`), and starts the service.
  - Sets up encrypted port forwarding / SSH tunnel or Cloudflare Tunnel connection.

---

## 3. Security Model & Invariants

All agents and contributors must strictly enforce the following security invariants:

1. **Authentication & Capability Route Protection**:
   - When `ACCESS_TOKEN` is configured, all capability routes and WebSockets must require a valid `Bearer <token>` authorization header or close immediately with HTTP 401 / WebSocket 4401.
   - Token comparisons must use constant-time comparison (`hmac.compare_digest`).
   - `/api/v1/health` and `/robots.txt` remain public.
2. **Network Exposure Protection**:
   - The backend binds to loopback (`127.0.0.1`) by default.
   - Attempting to bind a non-loopback host (e.g., `0.0.0.0`) without `ACCESS_TOKEN` set will cause `verify_network_exposure()` to abort startup.
3. **CORS & Origin Hardening**:
   - Wildcard CORS origins (`*`) are strictly prohibited and automatically stripped on startup.
   - WebSocket connections reject unauthorized `Origin` headers (HTTP 4403).
4. **Secret Storage on Client**:
   - SSH credentials, backend bearer tokens, and LLM API keys must **always** be stored in `FlutterSecureStorage`.
   - Plain `SharedPreferences` (`StorageService`) is restricted to non-sensitive profile metadata, active project paths, and UI settings.
   - Bearer tokens are strictly scoped to their backend origin URL; never forward a stored token to a modified backend host.
5. **SSRF & Outbound Request Validation**:
   - Outbound requests (e.g., SearXNG search or proxy targets) must validate target URLs using `assert_safe_outbound_url` to reject cloud metadata endpoints (`169.254.169.254`, `metadata.google.internal`) and link-local ranges.
6. **Subprocess Isolation**:
   - Terminal sessions and command executions must use `sanitized_child_env` to avoid leaking backend tokens or system secrets to child processes.

---

## 4. Coding Conventions & Best Practices

### Flutter / Dart Conventions
- **Linter & Formatting**: Keep `flutter analyze` completely clean (zero warnings/errors) and run `dart format` on all modified `.dart` files.
- **Icons**: Prefer Cupertino icons (`CupertinoIcons.*`) for interface actions to preserve visual consistency with the existing design system.
- **Architecture Layers**:
  - `lib/models/`: Plain Dart classes with JSON serialization (`fromJson` / `toJson`).
  - `lib/services/`: Transport, HTTP clients, WebSocket streams, and secure storage logic.
  - `lib/screens/`: Top-level screens and tab views.
  - `lib/widgets/`: Modular, reusable widgets.
- **Memory & Lifecycle**:
  - WebSocket channels and stream subscriptions must be explicitly closed and canceled in `dispose()`.
  - Reconnection timers must never outlive widget lifecycle.
- **Testing**: Add stable `ValueKey` or `Key` attributes to interactive controls to ensure reliable widget testing.

### Python / FastAPI Backend Conventions
- **Thin Handlers, Fat Services**: Keep route handlers in `endpoints/` minimal. Business logic, process management, and file operations belong in `services/`.
- **Validation**: All request payloads and response bodies must use strict Pydantic v2 schemas (`backend/src/backend/schemas/`).
- **Path Handling**: Always use `pathlib.Path` for path manipulations and check boundaries with `is_relative_to` or canonical path resolution.
- **Async I/O**: Use `asyncio` for non-blocking operations and avoid synchronous blocking calls inside async routes.
- **Error Types**: Return structured JSON errors with standard HTTP status codes (`HTTPException`). SSE and WebSocket streams must emit structured error event messages before terminating.

---

## 5. Development, Verification & Tooling

### Package Management
Always use package managers when modifying dependencies:
- **Flutter**: `flutter pub add <package>` or `flutter pub remove <package>`
- **Backend (Python)**: `cd backend && uv add <package>` or `uv remove <package>`

### Verification Commands
Run the following verification suite proportional to your changes:

```bash
# 1. Analyze Flutter codebase
flutter analyze

# 2. Run Flutter test suite
flutter test

# 3. Run Backend test suite
cd backend && uv run pytest -q

# 4. Format Dart code
dart format lib/ test/
```

### Standalone Backend Build & Smoke Test
When making changes to backend entrypoints, release workflows, or PyInstaller specs:

```bash
cd backend
uv run pyinstaller --clean --noconfirm workfromphone-backend.spec

# Smoke-test binary
ACCESS_TOKEN=test-token PORT=18765 dist/workfromphone-backend &
PID=$!
sleep 2
curl -fsS http://127.0.0.1:18765/api/v1/health
curl -fsS -H "Authorization: Bearer test-token" http://127.0.0.1:18765/api/v1/system/snapshot
kill $PID
```

---

## 6. API Route & WebSocket Reference

| Method / Protocol | Path | Auth Required | Description |
| :--- | :--- | :---: | :--- |
| `GET` | `/` | No | Root endpoint & metadata |
| `GET` | `/robots.txt` | No | Search crawler rejection headers |
| `GET` | `/share/{token}` | Optional PIN | View shared protected artifact |
| `POST` | `/share/{token}` | Optional PIN | Unlock protected artifact with PIN |
| `GET` | `/api/v1/health` | No | Service health check |
| `GET` | `/api/v1/fs/browse` | Yes | List project directories & files |
| `POST` | `/api/v1/fs/validate` | Yes | Validate directory path existence |
| `GET` | `/api/v1/fs/quick-paths` | Yes | Get common dev directories |
| `GET` | `/api/v1/fs/file` | Yes | Read file text content |
| `POST` | `/api/v1/fs/file` | Yes | Save / write file text |
| `POST` | `/api/v1/fs/upload` | Yes | Stream multipart binary file upload |
| `GET` | `/api/v1/fs/download` | Yes | Download project file |
| `POST` | `/api/v1/fs/create` | Yes | Create file or directory |
| `DELETE`| `/api/v1/fs/file` | Yes | Delete file or directory |
| `GET` | `/api/v1/git/status` | Yes | Get Git working directory status |
| `GET` | `/api/v1/git/diff` | Yes | Get Git diff (cached or working tree) |
| `POST` | `/api/v1/git/stage` | Yes | Stage modified files (`git add`) |
| `POST` | `/api/v1/git/unstage` | Yes | Unstage files (`git restore --staged`) |
| `POST` | `/api/v1/git/discard` | Yes | Discard uncommitted changes |
| `POST` | `/api/v1/git/commit` | Yes | Commit staged changes |
| `POST` | `/api/v1/git/push` | Yes | Push commits to upstream |
| `POST` | `/api/v1/git/pull` | Yes | Pull changes from upstream |
| `GET` | `/api/v1/git/branches`| Yes | List local branches |
| `POST` | `/api/v1/terminal/run`| Yes | Execute non-interactive shell command |
| `WS` | `/api/v1/terminal/ws` | Yes | Interactive PTY shell session |
| `GET` | `/api/v1/system/snapshot`| Yes | Snapshot of host CPU, RAM, Disk, GPU |
| `WS` | `/api/v1/system/ws` | Yes | Real-time system monitoring stream |
| `POST` | `/api/v1/llm/models` | Yes | Query available OpenRouter/OpenAI models |
| `POST` | `/api/v1/llm/chat` | Yes | Start agentic task loop (SSE stream) |
| `POST` | `/api/v1/llm/general`| Yes | General conversational chat (SSE stream) |
| `WS` | `/api/v1/llm/ws` | Yes | Interactive agent loop WebSocket stream |
| `GET` | `/api/v1/preview` | Yes | List registered web dev preview servers |
| `POST` | `/api/v1/preview/register` | Yes | Register active loopback dev server port |
| `POST` | `/api/v1/preview/unregister` | Yes | Remove preview registration |
| `WS` | `/api/v1/preview/ws` | Yes | Live preview targets change notifications |
| `ANY` | `/api/v1/preview/proxy/{id}/{path:path}` | Yes | Reverse-proxy live web preview target |
| `POST` | `/api/v1/artifacts/publish` | Yes | Publish an artifact for sharing |
| `GET` | `/api/v1/artifacts` | Yes | List published artifacts |
| `DELETE`| `/api/v1/artifacts/{token}` | Yes | Delete a published artifact |
| `POST` | `/api/v1/search` | Yes | Web search via SearXNG instance |

---

## 7. Working Rules for AI Agents

1. **Preserve User Changes**: Always preserve unrelated uncommitted changes in the workspace. Never overwrite or revert files without explicit instructions.
2. **No Unprompted App Execution**: Do not run `flutter run`, launch mobile emulators, or execute hot reload unless explicitly directed by the user.
3. **No Unrequested Git Commits**: Do not run `git commit` or `git push` unless specifically requested.
4. **Clean Verification**: Always verify that `flutter analyze`, `flutter test`, and `pytest` pass before concluding a coding task. If an unrelated test fails, report it clearly rather than modifying unrelated code silently.
5. **Security First**: Never hardcode credentials, bypass path canonicalization, or relax authentication / CORS guards.
