# WorkFromPhone

WorkFromPhone is a cross-platform mobile developer environment (Flutter client) paired with a high-performance, Linux-only FastAPI backend service. It allows developers to monitor remote Linux servers, manage Git repositories and files, run interactive persistent PTY terminal sessions, execute autonomous AI coding tasks, and preview running web development servers directly from a mobile device.

Website and downloads: https://xxparthparekhxx.github.io/workfromphone/

---

## Architecture Overview

```
+--------------------------------------------------------+
|                   Flutter Client (lib/)                |
|  - Projects & File Manager     - Persistent Terminals  |
|  - Git Staging & Diff Viewer   - System Monitor        |
|  - Agentic Chat Harness        - In-App Web Preview    |
|  - Remote SSH Provisioning     - Tokyo Night Theme     |
+------------------------+-------------------------------+
                         | HTTP REST / SSE / WebSockets
                         | Bearer Auth
+------------------------v-------------------------------+
|               FastAPI Backend (backend/src/)           |
|  - Linux PTY Manager           - Safe Path Sandboxing  |
|  - Real-time System Metrics    - Git CLI Wrappers      |
|  - LLM Agent Task Loop         - Dev Server Proxy      |
|  - Artifact Sharing (PIN/CSP)  - SearXNG Search        |
+--------------------------------------------------------+
```

---

## Features

- **Real-Time Linux System Monitor**: Live sub-second streaming of per-core CPU utilization, memory/swap, disk IO partitions, GPU usage, thermals, and top consuming processes over WebSockets.
- **Persistent PTY Terminals**: Interactive pseudo-terminals with non-blocking I/O, xterm ANSI color rendering, window resizing, and sanitized subshell environment isolation.
- **Autonomous AI Coding Harness**: Autonomous LLM agent loop equipped with tool calling (terminal command execution, file reading/slicing, substring replacement editing, file tree search, and preview registration).
- **Sandboxed File Explorer & Editor**: Full directory navigation, syntax-highlighted code editing, path traversal defense, and binary-safe chunked uploads.
- **Full Git Workspace Management**: Inspect status, view staged and unstaged unified diffs, stage/unstage files, commit changes, switch branches, and push/pull to remotes.
- **In-App Web Preview & Reverse Proxy**: Reverse proxy live web development servers (Next.js, Vite, Flask, Flutter Web) into the mobile webview with SPA routing rewrites and SSRF protections.
- **No-PC Mode (Android)**: Run the backend inside an on-device Debian container (proot, no root needed) and connect over loopback — no PC or Termux required.
- **Secure Transport Options**: Connect over encrypted loopback SSH tunnels or Cloudflare named tunnels without exposing backend ports to the public internet.

---

## Quick Server Installation

Run the automated installer on any Linux machine (x86_64 or aarch64 / ARM64):

```bash
curl -fsSL https://raw.githubusercontent.com/xxparthparekhxx/workfromphone/master/scripts/install.sh | bash
```

The script automatically:
1. Detects your Linux architecture (`x86_64` or `aarch64`).
2. Fetches the latest release from GitHub and verifies its SHA-256 checksum.
3. Extracts the standalone binary to `~/.local/share/workfromphone/current/`.
4. Generates a secure random `ACCESS_TOKEN` and saves it to `~/.config/workfromphone/backend.env`.
5. Configures and starts a user-level systemd service (`workfromphone-backend.service`).

---

## Manual Backend Installation

### 1. Standalone Binary (Precompiled)

Download the release archive matching your architecture:

