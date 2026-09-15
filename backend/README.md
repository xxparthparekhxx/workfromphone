# WorkFromPhone Backend

FastAPI server for the WorkFromPhone project.

## Features

- **FastAPI**: Modern, high-performance web framework.
- **Linux System Monitor**: CPU, memory, storage, network, process, thermal, and GPU metrics.
- **Persistent PTY**: Independent interactive shell sessions over authenticated WebSockets.
- **Optional Bearer Authentication**: Protects every capability endpoint when `ACCESS_TOKEN` is set.
- **Pydantic v2**: Strict type safety, validation, and serialization.
- **Pydantic Settings**: Centralized environment variable management (`.env`).
- **CORS Middleware**: Pre-configured with explicit local development origins.
- **Modular Structure**: Organized by `core`, `schemas`, `api/v1`.
- **Package Management**: Powered by [`uv`](https://github.com/astral-sh/uv) (fast Python package manager).

---

## Project Structure

```text
backend/
├── src/
│   └── backend/
│       ├── api/
│       │   └── v1/
│       │       ├── endpoints/
│       │       │   ├── __init__.py
│       │       │   └── health.py
│       │       ├── __init__.py
│       │       └── router.py
│       ├── core/
│       │   ├── __init__.py
│       │   └── config.py
│       ├── schemas/
│       │   ├── __init__.py
│       │   └── health.py
│       ├── __init__.py
│       └── main.py
├── .env.example
├── .gitignore
├── pyproject.toml
├── requirements.txt
└── README.md
```

---

## Getting Started

### 1. Using `uv` (Recommended)

Make sure you are in the `backend/` directory:

```bash
cd backend
```

#### Run the development server with auto-reload:
```bash
uv run uvicorn backend.main:app --reload --host 127.0.0.1 --port 8000
```
or simply:
```bash
uv run backend
```

The server binds `127.0.0.1` by default. Binding any other interface requires
a strong `ACCESS_TOKEN`: without one the backend refuses to start, because
every capability route — including terminal command execution — would be
reachable unauthenticated. Release installations created by the Flutter setup
wizard bind to `127.0.0.1` and are reached through SSH or Cloudflare Tunnel.

`CORS_ORIGINS` must list explicit origins. A `"*"` entry is stripped at
startup, since it would let any website a user visits reach this backend.

---

## Self-contained Linux releases

Tags matching `backend-v*` build x86_64 and ARM64 executables using
`.github/workflows/backend-release.yml`. Each release includes:

- `workfromphone-backend-linux-x86_64.tar.gz`
- `workfromphone-backend-linux-aarch64.tar.gz`
- `backend-manifest.json` containing download URLs and SHA-256 checksums

Build the Flutter app with the release repository used by the setup wizard:

```bash
flutter build apk \
  --dart-define=WFP_BACKEND_RELEASE_REPO=owner/repository
```

The wizard verifies the SSH host key, detects the remote architecture,
checks the archive checksum, and installs a systemd user service under the
remote account.

---

### 2. Docker Developer Environment (Full Workspace)

The `Dockerfile` ships a full developer workspace (Python + Node.js for
Vite/Next preview targets, C build toolchain, `vim/tmux/jq/ripgrep/sqlite3`;
`coder` has passwordless sudo) with the backend pre-installed:

```bash
# From the repository root:
docker compose up --build -d
docker compose logs backend  # grab the generated ACCESS_TOKEN on first run

# Or plain docker:
docker build -t workfromphone-backend backend/
docker run -d --name wfp -v wfp-home:/home/coder -p 8000:8000 workfromphone-backend
docker logs wfp  # generated ACCESS_TOKEN (persisted in the wfp-home volume)
```

Notes:

- `HOST`/`PORT` env vars are honored (the entrypoint rewrites uvicorn's
  `--host`/`--port` from them), e.g. `-e PORT=9000 -p 9000:9000`.
- `WORKSPACE=/home/coder` constrains the fs/git/terminal APIs to the
  workspace; mount projects there.
- Binding `0.0.0.0` without `ACCESS_TOKEN` auto-generates a token into
  `~/.config/workfromphone/backend.env` — use a named volume so it survives
  restarts. Point the Flutter app at `http://<host>:8000` with that token.

---

### 3. Using Standard Python Virtual Environment (`venv`)

```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn backend.main:app --reload --host 127.0.0.1 --port 8000
```

---

## Interactive Documentation

Once the server is running, access:

- **Swagger UI**: [http://localhost:8000/docs](http://localhost:8000/docs)
- **ReDoc**: [http://localhost:8000/redoc](http://localhost:8000/redoc)
- **Health Check**: [http://localhost:8000/api/v1/health](http://localhost:8000/api/v1/health)
