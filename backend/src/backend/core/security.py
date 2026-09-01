import hashlib
import hmac
import ipaddress
import os
import re
import socket
import time
from urllib.parse import urlparse

from backend.core.config import settings


INTERNAL_ERROR_DETAIL = "Internal server error"

_SENSITIVE_ENV_MARKERS = (
    "SECRET",
    "PASSWORD",
    "TOKEN",
    "API_KEY",
    "APIKEY",
    "CREDENTIAL",
    "PRIVATE_KEY",
    "ACCESS_KEY",
)
_ENV_KEEP = {
    "TERM",
    "COLORTERM",
    "FORCE_COLOR",
    "SSH_AUTH_SOCK",
    "SSH_AGENT_PID",
}

_BLOCKED_METADATA_HOSTS = {
    "metadata.google.internal",
    "metadata.google.com",
    "instance-data.ec2.internal",
}
_BLOCKED_IP_NETWORKS = (
    ipaddress.ip_network("169.254.0.0/16"),
    ipaddress.ip_network("fe80::/10"),
)
_BLOCKED_PREVIEW_PORTS = {
    22,
    25,
    53,
    135,
    139,
    445,
    1433,
    1521,
    2375,
    2376,
    3306,
    3389,
    5432,
    5900,
    6379,
    9200,
    11211,
    27017,
}
_LOOPBACK_WS_HOSTS = {
    "localhost",
    "127.0.0.1",
    "::1",
    "testserver",
    "10.0.2.2",
}

_PIN_PBKDF2_ROUNDS = 100_000
_PUBLIC_PATHS = {
    "/",
    "/robots.txt",
    f"{settings.API_V1_PREFIX}/health",
}
_DOCS_PATHS = {
    "/docs",
    "/docs/oauth2-redirect",
    "/openapi.json",
    "/redoc",
}
_SENSITIVE_PROXY_HEADERS = {
    "authorization",
    "cookie",
    "set-cookie",
    "proxy-authorization",
    "x-api-key",
    "x-access-token",
}

_PIN_PATTERN = re.compile(r"^\d{4,8}$")


def normalize_url_path(path: str) -> str:
    """Collapse `.` and `..` segments without touching the filesystem."""
    parts: list[str] = []
    for part in path.split("/"):
        if part in {"", "."}:
            continue
        if part == "..":
            if parts:
                parts.pop()
            continue
        parts.append(part)
    return "/" + "/".join(parts)


def is_public_path(path: str) -> bool:
    normalized = normalize_url_path(path)
    if normalized in _PUBLIC_PATHS:
        return True
    if not settings.ACCESS_TOKEN and normalized in _DOCS_PATHS:
        return True
    if normalized.startswith("/share/"):
        rest = normalized[len("/share/") :]
        return bool(rest) and "/" not in rest and rest not in {".", ".."}
    return False


def is_allowed_websocket_origin(origin: str) -> bool:
    """Allow native clients (no Origin) and loopback / configured CORS origins."""
    raw = origin.strip()
    if not raw:
        return True
    parsed = urlparse(raw)
    host = (parsed.hostname or "").strip("[]").lower()
    if host in _LOOPBACK_WS_HOSTS:
        return True
    normalized = raw.rstrip("/")
    return normalized in {item.rstrip("/") for item in settings.CORS_ORIGINS}


def sanitized_child_env(extra: dict[str, str] | None = None) -> dict[str, str]:
    """Copy the process environment without backend tokens or similar secrets."""
    env = {key: value for key, value in os.environ.items() if isinstance(value, str)}
    for key in list(env):
        if key in _ENV_KEEP:
            continue
        upper = key.upper()
        if any(marker in upper for marker in _SENSITIVE_ENV_MARKERS):
            env.pop(key, None)
    if extra:
        env.update(extra)
    return env


def _is_blocked_ip(ip: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    return any(ip in network for network in _BLOCKED_IP_NETWORKS)


def assert_safe_outbound_url(url: str) -> None:
    """Reject non-HTTP(S) URLs and cloud-metadata / link-local targets."""
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        raise ValueError("URL must use http or https")
    host = (parsed.hostname or "").strip("[]").lower()
    if not host:
        raise ValueError("URL is missing a host")
    if host in _BLOCKED_METADATA_HOSTS:
        raise ValueError("URL host is not allowed")
    try:
        literal = ipaddress.ip_address(host)
    except ValueError:
        literal = None
    if literal is not None and _is_blocked_ip(literal):
        raise ValueError("URL must not target link-local or cloud metadata addresses")

    try:
        infos = socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)
    except socket.gaierror:
        return
    for info in infos:
        address = info[4][0]
        try:
            ip = ipaddress.ip_address(address)
        except ValueError:
            continue
        if _is_blocked_ip(ip):
            raise ValueError(
                "URL must not target link-local or cloud metadata addresses"
            )


def is_allowed_preview_port(port: int) -> bool:
    if not isinstance(port, int) or port < 1024 or port > 65535:
        return False
    if port == settings.PORT or port in _BLOCKED_PREVIEW_PORTS:
        return False
    return True


def should_forward_proxy_header(name: str) -> bool:
    return name.lower() not in _SENSITIVE_PROXY_HEADERS


def hash_pin(pin: str, salt: str) -> str:
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        pin.encode("utf-8"),
        salt.encode("utf-8"),
        _PIN_PBKDF2_ROUNDS,
    )
    return digest.hex()


def pins_match(supplied: str, expected_hash: str, salt: str) -> bool:
    computed = hash_pin(supplied, salt)
    return hmac.compare_digest(computed, expected_hash)


def is_valid_pin(pin: str) -> bool:
    return bool(_PIN_PATTERN.fullmatch(pin))


class AttemptLimiter:
    def __init__(self, *, max_failures: int = 5, window_seconds: float = 300) -> None:
        self.max_failures = max_failures
        self.window_seconds = window_seconds
        self._failures: dict[str, list[float]] = {}

    def _prune(self, key: str, now: float) -> list[float]:
        stamps = [
            stamp
            for stamp in self._failures.get(key, [])
            if now - stamp < self.window_seconds
        ]
        if stamps:
            self._failures[key] = stamps
        else:
            self._failures.pop(key, None)
        return stamps

    def allowed(self, key: str) -> bool:
        return len(self._prune(key, time.monotonic())) < self.max_failures

    def record_failure(self, key: str) -> None:
        now = time.monotonic()
        stamps = self._prune(key, now)
        stamps.append(now)
        self._failures[key] = stamps

    def reset(self, key: str) -> None:
        self._failures.pop(key, None)
