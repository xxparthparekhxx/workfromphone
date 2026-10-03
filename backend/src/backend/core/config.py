from functools import lru_cache
from typing import List
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    APP_NAME: str = "WorkFromPhone Backend"
    APP_VERSION: str = "0.1.0"
    API_V1_PREFIX: str = "/api/v1"
    DEBUG: bool = False

    HOST: str = "127.0.0.1"
    PORT: int = 8000
    ACCESS_TOKEN: str = ""
    MAX_UPLOAD_BYTES: int = 512 * 1024 * 1024
    MAX_UPLOAD_FILES: int = 20
    MAX_UPLOAD_TOTAL_BYTES: int = 512 * 1024 * 1024
    SEARXNG_URL: str = "http://localhost:8080"
    # When True, outbound LLM/search requests may target RFC 1918 / ULA
    # addresses (LAN-local Ollama, SearXNG). Default False: only loopback and
    # public addresses pass assert_safe_outbound_url; metadata, link-local,
    # 0.0.0.0, multicast and documentation ranges are always blocked.
    ALLOW_PRIVATE_OUTBOUND: bool = False
    # Default workspace root inside constrained runtimes (Android proot,
    # containers). When set to an existing directory, filesystem browsing
    # and quick-paths default to it instead of $HOME.
    WORKSPACE: str = ""
    # Optional extra workspace roots. When WORKSPACE or any entry here points
    # at an existing directory, every project_path accepted by the fs / git /
    # terminal / harness APIs must resolve inside one of these roots.
    # Empty (default) = unconstrained, backwards compatible self-hosted mode.
    ALLOWED_ROOTS: List[str] = []
    # Guardrail / DoS caps.
    MAX_TOOL_OUTPUT_CHARS: int = 20_000
    MAX_TERMINAL_OUTPUT_BYTES: int = 1 * 1024 * 1024
    MAX_TERMINAL_TIMEOUT_SECONDS: float = 120.0
    MAX_PTYS: int = 8
    MAX_GIT_OUTPUT_BYTES: int = 2 * 1024 * 1024
    MAX_SEARCH_TIMEOUT_SECONDS: float = 60.0
    MAX_HTTP_BODY_BYTES: int = 16 * 1024 * 1024
    PREVIEW_MAX_BODY_BYTES: int = 10 * 1024 * 1024
    ARTIFACT_MAX_COUNT: int = 500
    # Per-route fixed-window rate limits (requests per minute per client IP).
    RATE_LIMIT_DEFAULT_PER_MIN: int = 300
    RATE_LIMIT_AUTH_PER_MIN: int = 30
    RATE_LIMIT_TERMINAL_PER_MIN: int = 30
    RATE_LIMIT_LLM_PER_MIN: int = 20
    RATE_LIMIT_UPLOAD_PER_MIN: int = 20
    RATE_LIMIT_PROXY_PER_MIN: int = 120

    # CORS configuration - default allows local frontend/mobile dev.
    # Never add "*" here: browsers would then let any site reach this backend.
    CORS_ORIGINS: List[str] = [
        "http://localhost",
        "http://localhost:3000",
        "http://localhost:8080",
        "http://127.0.0.1",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8080",
    ]

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
