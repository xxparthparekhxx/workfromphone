#!/usr/bin/env bash
# ==============================================================================
# WorkFromPhone - Linux Backend Automated Installer
# https://github.com/xxparthparekhxx/workfromphone
# ==============================================================================
set -euo pipefail

REPO="${WFP_REPO:-xxparthparekhxx/workfromphone}"
INSTALL_DIR="${WFP_INSTALL_DIR:-$HOME/.local/share/workfromphone}"
CONFIG_DIR="${WFP_CONFIG_DIR:-$HOME/.config/workfromphone}"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
PORT="${PORT:-8000}"
HOST="${HOST:-127.0.0.1}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
log_success() { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

printf "\n${BOLD}${CYAN}  WorkFromPhone - Backend Installer${NC}\n"
printf "${CYAN}  ======================================${NC}\n\n"

# 1. OS & Architecture Check
OS="$(uname -s)"
if [ "$OS" != "Linux" ]; then
  log_error "WorkFromPhone backend only runs on Linux (current: $OS)."
  exit 1
fi

ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64|amd64) ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
  *)
    log_error "Unsupported architecture: $ARCH_RAW. Supported architectures: x86_64, aarch64."
    exit 1
    ;;
esac

log_info "Detected OS: Linux ($ARCH)"

# 2. Dependency Check
for cmd in curl tar sha256sum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Required tool '$cmd' is missing. Please install it first."
    exit 1
  fi
done

HAS_SYSTEMD=0
if command -v systemctl >/dev/null 2>&1 && systemctl --user list-units >/dev/null 2>&1; then
  HAS_SYSTEMD=1
  log_info "Detected systemd user session."
else
  log_warn "systemd user session not active. Will install standalone binary without systemd service."
fi

# 3. Fetch Release Manifest
log_info "Fetching latest release manifest from GitHub ($REPO)..."
MANIFEST_URL="https://github.com/$REPO/releases/latest/download/backend-manifest.json"
MANIFEST_JSON="$(curl -fsSL "$MANIFEST_URL" 2>/dev/null || true)"

if [ -z "$MANIFEST_JSON" ]; then
  log_error "Could not fetch release manifest from $MANIFEST_URL"
  exit 1
fi

