import hmac

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from backend.core.config import settings


_PUBLIC_PATHS = {
    "/",
    "/docs",
    "/docs/oauth2-redirect",
    "/openapi.json",
    "/redoc",
    f"{settings.API_V1_PREFIX}/health",
}


class BearerTokenMiddleware:
    """Protect backend capabilities when ACCESS_TOKEN is configured."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        access_token = settings.ACCESS_TOKEN
        if (
            not access_token
            or scope["type"] not in {"http", "websocket"}
            or scope.get("path") in _PUBLIC_PATHS
        ):
            await self.app(scope, receive, send)
            return

        headers = {
            key.decode("latin-1").lower(): value.decode("latin-1")
            for key, value in scope.get("headers", [])
        }
        authorization = headers.get("authorization", "")
        scheme, _, supplied_token = authorization.partition(" ")
        authorized = (
            scheme.lower() == "bearer"
            and bool(supplied_token)
            and hmac.compare_digest(supplied_token, access_token)
        )
        if authorized:
            await self.app(scope, receive, send)
            return

        if scope["type"] == "websocket":
            message: Message = {
                "type": "websocket.close",
                "code": 4401,
                "reason": "Authentication required",
            }
            await send(message)
            return

        response = JSONResponse(
            {"detail": "Authentication required"},
            status_code=401,
            headers={"WWW-Authenticate": "Bearer"},
        )
        await response(scope, receive, send)
