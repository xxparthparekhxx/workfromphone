# WorkFromPhone Agent Guide

## Project overview

WorkFromPhone is a Flutter mobile/desktop client backed by a Linux-only
FastAPI service. The client provides chat, files, Git, persistent PTY
terminals, system monitoring, and SSH-based backend provisioning.

- Flutter application: `lib/`
- Flutter tests: `test/`
- FastAPI backend: `backend/src/backend/`
- Backend tests: `backend/tests/`
- Linux release workflow: `.github/workflows/backend-release.yml`

## Working rules

- Preserve unrelated and uncommitted user changes.
- Do not launch, install, or hot-reload the app unless the user explicitly
  requests it. The user normally runs the app and supplies runtime output.
- Do not commit or push changes unless explicitly requested.
- Use package managers when changing dependencies:
  `flutter pub add/remove` and `uv add/remove`.
- Never store credentials, SSH passwords, access tokens, or LLM keys in
  source control or plain `SharedPreferences`.
- Do not manually edit generated Flutter plugin registrant files.

## Flutter conventions

- Follow `flutter_lints` and keep `flutter analyze` clean.
- Format changed Dart files with `dart format`.
- Prefer Cupertino icons for interface actions to match the current visual
  language. Material widgets and theming remain acceptable.
- Keep transport and persistence logic in `lib/services/`, JSON models in
  `lib/models/`, and feature UI in `lib/screens/` or `lib/widgets/`.
- Use `flutter_secure_storage` for secrets. Persist only non-sensitive profile
  metadata with `StorageService`.
- Scope backend bearer tokens to their configured URL origin. Never forward a
  token after the backend URL changes.
- Keep WebSocket sessions independently disposable and prevent reconnect
  timers from surviving widget or session disposal.
- File transfers must remain binary-safe and stream uploads rather than loading
  large files fully into memory.
- Add stable widget keys for important controls used by tests.

## Backend conventions

- Keep API handlers thin; place reusable behavior in `services/` and response
  contracts in `schemas/`.
- The backend supports Linux. PTY code may rely on `pty`, `fcntl`, `termios`,
  and Linux `/proc` behavior.
- Capability routes must remain protected by bearer authentication whenever
  `ACCESS_TOKEN` is configured. `/api/v1/health` may remain public.
- Resolve project paths before use and verify they remain under the project
  root. Reject path traversal before reading, writing, uploading, downloading,
  deleting, or invoking Git.
- Stream multipart uploads to temporary files, enforce
  `MAX_UPLOAD_BYTES`, and atomically replace destinations.
- Do not expose environment variables, process arguments, credentials, or
  unrestricted host details through monitoring endpoints.
- SSE and WebSocket errors should use explicit event types and always clean up
  subprocesses, files, sockets, and tasks.

## Verification

Run checks proportional to the change:

```bash
flutter analyze
flutter test
cd backend && uv run pytest -q
```

For backend release changes, also build and smoke-test:

```bash
cd backend
uv run pyinstaller --clean --noconfirm workfromphone-backend.spec
```

Do not report success if a relevant check failed. Call out unrelated existing
failures separately instead of silently modifying unrelated files.

## Remote backend releases

The setup wizard expects versioned x86_64 and ARM64 artifacts plus
`backend-manifest.json`. Production Flutter builds must configure:

```bash
--dart-define=WFP_BACKEND_RELEASE_REPO=owner/repository
```

SSH host fingerprints must be verified and pinned. Public hosts use encrypted
SSH forwarding with the backend bound to localhost. Private hosts may use a
pre-created named Cloudflare Tunnel and still require backend bearer auth.
