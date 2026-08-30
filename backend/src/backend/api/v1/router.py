from fastapi import APIRouter
from backend.api.v1.endpoints import fs, git, health, llm, preview, system, terminal

api_v1_router = APIRouter()
api_v1_router.include_router(health.router)
api_v1_router.include_router(fs.router)
api_v1_router.include_router(llm.router)
api_v1_router.include_router(git.router)
api_v1_router.include_router(terminal.router)
api_v1_router.include_router(system.router)
api_v1_router.include_router(preview.router)
