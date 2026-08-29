from fastapi import APIRouter
from backend.api.v1.endpoints import health

api_v1_router = APIRouter()
api_v1_router.include_router(health.router)
