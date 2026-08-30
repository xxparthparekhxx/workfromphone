import asyncio
from typing import Optional

import httpx
from fastapi import APIRouter, HTTPException, Request, WebSocket
from fastapi.responses import Response

from backend.schemas.preview import (
    PreviewListResponse,
    PreviewRegisterRequest,
    PreviewUnregisterRequest,
)
from backend.services.preview_service import preview_registry


router = APIRouter(prefix="/preview", tags=["Preview"])


@router.get("", response_model=PreviewListResponse)
async def list_previews(project_path: str) -> PreviewListResponse:
    return PreviewListResponse(
        entries=preview_registry.list_for_project(project_path),
    )


@router.post("/register", response_model=None)
async def register_preview(req: PreviewRegisterRequest):
    entry = await preview_registry.register(
        project_path=req.project_path,
        port=req.port,
        label=req.label,
        base_path=req.base_path,
        source=req.source,
        entry_id=req.id,
    )
    return {"entry": entry}


@router.post("/unregister")
async def unregister_preview(req: PreviewUnregisterRequest):
    removed = await preview_registry.unregister(req.id)
    if not removed:
        raise HTTPException(status_code=404, detail="Preview not found")
    return {"unregistered": req.id}


@router.delete("/{entry_id}")
async def unregister_preview_by_id(entry_id: str):
    removed = await preview_registry.unregister(entry_id)
    if not removed:
        raise HTTPException(status_code=404, detail="Preview not found")
    return {"unregistered": entry_id}


@router.websocket("/ws")
async def preview_websocket(websocket: WebSocket) -> None:
    await preview_registry.handle_websocket(websocket)


# ---------------------------------------------------------------------------
# Reverse proxy with SPA fallback.
# ---------------------------------------------------------------------------
#
# A registered preview target exposes its dev server on a loopback port on
# the host running the backend. The mobile client cannot reach that port
# directly (different host, loopback-only, possibly behind NAT/SSH), so we
# proxy all requests through the backend's loopback address and add a
# single fallback: if the upstream answers 404 for a path that does not
# look like a static asset (no "." in the last URL segment), we re-issue
# the request for "/" so SPAs like Vite/React/Flutter-web can answer
# client-side routes via their own router.

_HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "content-length",
    "host",
}


def _filter_response_headers(headers) -> dict[str, str]:
    pairs: dict[str, str] = {}
    for key, value in headers.items():
        if key.lower() in _HOP_BY_HOP_HEADERS:
            continue
        pairs[key] = value
    return pairs


def _looks_like_asset(path: str) -> bool:
    last = path.rsplit("/", 1)[-1]
    if not last:
        return False
    return "." in last


@router.api_route(
    "/proxy/{entry_id}/{path:path}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"],
    summary="Reverse-proxy a registered preview target with SPA fallback.",
)
async def proxy_preview(
    entry_id: str,
    path: str,
    request: Request,
) -> Response:
    entry = preview_registry.get(entry_id)
    if entry is None:
        raise HTTPException(status_code=404, detail="Preview not found")

    forwarded_path = f"/{path}" if path else "/"
    base_prefix = entry.base_path or ""
    if base_prefix and not forwarded_path.startswith(base_prefix):
        upstream_path = base_prefix.rstrip("/") + forwarded_path
    else:
        upstream_path = forwarded_path

    async with httpx.AsyncClient(timeout=httpx.Timeout(20.0)) as client:
        response = await _issue(client, request, entry.port, upstream_path)

        if (
            response.status_code == 404
            and request.method.upper() == "GET"
            and not _looks_like_asset(upstream_path)
        ):
            fallback_path = base_prefix or "/"
            response = await _issue(client, request, entry.port, fallback_path)

    return Response(
        content=response.content,
        status_code=response.status_code,
        headers=_filter_response_headers(response.headers),
        media_type=response.headers.get("content-type"),
    )


async def _issue(
    client: httpx.AsyncClient,
    request: Request,
    port: int,
    upstream_path: str,
) -> httpx.Response:
    body = await request.body()
    headers = {
        key: value
        for key, value in request.headers.items()
        if key.lower() not in _HOP_BY_HOP_HEADERS
    }
    upstream_url = f"http://127.0.0.1:{port}{upstream_path}"
    try:
        return await client.request(
            request.method,
            upstream_url,
            params=request.query_params,
            headers=headers,
            content=body,
        )
    except httpx.RequestError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Upstream preview server on port {port} is unreachable: {exc}",
        )