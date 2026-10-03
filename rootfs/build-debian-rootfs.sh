#!/usr/bin/env bash
# Build a minimal Debian rootfs for WorkFromPhone on-device mode.
#
# Usage:
#   rootfs/build-debian-rootfs.sh <arch> [--overlay-only] [--out DIR]
#
#   <arch> is the Debian architecture: arm64 (phones) or amd64 (emulator).
#   The published tarball name uses the release-arch naming from
#   .github/workflows/backend-release.yml: aarch64 / x86_64.
#
# Modes:
#   Full debootstrap (default): requires root and debootstrap; run on a
#     native-arch host (cross-arch additionally needs qemu-user-static). CI
#     (backend-release.yml) uses this mode on a runner matching each target
#     arch, producing a bootable ~150-300MB tarball with Debian minimal +
#     backend + git/curl/ca-certificates/build-essential. Prefers the
#     prebuilt PyInstaller backend binary (--backend-tar) and falls back to
#     an apt-python venv installed inside the rootfs on first boot.
#   --overlay-only: assembles just the WorkFromPhone overlay
#     (opt/workfromphone/...) from an already-built backend tarball. Local /
#     advanced use only — the published image is the full rootfs above, not
#     an overlay.
set -euo pipefail

ARCH=""
OVERLAY_ONLY=0
OUT_DIR="$(pwd)"
BACKEND_TAR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --overlay-only) OVERLAY_ONLY=1; shift ;;
    --out=*) OUT_DIR="${1#--out=}"; shift ;;
    --out) OUT_DIR="${2:-}"; shift 2 ;;
    --backend-tar=*) BACKEND_TAR="${1#--backend-tar=}"; shift ;;
    --backend-tar) BACKEND_TAR="${2:-}"; shift 2 ;;
    -h|--help)
      echo "usage: $0 <arm64|amd64> [--overlay-only] [--out DIR] [--backend-tar FILE]" >&2
      exit 0 ;;
    *)
      if [ -z "$ARCH" ]; then ARCH="$1"; else
        echo "unexpected argument: $1" >&2; exit 2
      fi
      shift ;;
  esac
done

case "$ARCH" in
  arm64|aarch64) DEB_ARCH=arm64; REL_ARCH=aarch64 ;;
  amd64|x86_64) DEB_ARCH=amd64; REL_ARCH=x86_64 ;;
  *) echo "usage: $0 <arm64|amd64> [--overlay-only] [--out DIR] [--backend-tar FILE]" >&2; exit 2 ;;
esac

VERSION="${VERSION:-$(git describe --tags --match 'backend-v*' --abbrev=0 2>/dev/null | sed 's/^backend-v//' || echo dev)}"
TARBALL="workfromphone-rootfs-debian-${REL_ARCH}.tar.gz"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

OVERLAY="$STAGE/overlay"
mkdir -p "$OVERLAY/opt/workfromphone" "$OUT_DIR"

# --- Overlay contents (shipped in both modes) ---
if [ -n "$BACKEND_TAR" ] && [ -f "$BACKEND_TAR" ]; then
  tar -xzf "$BACKEND_TAR" -C "$OVERLAY/opt/workfromphone"
  chmod 700 "$OVERLAY/opt/workfromphone/workfromphone-backend" || true
else
  echo "NOTE: no --backend-tar given; overlay will fetch the backend on first boot." >&2
fi
cp "$SCRIPT_DIR/launch.sh" "$OVERLAY/opt/workfromphone/launch.sh"
cp "$SCRIPT_DIR/bootstrap.sh" "$OVERLAY/opt/workfromphone/bootstrap.sh"
chmod 755 "$OVERLAY/opt/workfromphone/launch.sh" "$OVERLAY/opt/workfromphone/bootstrap.sh"
printf '%s\n' "$VERSION" > "$OVERLAY/opt/workfromphone/VERSION"
cat > "$OVERLAY/opt/workfromphone/apt-packages.txt" <<'EOF'
git
curl
ca-certificates
build-essential
openssh-client
python3
python3-venv
python3-pip
nodejs
npm
vim
nano
tmux
jq
unzip
sqlite3
EOF

if [ "$OVERLAY_ONLY" = "1" ]; then
  tar -C "$OVERLAY" -czf "$OUT_DIR/$TARBALL" .
  (cd "$OUT_DIR" && sha256sum "$TARBALL" > "$TARBALL.sha256")
  echo "Wrote $OUT_DIR/$TARBALL (overlay-only)"
  exit 0
fi

# --- Full debootstrap build (needs root) ---
if [ "$(id -u)" -ne 0 ]; then
  echo "Full rootfs build needs root (debootstrap). Re-run with sudo or use --overlay-only." >&2
  exit 1
fi
command -v debootstrap >/dev/null || { echo "debootstrap is required" >&2; exit 1; }
if [ "$DEB_ARCH" != "$(dpkg --print-architecture 2>/dev/null || echo amd64)" ]; then
  command -v "qemu-$([ "$DEB_ARCH" = arm64 ] && echo aarch64 || echo x86-64)-static" >/dev/null \
    || { echo "qemu-user-static is required for cross-arch debootstrap" >&2; exit 1; }
fi

ROOTFS="$STAGE/rootfs"
debootstrap --variant=minbase --arch="$DEB_ARCH" --include=ca-certificates \
  bookworm "$ROOTFS" http://deb.debian.org/debian

cp -a "$OVERLAY/." "$ROOTFS/"

# Minimal device configuration so the rootfs boots cleanly under proot.
cat > "$ROOTFS/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
echo "workfromphone" > "$ROOTFS/etc/hostname"
printf 'LANG=C.UTF-8\nLC_ALL=C.UTF-8\n' > "$ROOTFS/etc/default/locale"

# Slim image: only the backend plus its toolchain, no docs/locales.
chroot "$ROOTFS" apt-get update
chroot "$ROOTFS" apt-get install --no-install-recommends -y \
  git curl ca-certificates build-essential openssh-client \
  python3 python3-venv python3-pip nodejs npm vim nano tmux jq unzip sqlite3
chroot "$ROOTFS" apt-get clean
rm -rf "$ROOTFS/var/lib/apt/lists/"* "$ROOTFS/usr/share/doc" "$ROOTFS/usr/share/man"
mkdir -p "$ROOTFS/workspace"

tar -C "$ROOTFS" -czf "$OUT_DIR/$TARBALL" .
(cd "$OUT_DIR" && sha256sum "$TARBALL" > "$TARBALL.sha256")
echo "Wrote $OUT_DIR/$TARBALL (full debootstrap, Debian bookworm+$VERSION)"
