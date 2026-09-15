#!/bin/sh
# WorkFromPhone Backend - container entrypoint.
#
# Shared with the on-device (proot) launcher: both execute the backend with
# HOST/PORT/ACCESS_TOKEN taken from the environment. When binding a
# non-loopback HOST without ACCESS_TOKEN, generate and persist a token next
# to the binary so the server never comes up unauthenticated on a LAN.
set -eu

TOKEN_FILE="${WFP_TOKEN_FILE:-$HOME/.config/workfromphone/backend.env}"

if [ -z "${ACCESS_TOKEN:-}" ] && [ "${HOST:-0.0.0.0}" != "127.0.0.1" ] && [ "${HOST:-0.0.0.0}" != "localhost" ]; then
  if [ -f "$TOKEN_FILE" ]; then
    # shellcheck disable=SC1090
    . "$TOKEN_FILE"
  fi
  if [ -z "${ACCESS_TOKEN:-}" ]; then
    ACCESS_TOKEN="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 48)"
    export ACCESS_TOKEN
    mkdir -p "$(dirname "$TOKEN_FILE")"
    {
      printf 'HOST=%s\n' "${HOST:-0.0.0.0}"
      printf 'PORT=%s\n' "${PORT:-8000}"
      printf 'DEBUG=%s\n' "${DEBUG:-false}"
      printf 'ACCESS_TOKEN=%s\n' "$ACCESS_TOKEN"
    } > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    printf 'Generated ACCESS_TOKEN and saved it to %s\n' "$TOKEN_FILE" >&2
  fi
fi

export HOST="${HOST:-0.0.0.0}"
export PORT="${PORT:-8000}"

# The Dockerfile CMD carries default --host/--port flags, but HOST/PORT env
# is the documented override (`docker run -e PORT=9000`). When exec'ing the
# default uvicorn server, strip any baked-in --host/--port flags and re-append
# them from the environment so env and verify_network_exposure() agree on the
# actual bind address (a mismatch would be a security hole: guarded as
# loopback while really bound to 0.0.0.0). Custom commands pass through.
if [ "${1:-}" = "uvicorn" ]; then
  filtered=""
  skip_next=0
  for arg in "$@"; do
    if [ "$skip_next" = "1" ]; then
      skip_next=0
      continue
    fi
    case "$arg" in
      --host|--port) skip_next=1; continue ;;
      --host=*|--port=*) continue ;;
      *) filtered="$filtered $arg" ;;
    esac
  done
  # shellcheck disable=SC2086
  set -- $filtered --host "$HOST" --port "$PORT"
fi

exec "$@"
