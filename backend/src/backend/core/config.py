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
    SEARXNG_URL: str = "http://localhost:8080"

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
