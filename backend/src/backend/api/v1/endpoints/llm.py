import json
from pathlib import Path
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse

from backend.schemas.llm import (
    ChatTaskRequest,
    FetchModelsRequest,
    FetchModelsResponse,
)
from backend.services.harness_service import harness_service

router = APIRouter(prefix="/llm", tags=["LLM & Harness"])


@router.post("/models", response_model=FetchModelsResponse, summary="Fetch Models from Router")
async def get_models(req: FetchModelsRequest) -> FetchModelsResponse:
    """
    Fetches available models from OpenRouter or custom OpenAI-compatible router.
    Falls back gracefully to curated models list if router endpoint is restricted or offline.
    """
    return await harness_service.fetch_models(req)


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
