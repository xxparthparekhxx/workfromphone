from starlette.exceptions import HTTPException
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from backend.core.config import settings


class _BodyLimitExceeded(HTTPException):
    """Raised from the wrapped `receive` once the body cap is crossed.

    Subclasses ``HTTPException`` (413) so the application's own exception
    pipeline turns it into the standard ``{"detail": ...}`` JSON response —
    FastAPI would otherwise convert an unknown body-parsing exception into
    a 400 "error parsing the body".
    """

    def __init__(self) -> None:
        super().__init__(status_code=413, detail="Request body too large")


class HttpBodyLimitMiddleware:
    """Cap inbound HTTP request bodies so a multi-GB body cannot OOM us.

    Pure-ASGI middleware: it wraps the `receive` callable and counts body
    bytes as they arrive. When the limit is crossed, the request is aborted
    with a 413; memory stays bounded by the limit plus at most one receive
    chunk (the rest of the body is never buffered).

    Requests whose `Content-Length` is already over the limit are rejected
    up front, before the app runs. WebSocket upgrades are skipped entirely
    (WS messages have their own 64 KiB cap).
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        max_bytes = int(settings.MAX_HTTP_BODY_BYTES)

        headers = {
            key.decode("latin-1").lower(): value.decode("latin-1")
            for key, value in scope.get("headers", [])
        }
        content_length = headers.get("content-length")
        if content_length is not None:
            try:
                declared = int(content_length)
            except ValueError:
                declared = None
            if declared is not None and declared > max_bytes:
                response = JSONResponse({"detail": "Request body too large"}, status_code=413)
                await response(scope, receive, send)
                return

        received = 0

        async def limited_receive() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request" and message.get("body"):
                received += len(message["body"])
                if received > max_bytes:
                    raise _BodyLimitExceeded()
            return message

        await self.app(scope, limited_receive, send)
