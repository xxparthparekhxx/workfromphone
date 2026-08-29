from contextlib import asynccontextmanager
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from backend.api.v1.router import api_v1_router
from backend.core.config import settings


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup logic
    print(f"🚀 Starting {settings.APP_NAME} v{settings.APP_VERSION}")
    yield
    # Shutdown logic
    print(f"🛑 Shutting down {settings.APP_NAME}")


def create_app() -> FastAPI:
    application = FastAPI(
        title=settings.APP_NAME,
        version=settings.APP_VERSION,
        description="FastAPI Backend Server for WorkFromPhone",
        lifespan=lifespan,
    )

    # Configure CORS
    application.add_middleware(
        CORSMiddleware,
        allow_origins=settings.CORS_ORIGINS,
        allow_credentials=True,
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
        reload=True,
    )


if __name__ == "__main__":
    start()