- **Linux x86_64**: [Download](https://github.com/xxparthparekhxx/workfromphone/releases/latest/download/workfromphone-backend-linux-x86_64.tar.gz)
- **Linux aarch64 / ARM64**: [Download](https://github.com/xxparthparekhxx/workfromphone/releases/latest/download/workfromphone-backend-linux-aarch64.tar.gz)
- **Release Manifest**: [backend-manifest.json](https://github.com/xxparthparekhxx/workfromphone/releases/latest/download/backend-manifest.json)

Extract and run:

```bash
mkdir -p ~/.local/share/workfromphone/current
tar -xzf workfromphone-backend-linux-x86_64.tar.gz -C ~/.local/share/workfromphone/current
chmod 700 ~/.local/share/workfromphone/current/workfromphone-backend

ACCESS_TOKEN="your-secure-random-token" PORT=8000 ~/.local/share/workfromphone/current/workfromphone-backend
```

### 2. Systemd User Service Setup

Create the environment file:

```bash
mkdir -p ~/.config/workfromphone
cat <<'EOF' > ~/.config/workfromphone/backend.env
HOST=127.0.0.1
PORT=8000
ACCESS_TOKEN=your-secure-random-token
DEBUG=false
EOF
chmod 600 ~/.config/workfromphone/backend.env
```

Create the systemd service file:

```bash
mkdir -p ~/.config/systemd/user
cat <<'EOF' > ~/.config/systemd/user/workfromphone-backend.service
[Unit]
Description=WorkFromPhone Backend
After=network-online.target

[Service]
Type=simple
EnvironmentFile=%h/.config/workfromphone/backend.env
ExecStart=%h/.local/share/workfromphone/current/workfromphone-backend
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF
```

Enable and start the service:

```bash
systemctl --user daemon-reload
systemctl --user enable --now workfromphone-backend.service
```

### 3. Development Server (from Source)

Prerequisites: Python >= 3.13 and [`uv`](https://github.com/astral-sh/uv).

```bash
cd backend
uv run uvicorn backend.main:app --reload --host 127.0.0.1 --port 8000
```

---

## No-PC Mode: On-Device Debian Container

No computer at all? The Android app can host the backend itself. **No-PC
mode** embeds a Debian Linux container (patched `proot` + minimal Debian
rootfs, no root access needed) inside the app: the FastAPI backend runs on
the phone and the Flutter UI talks to `http://127.0.0.1:8000`, exactly as if
it were a remote server. No Termux dependency — everything ships with (or is
fetched by) the app.

How it works:

1. Open **Settings → Run backend on this phone**.
2. **Begin Setup**: downloads the signed Debian rootfs for your device
   (`aarch64` phones, `x86_64` emulator; ~150–300MB, one-time) into
   app-private storage and verifies its SHA-256 against
   `rootfs-manifest.json` from GitHub Releases. The APK stays slim because
   the rootfs is fetched on first run, never bundled.
3. **Start**: launches the container as a foreground service (ongoing
   notification with a Stop action, wakelock, and a battery-exemption prompt
   so OEM task killers don't freeze it). Your workspace is bind-mounted at
   `/workspace` inside the guest.
4. **Test Connection**: probes public `/api/v1/health`, then the
   token-authenticated `/api/v1/system/snapshot`.
5. **Save & Use On-device Backend**: stores a `directHttp`
   `http://127.0.0.1:8000` profile and generates the mandatory
   `ACCESS_TOKEN` (required even on loopback — any on-device app can reach
   localhost) in `FlutterSecureStorage`, scoped to the local URL only.

Notes for builders: the rootfs image is Debian minimal + backend +
`git/curl/ca-certificates/build-essential` only (see `rootfs/`); patched
`proot` binaries live in `android/app/src/main/jniLibs/<abi>/` (fetch with
`scripts/fetch-proot.sh`) because Android W^X only allows executing code
from `nativeLibraryDir`. Releases publish
`workfromphone-rootfs-debian-<arch>.tar.gz` + SHA-256 on every `backend-v*`
tag, mirroring the `backend-manifest.json` flow. Expect ~5% CPU overhead
from proot's ptrace layer.

Play-policy watch items before release: the foreground service uses the
`specialUse` type with a declared subtype and a persistent Stop-action
notification; `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` invites extra Play
review scrutiny, so keep the in-app rationale visible — the setup wizard
explains why the exemption is needed ("Android may kill the container in
the background") on the same card as the consent button, and the exemption
is only ever requested after the user taps it, never at startup.

Physical-device QA checklist (not runnable in CI): on arm64 hardware, run
setup → start → green Test Connection → background the app for 10+ minutes
→ foreground and re-test (must still be healthy); confirm the Stop action
removes the notification and frees the port.

### Already on Termux?

Termux users need nothing new: install any proot distro in Termux, run the
standalone backend binary (or `uv run uvicorn backend.main:app`) inside it,
and point the app at it with the existing transports — `directHttp` to the
distro's loopback address, or the SSH provisioning wizard over `sshd`.
One paragraph is all this takes because the app already speaks plain
HTTP/WebSocket to any Linux host.

---

## Flutter Client Setup

Prerequisites: Flutter SDK (>= 3.29.0).

### Run on Device or Emulator

```bash
flutter pub get
flutter run --dart-define=WFP_BACKEND_RELEASE_REPO=xxparthparekhxx/workfromphone
```

### Build Android APK

```bash
flutter build apk --release --dart-define=WFP_BACKEND_RELEASE_REPO=xxparthparekhxx/workfromphone
```

The `WFP_BACKEND_RELEASE_REPO` flag instructs the built-in remote setup wizard to fetch backend binaries and manifests directly from your repository releases.

---

## Security Invariants

1. **Authentication**: When `ACCESS_TOKEN` is set, all capability routes and WebSocket connections require a valid `Bearer <token>` authorization header with constant-time verification (`hmac.compare_digest`). On-device (No-PC) mode always sets a token, even on loopback, since any app on the phone can reach localhost.
2. **Network Exposure Defense**: The backend binds to loopback (`127.0.0.1`) by default. Binding to non-loopback interfaces without an explicit `ACCESS_TOKEN` causes startup abort.
3. **CORS & Origin Hardening**: Wildcard CORS origins (`*`) are disallowed and stripped at startup. Unauthorized WebSocket origin headers are rejected with code 4403.
4. **Sandboxed Paths**: File system operations strictly resolve paths and reject any path traversal outside designated project roots.
5. **Child Process Isolation**: Terminal subshells and background commands purge sensitive environment variables (tokens, keys, secrets, passwords) prior to spawning child processes.
6. **Client-Side Secret Storage**: All SSH credentials, bearer tokens, and API keys are stored exclusively in encrypted storage (`FlutterSecureStorage`).

---

## API & WebSocket Endpoints

| Protocol / Method | Endpoint | Auth Required | Description |
| :--- | :--- | :---: | :--- |
| `GET` | `/api/v1/health` | No | Service status and version health check |
| `GET` | `/api/v1/system/snapshot` | Yes | Snapshot of CPU, memory, disks, and GPUs |
| `WS` | `/api/v1/system/ws` | Yes | Real-time system monitoring WebSocket stream |
| `WS` | `/api/v1/terminal/ws` | Yes | Interactive persistent PTY terminal session |
| `GET` | `/api/v1/fs/browse` | Yes | Sandboxed directory and file tree browsing |
| `GET` | `/api/v1/fs/file` | Yes | Read file contents with optional slicing |
| `POST` | `/api/v1/fs/file` | Yes | Write / save file contents |
| `POST` | `/api/v1/fs/upload` | Yes | Chunked multipart binary file upload |
| `GET` | `/api/v1/git/status` | Yes | Git working tree status |
| `GET` | `/api/v1/git/diff` | Yes | Staged and unstaged unified diffs |
| `POST` | `/api/v1/git/stage` | Yes | Stage modified files (`git add`) |
| `POST` | `/api/v1/git/commit` | Yes | Commit staged changes |
| `POST` | `/api/v1/llm/chat` | Yes | Autonomous LLM agent task loop (SSE stream) |
| `WS` | `/api/v1/llm/ws` | Yes | Interactive agent loop WebSocket stream |
| `ANY` | `/api/v1/preview/proxy/{id}/{path}` | Yes | Reverse-proxy live web development server |
| `POST` | `/api/v1/artifacts/publish` | Yes | Publish an artifact with optional PIN |
| `POST` | `/api/v1/search` | Yes | Web search via SearXNG (with scraping fallback) |

---

## Verification & Testing

Run tests across both client and backend:

```bash
# 1. Analyze Flutter code
flutter analyze

# 2. Run Flutter test suite
flutter test

# 3. Run Backend test suite
cd backend && uv run pytest -q

# 4. Format Dart code
dart format lib/ test/
```

---

## Repository Structure

```text
.
├── .github/
│   └── workflows/
│       ├── backend-release.yml      # Backend + Debian rootfs release matrix (x86_64, aarch64)
│       └── deploy-pages.yml         # GitHub Pages automated deployment
├── backend/
│   ├── src/backend/
│   │   ├── api/v1/                  # API route endpoints
│   │   ├── core/                    # Config, security, auth guards
│   │   ├── schemas/                 # Pydantic v2 validation models
│   │   └── services/                # PTY, System, FS, Git, LLM, Preview services
│   ├── tests/                       # Backend test suite (pytest)
│   ├── docker-entrypoint.sh         # Container/proot entrypoint (token bootstrap)
│   └── workfromphone-backend.spec   # PyInstaller specification
├── rootfs/                          # On-device Debian rootfs packaging
│   ├── build-debian-rootfs.sh       # debootstrap minimal image (arm64/amd64)
│   ├── bootstrap.sh                 # First-boot guest setup (DNS, toolchain)
│   └── launch.sh                    # Guest backend launcher (token-guarded)
├── android/app/src/main/
│   ├── jniLibs/<abi>/               # Patched proot (via scripts/fetch-proot.sh)
│   └── kotlin/.../container/        # RootfsManager, ProotRunner, foreground service
├── lib/
│   ├── models/                      # Dart data models
│   ├── screens/                     # Feature screens (Chat, Files, Git, Terminal, System, Preview, Settings)
│   ├── services/                    # HTTP, WebSocket, SSH provisioning, SecureStorage
│   ├── utils/                       # Theme (Tokyo Night), ANSI parsers, icons
│   └── widgets/                     # Reusable UI widgets
├── scripts/
│   └── install.sh                   # 1-line server installation script
├── website/                         # Static landing page & download site (GitHub Pages)
└── test/                            # Flutter widget and unit tests
```

---

## License

Licensed under the GNU General Public License v3.0. See the [LICENSE](LICENSE) file for details.
