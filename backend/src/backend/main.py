from contextlib import asynccontextmanager
import ipaddress
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from backend.api.v1.router import api_v1_router
from backend.core.auth import BearerTokenMiddleware
from backend.core.config import settings


def is_loopback_host(host: str) -> bool:
    """Report whether binding to `host` keeps the backend off the network."""
    normalized = host.strip().strip("[]").lower()
    if normalized == "localhost":
        return True
    try:
        return ipaddress.ip_address(normalized).is_loopback
    except ValueError:
        return False


def resolve_cors_origins() -> list[str]:
    """Drop wildcard origins so no arbitrary site can reach this backend."""
    return [origin for origin in settings.CORS_ORIGINS if origin.strip() != "*"]


def verify_network_exposure() -> None:
    """Refuse to serve a non-loopback interface without bearer authentication."""
    if settings.ACCESS_TOKEN or is_loopback_host(settings.HOST):
        return
    raise RuntimeError(
        f"Refusing to bind {settings.HOST} without ACCESS_TOKEN set: every "
        "capability route, including terminal command execution, would be "
        "reachable unauthenticated. Set ACCESS_TOKEN or bind 127.0.0.1.",
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup logic
    print(f"🚀 Starting {settings.APP_NAME} v{settings.APP_VERSION}")
    yield
    # Shutdown logic
    print(f"🛑 Shutting down {settings.APP_NAME}")


def create_app() -> FastAPI:
    verify_network_exposure()

    application = FastAPI(
        title=settings.APP_NAME,
        version=settings.APP_VERSION,
        description="FastAPI Backend Server for WorkFromPhone",
        lifespan=lifespan,
    )

    application.add_middleware(BearerTokenMiddleware)

    # Configure CORS
    application.add_middleware(
        CORSMiddleware,
        allow_origins=resolve_cors_origins(),
        # The client authenticates with an explicit bearer header, never with
        # cookies, so credentialed cross-origin requests are never needed.
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Root route
    @application.get("/", tags=["Root"])
    async def root():
        return {
            "message": f"Welcome to {settings.APP_NAME} API",
            "version": settings.APP_VERSION,
            "docs": "/docs",
            "health": f"{settings.API_V1_PREFIX}/health",
        }

    # Include API Routers
    application.include_router(api_v1_router, prefix=settings.API_V1_PREFIX)

    return application


app = create_app()


def start() -> None:
    """Entrypoint for CLI command `uv run backend` or `backend` script."""
    uvicorn.run(
        "backend.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
    )


if __name__ == "__main__":
    start()
