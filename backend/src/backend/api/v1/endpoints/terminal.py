from fastapi import APIRouter, HTTPException, WebSocket, Query

from backend.core.security import INTERNAL_ERROR_DETAIL
from backend.schemas.terminal import TerminalRunRequest, TerminalRunResponse
from backend.services.terminal_service import terminal_service

router = APIRouter(prefix="/terminal", tags=["Terminal"])


@router.post("/run", response_model=TerminalRunResponse, summary="Run Shell Command in Project Directory")
async def run_command(req: TerminalRunRequest) -> TerminalRunResponse:
    try:
        return await terminal_service.run_command(req)
    except Exception:
        raise HTTPException(status_code=500, detail=INTERNAL_ERROR_DETAIL)


@router.websocket("/ws")
async def terminal_websocket(websocket: WebSocket, project_path: str = Query(...)):
    await terminal_service.handle_websocket(websocket, project_path)