# Extract version, URL, and sha256
VERSION="$(printf '%s' "$MANIFEST_JSON" | grep -o '"version": *"[^"]*"' | head -n 1 | cut -d'"' -f4 || echo "unknown")"
ARCH_SECTION="$(printf '%s' "$MANIFEST_JSON" | grep -A 5 "\"$ARCH\":" || true)"
DOWNLOAD_URL="$(printf '%s' "$ARCH_SECTION" | grep -o '"url": *"[^"]*"' | head -n 1 | cut -d'"' -f4 || true)"
CHECKSUM="$(printf '%s' "$ARCH_SECTION" | grep -o '"sha256": *"[^"]*"' | head -n 1 | cut -d'"' -f4 || true)"

if [ -z "$DOWNLOAD_URL" ] || [ -z "$CHECKSUM" ]; then
  log_error "Could not find release artifact for architecture: $ARCH in manifest."
  exit 1
fi

log_info "Target Version: v$VERSION"
log_info "Downloading $DOWNLOAD_URL..."

# 4. Download and Verify
TMP_ARCHIVE="$(mktemp --suffix=.tar.gz)"
trap 'rm -f "$TMP_ARCHIVE"' EXIT

curl -fsSL "$DOWNLOAD_URL" -o "$TMP_ARCHIVE"
ACTUAL_CHECKSUM="$(sha256sum "$TMP_ARCHIVE" | awk '{print $1}')"

if [ "$ACTUAL_CHECKSUM" != "$CHECKSUM" ]; then
  log_error "Checksum verification failed!"
  log_error "Expected: $CHECKSUM"
  log_error "Got:      $ACTUAL_CHECKSUM"
  exit 1
fi
log_success "SHA-256 checksum verified ($ACTUAL_CHECKSUM)"

# 5. Unpack Binary
VERSION_DIR="$INSTALL_DIR/server/$VERSION"
mkdir -p "$VERSION_DIR" "$CONFIG_DIR"
tar -xzf "$TMP_ARCHIVE" -C "$VERSION_DIR"
chmod 700 "$VERSION_DIR/workfromphone-backend"

ln -sfn "$VERSION_DIR" "$INSTALL_DIR/current"
log_success "Installed binary to $INSTALL_DIR/current/workfromphone-backend"

# 6. Generate or preserve ACCESS_TOKEN & Config
ENV_FILE="$CONFIG_DIR/backend.env"
ACCESS_TOKEN=""

if [ -f "$ENV_FILE" ]; then
  ACCESS_TOKEN="$(grep -E '^ACCESS_TOKEN=' "$ENV_FILE" | cut -d'=' -f2- || true)"
fi

if [ -z "$ACCESS_TOKEN" ]; then
  if command -v openssl >/dev/null 2>&1; then
    ACCESS_TOKEN="$(openssl rand -hex 24)"
  else
    ACCESS_TOKEN="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  fi
fi

cat > "$ENV_FILE" <<EOF
HOST=$HOST
PORT=$PORT
DEBUG=false
ACCESS_TOKEN=$ACCESS_TOKEN
EOF
chmod 600 "$ENV_FILE"
log_success "Configuration saved at $ENV_FILE"

# 7. Configure and start systemd user service if supported
if [ "$HAS_SYSTEMD" -eq 1 ]; then
  mkdir -p "$SYSTEMD_USER_DIR"
  SERVICE_FILE="$SYSTEMD_USER_DIR/workfromphone-backend.service"

  cat > "$SERVICE_FILE" <<EOF
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

  systemctl --user daemon-reload
  systemctl --user enable --now workfromphone-backend.service
  
  # Health check
  log_info "Verifying backend health..."
  HEALTHY=0
  for i in $(seq 1 10); do
    if curl -fsS "http://$HOST:$PORT/api/v1/health" >/dev/null 2>&1; then
      HEALTHY=1
      break
    fi
    sleep 1
  done

  if [ "$HEALTHY" -eq 1 ]; then
    log_success "Service is active and healthy!"
  else
    log_warn "Service started but health check timed out. Check logs with: journalctl --user -u workfromphone-backend -e"
  fi
fi

printf "\n${BOLD}${GREEN}======================================================${NC}\n"
printf "${BOLD}${GREEN}  WorkFromPhone Backend v%s Installed Successfully!${NC}\n" "$VERSION"
printf "${BOLD}${GREEN}======================================================${NC}\n\n"

printf "  ${BOLD}Host / Bind:${NC}   %s:%s\n" "$HOST" "$PORT"
printf "  ${BOLD}Access Token:${NC}  ${YELLOW}%s${NC}\n" "$ACCESS_TOKEN"
printf "  ${BOLD}Config File:${NC}   %s\n" "$ENV_FILE"
printf "  ${BOLD}Executable:${NC}    %s/current/workfromphone-backend\n\n" "$INSTALL_DIR"

if [ "$HAS_SYSTEMD" -eq 1 ]; then
  printf "  ${BOLD}Service Control:${NC}\n"
  printf "    systemctl --user status workfromphone-backend\n"
  printf "    systemctl --user restart workfromphone-backend\n"
  printf "    journalctl --user -u workfromphone-backend -f\n\n"
else
  printf "  ${BOLD}Manual Run Command:${NC}\n"
  printf "    %s/current/workfromphone-backend\n\n" "$INSTALL_DIR"
fi

printf "  ${BOLD}Mobile App Connection:${NC}\n"
printf "  1. In the WorkFromPhone app, open Settings -> Add Backend.\n"
printf "  2. Choose SSH Tunnel or Direct Connection with your host details.\n"
printf "  3. Enter the Access Token above.\n\n"
