# WorkFromPhone Backend - container image
#
# Runs the FastAPI backend inside a container so the phone app has something
# to talk to even when there is no dedicated PC available: point the client
# at any host running this image (a VPS, a home server, a spare machine).
#
# The container doubles as a full developer workspace: mount your project(s)
# into /home/coder (WORKSPACE) and browse/edit/run them from the app exactly
# as you would on a bare-metal install. Ships with git + C build toolchain +
# Node.js (Vite/Next preview targets) + everyday CLI tools (vim, tmux, jq,
# ripgrep, sqlite3); coder has passwordless sudo for extra apt packages.

FROM python:3.13-slim AS builder

RUN pip install --no-cache-dir uv

WORKDIR /build
# Build the venv directly at its final path so console-script shebangs
# (#!/opt/venv/bin/python) stay valid after COPY. A relocated .venv would
# leave shebangs pointing at /build/.venv and fail with "uvicorn: not found".
ENV UV_PROJECT_ENVIRONMENT=/opt/venv
COPY pyproject.toml uv.lock ./
COPY src ./src
COPY README.md ./

# --no-editable: bake backend code into site-packages instead of a .pth
# pointing at /build/src (which does not exist in the runtime stage).
RUN uv sync --frozen --no-dev --no-editable

FROM python:3.13-slim

LABEL org.opencontainers.image.title="workfromphone-backend"
LABEL org.opencontainers.image.description="FastAPI backend for the WorkFromPhone mobile client"
LABEL org.opencontainers.image.source="https://github.com/xxparthparekhxx/workfromphone"

# Full developer environment: version control + C toolchain (native wheels,
# neovim plugins) + Node.js (Vite/Next preview targets) + everyday CLI tools.
# coder gets passwordless sudo so extra apt packages can be added at runtime.
RUN apt-get update && apt-get install --no-install-recommends -y \
    git \
    curl \
    ca-certificates \
    openssh-client \
    build-essential \
    python3-dev \
    nodejs \
    npm \
    sudo \
    vim \
    nano \
    tmux \
    jq \
    unzip \
    zip \
    htop \
    ripgrep \
    sqlite3 \
    locales \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen 2>/dev/null || true \
    && locale-gen en_US.UTF-8 2>/dev/null || true

RUN useradd --create-home --shell /bin/bash coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder \
    && chmod 440 /etc/sudoers.d/coder
USER coder
WORKDIR /home/coder
ENV HOME=/home/coder
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PYTHONUNBUFFERED=1
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY --from=builder --chown=coder:coder /opt/venv /opt/venv
COPY --chown=coder:coder docker-entrypoint.sh /opt/workfromphone/docker-entrypoint.sh
RUN chmod 755 /opt/workfromphone/docker-entrypoint.sh

# Containers only reach the outside world through published ports, so
# binding the loopback address here would make the server unreachable from
# the host. ACCESS_TOKEN is required whenever HOST isn't loopback (see
# backend/src/backend/main.py:verify_network_exposure) - the entrypoint
# generates one on first run if none is supplied. WORKSPACE constrains the
# fs/git/terminal APIs to the dev workspace (matches the on-device
# /workspace guest); mount projects into /home/coder. Persist /home/coder
# in a named volume so the generated token and your projects survive restarts:
#   docker run -v wfp-home:/home/coder -p 8000:8000 workfromphone-backend
ENV HOST=0.0.0.0
ENV PORT=8000
ENV DEBUG=false
ENV WORKSPACE=/home/coder

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT:-8000}/api/v1/health" || exit 1

ENTRYPOINT ["/opt/workfromphone/docker-entrypoint.sh"]
# Default args; the entrypoint rewrites --host/--port from $HOST/$PORT so
# `docker run -e PORT=9000 -p 9000:9000` actually binds 9000.
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
