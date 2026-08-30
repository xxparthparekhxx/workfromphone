from fastapi import APIRouter, Query, WebSocket

from backend.schemas.system import SystemSnapshot
from backend.services.system_service import system_service

router = APIRouter(prefix="/system", tags=["System"])


@router.get(
    "/snapshot",
    response_model=SystemSnapshot,
    summary="Get a Linux system utilization snapshot",
)
async def get_system_snapshot() -> SystemSnapshot:
    return await system_service.snapshot()


@router.websocket("/ws")
async def system_websocket(
    websocket: WebSocket,
    interval: float = Query(default=2.0, ge=1.0, le=30.0),
) -> None:
    await system_service.handle_websocket(websocket, interval)
