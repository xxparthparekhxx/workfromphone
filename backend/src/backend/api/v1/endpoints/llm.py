import json

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse

from backend.schemas.llm import (
    ChatTaskRequest,
    FetchModelsRequest,
    FetchModelsResponse,
    GeneralChatRequest,
)
from backend.services.harness_service import harness_service

router = APIRouter(prefix="/llm", tags=["LLM & Harness"])


@router.post("/models", response_model=FetchModelsResponse, summary="Fetch Models from Router")
async def get_models(req: FetchModelsRequest) -> FetchModelsResponse:
    """Fetch available models from OpenRouter or an OpenAI-compatible router."""
    try:
        return await harness_service.fetch_models(req)
    except ValueError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@router.post("/chat", summary="Run Agentic Task (SSE Stream)")
async def chat_task_stream(req: ChatTaskRequest):
    """
    Executes an autonomous agentic task against the project directory.
    Streams progress, reasoning, tool execution, and responses via SSE.
    """
    return StreamingResponse(
        harness_service.run_agentic_task_stream(req),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.post("/general", summary="Run General Chat (SSE Stream)")
async def general_chat_stream(req: GeneralChatRequest):
    """
    Streams a non-agentic chat completion against OpenRouter or an
    OpenAI-compatible endpoint. Used by the on-device general assistant.
    """
    return StreamingResponse(
        harness_service.run_general_chat_stream(req),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.websocket("/ws")
async def chat_task_ws(websocket: WebSocket):
    """
    WebSocket endpoint for bidirectional interactive task streaming and control.
    """
    await websocket.accept()
    try:
        while True:
            data_text = await websocket.receive_text()
            try:
                data = json.loads(data_text)
                req = ChatTaskRequest(**data)

                # Stream task events to websocket
                async for sse_line in harness_service.run_agentic_task_stream(req):
                    if sse_line.startswith("data:"):
                        payload = sse_line[5:].strip()
                        await websocket.send_text(payload)

            except Exception as e:
                await websocket.send_text(
                    json.dumps({"type": "error", "message": f"Processing error: {str(e)}"})
                )
    except WebSocketDisconnect:
        pass
