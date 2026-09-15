#!/bin/sh
# First-boot bootstrap executed INSIDE the proot Debian guest (as root).
#
# Invoked once by RootfsManager after extraction, then again on every backend
# start only to repair resolv.conf. Installs the full dev toolchain
# (see ../opt/workfromphone/apt-packages.txt) when a network is available,
# creates the coder user, and falls back to an apt-python venv when the
# prebuilt PyInstaller binary is missing (e.g. overlay-only rootfs where the
# binary download failed).
set -eu

WFP=/opt/workfromphone
export DEBIAN_FRONTEND=noninteractive

# proot guests inherit a broken/empty resolv.conf; always repair it.
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf || true

if [ ! -f /opt/workfromphone/.bootstrapped ]; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update || true
    # shellcheck disable=SC2046
    apt-get install --no-install-recommends -y $(cat "$WFP/apt-packages.txt") || true
    apt-get clean || true
    rm -rf /var/lib/apt/lists/* || true
  fi
  if ! id coder >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash coder || true
  fi
  mkdir -p /workspace
  # apt-python venv fallback when no prebuilt binary is present.
  if [ ! -x "$WFP/workfromphone-backend" ] && command -v python3 >/dev/null 2>&1; then
    if [ -d "$WFP/src" ]; then
      python3 -m venv "$WFP/.venv" || true
      "$WFP/.venv/bin/pip" install --no-cache-dir "$WFP/src" || true
      printf '#!/bin/sh\nexec %s/.venv/bin/python -m backend.main "$@"\n' "$WFP" > "$WFP/workfromphone-backend"
      chmod 755 "$WFP/workfromphone-backend" || true
    fi
  fi
  date -u +%FT%TZ > "$WFP/.bootstrapped" || true
fi
