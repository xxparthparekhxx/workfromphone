from fastapi import APIRouter
from backend.api.v1.endpoints import fs, health, llm

api_v1_router = APIRouter()
api_v1_router.include_router(health.router)
api_v1_router.include_router(fs.router)
api_v1_router.include_router(llm.router)
