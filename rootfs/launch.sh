#!/bin/sh
# Launch the WorkFromPhone backend INSIDE the proot Debian guest.
#
# Environment (injected by ProotRunner via `/usr/bin/env -i` so host
# linker vars like LD_LIBRARY_PATH do not leak into Debian):
#   ACCESS_TOKEN  mandatory, even on loopback: any on-device app can reach
#                 127.0.0.1, so an unauthenticated localhost server is not safe.
#   PORT          backend port (default 8000).
#   WORKSPACE     bind-mounted workspace path visible to the Flutter client.
#   HOST          always 127.0.0.1 on-device.
set -eu

WFP=/opt/workfromphone

if [ -z "${ACCESS_TOKEN:-}" ]; then
  echo "ACCESS_TOKEN is required (see No-PC mode docs)" >&2
  exit 10
fi

export HOST=127.0.0.1
export PORT="${PORT:-8000}"
export DEBUG="${DEBUG:-false}"
export WORKSPACE="${WORKSPACE:-/workspace}"
export HOME="${HOME:-/home/coder}"

cd "$WORKSPACE" 2>/dev/null || cd /

if [ -x "$WFP/workfromphone-backend" ]; then
  exec "$WFP/workfromphone-backend"
elif [ -x "$WFP/.venv/bin/python" ]; then
  exec "$WFP/.venv/bin/python" -m backend.main
else
  echo "No backend binary found in $WFP" >&2
  exit 11
fi
