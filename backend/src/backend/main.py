from contextlib import asynccontextmanager
import contextlib
import html
import hmac
import ipaddress
import uvicorn
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, PlainTextResponse

from backend.api.v1.router import api_v1_router
from backend.core.auth import BearerTokenMiddleware
from backend.core.config import settings
from backend.core.middleware import HttpBodyLimitMiddleware
from backend.core.security import AttemptLimiter, pins_match
from backend.services.artifact_service import artifact_service

_pin_limiter = AttemptLimiter(max_failures=5, window_seconds=300)


def is_loopback_host(host: str) -> bool:
    """Report whether binding to `host` keeps the backend off the network."""
    normalized = host.strip().strip("[]").lower()
    if normalized == "localhost":
        return True
    try:
        return ipaddress.ip_address(normalized).is_loopback
    except ValueError:
        return False


def resolve_cors_origins() -> list[str]:
    """Drop wildcard origins so no arbitrary site can reach this backend."""
    return [origin for origin in settings.CORS_ORIGINS if origin.strip() != "*"]


def verify_network_exposure() -> None:
    """Refuse to serve a non-loopback interface without bearer authentication."""
    if settings.ACCESS_TOKEN or is_loopback_host(settings.HOST):
        return
    raise RuntimeError(
        f"Refusing to bind {settings.HOST} without ACCESS_TOKEN set: every "
        "capability route, including terminal command execution, would be "
        "reachable unauthenticated. Set ACCESS_TOKEN or bind 127.0.0.1.",
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    print(f"🚀 Starting {settings.APP_NAME} v{settings.APP_VERSION}")
    if not settings.ACCESS_TOKEN:
        print(
            "⚠️  ACCESS_TOKEN is not set: every capability route (files, git, "
            "terminal, LLM) accepts any local connection. This is only safe "
            "while bound to loopback with no port forwarding (no `ssh -R`, no "
            "Cloudflare Tunnel pointing at it). Set ACCESS_TOKEN for any "
            "forwarded or shared setup."
        )
    if workspace_roots_snapshot():
        print(f"📁 Workspace allowlist: {', '.join(workspace_roots_snapshot())}")
    yield
    print(f"🛑 Shutting down {settings.APP_NAME}")
    with contextlib.suppress(Exception):
        from backend.api.v1.endpoints import preview as _preview_ep

        client = _preview_ep._shared_preview_client
        if client is not None:
            await client.aclose()
        _preview_ep._shared_preview_client = None


def workspace_roots_snapshot() -> list[str]:
    try:
        from backend.core.security import workspace_roots

        return workspace_roots()
    except Exception:
        return []


class RateLimitMiddleware:
    """Fixed-window per-IP rate limits (brute-force / DoS backstop).

    Buckets are deliberately generous so normal single-user operation never
    trips them; they exist to blunt bearer-token brute force, terminal/run
    abuse, LLM loop spam, upload floods and proxy hammering.
    """

    def __init__(self, app) -> None:
        from backend.core.security import RateLimiter as _RL

        self.app = app
        self._limiters = {
            "default": _RL(limit=settings.RATE_LIMIT_DEFAULT_PER_MIN, window_seconds=60.0),
            "terminal": _RL(limit=settings.RATE_LIMIT_TERMINAL_PER_MIN, window_seconds=60.0),
            "llm": _RL(limit=settings.RATE_LIMIT_LLM_PER_MIN, window_seconds=60.0),
            "upload": _RL(limit=settings.RATE_LIMIT_UPLOAD_PER_MIN, window_seconds=60.0),
            "proxy": _RL(limit=settings.RATE_LIMIT_PROXY_PER_MIN, window_seconds=60.0),
        }

    def _bucket(self, path: str) -> str:
        if path.startswith(f"{settings.API_V1_PREFIX}/terminal/"):
            return "terminal"
        if path.startswith(f"{settings.API_V1_PREFIX}/llm/"):
            return "llm"
        if path.startswith(f"{settings.API_V1_PREFIX}/fs/upload"):
            return "upload"
        if path.startswith(f"{settings.API_V1_PREFIX}/preview/proxy/"):
            return "proxy"
        return "default"

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] not in {"http", "websocket"}:
            await self.app(scope, receive, send)
            return
        path = scope.get("path", "")
        bucket = self._bucket(path)
        client = scope.get("client")
        ip = client[0] if isinstance(client, (list, tuple)) and client else "unknown"
        if not self._limiters[bucket].allowed(f"{ip}:{bucket}"):
            if scope["type"] == "websocket":
                await send({"type": "websocket.close", "code": 4429, "reason": "Rate limit exceeded"})
                return
            from starlette.responses import JSONResponse as _JSON

            response = _JSON({"detail": "Rate limit exceeded. Try again later."}, status_code=429)
            await response(scope, receive, send)
            return
        await self.app(scope, receive, send)


def create_app() -> FastAPI:
    verify_network_exposure()

    token_configured = bool(settings.ACCESS_TOKEN)
    application = FastAPI(
        title=settings.APP_NAME,
        version=settings.APP_VERSION,
        description="FastAPI Backend Server for WorkFromPhone",
        lifespan=lifespan,
        docs_url=None if token_configured else "/docs",
        redoc_url=None if token_configured else "/redoc",
        openapi_url=None if token_configured else "/openapi.json",
    )

    # Added first => innermost user middleware: an unauthenticated oversized
    # request still gets the auth 401, and an authenticated one gets the 413.
    application.add_middleware(HttpBodyLimitMiddleware)
    application.add_middleware(BearerTokenMiddleware)
    application.add_middleware(RateLimitMiddleware)

    # Configure CORS
    application.add_middleware(
        CORSMiddleware,
        allow_origins=resolve_cors_origins(),
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Strict Global Robots.txt to prevent search engine indexing
    @application.get("/robots.txt", tags=["SEO"])
    async def robots_txt():
        return PlainTextResponse(
            "User-agent: *\nDisallow: /\n",
            headers={
                "X-Robots-Tag": "noindex, nofollow, noarchive, nosnippet",
                "Cache-Control": "public, max-age=86400",
            },
        )

    # Root route
    @application.get("/", tags=["Root"])
    async def root():
        payload = {
            "message": f"Welcome to {settings.APP_NAME} API",
            "version": settings.APP_VERSION,
            "health": f"{settings.API_V1_PREFIX}/health",
        }
        if not settings.ACCESS_TOKEN:
            payload["docs"] = "/docs"
        return payload

    def _artifact_not_found() -> HTMLResponse:
        return HTMLResponse(
            """<!DOCTYPE html>
            <html><head><title>Artifact Not Found</title>
            <meta name="robots" content="noindex, nofollow">
            <style>body{font-family:sans-serif;background:#0f111a;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;}
            .box{background:#1a1b26;padding:32px;border-radius:12px;border:1px solid #333;text-align:center;max-width:400px;}
            h2{color:#f7768e;margin-top:0;}</style></head>
            <body><div class="box"><h2>404 - Artifact Expired or Not Found</h2><p>This shared artifact does not exist or has expired.</p></div></body></html>""",
            status_code=404,
            headers={"X-Robots-Tag": "noindex, nofollow, noarchive, nosnippet"},
        )

    def _pin_form(artifact: dict, *, locked_out: bool = False) -> HTMLResponse:
        title_escaped = html.escape(artifact.get("title", "Protected Artifact"))
        message = (
            "Too many unlock attempts. Try again later."
            if locked_out
            else "Enter the PIN to view this artifact."
        )
        return HTMLResponse(
            f"""<!DOCTYPE html>
            <html><head><title>Protected Artifact</title>
            <meta name="robots" content="noindex, nofollow">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>body{{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#0f111a;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;}}
            .card{{background:#1a1b26;padding:32px;border-radius:14px;border:1px solid #282e44;width:90%;max-width:380px;text-align:center;box-shadow:0 10px 30px rgba(0,0,0,0.5);}}
            input{{width:100%;box-sizing:border-box;padding:12px;margin:16px 0;background:#24283b;border:1px solid #414868;color:#fff;border-radius:8px;font-size:16px;text-align:center;letter-spacing:4px;}}
            button{{width:100%;padding:12px;background:#7aa2f7;border:none;color:#1a1b26;border-radius:8px;font-weight:bold;font-size:15px;cursor:pointer;}}</style></head>
            <body><div class="card"><h3>Protected Artifact</h3><p style="color:#a9b1d6;font-size:14px;">{title_escaped}</p>
            <p style="color:#a9b1d6;font-size:13px;">{html.escape(message)}</p>
            <form method="POST" action=""><label class="sr-only" for="pin">PIN code</label><input id="pin" type="password" name="pin" inputmode="numeric" autocomplete="off" placeholder="Enter PIN" aria-label="Artifact PIN code" autofocus required />
            <button type="submit">Unlock & View</button></form></div></body></html>""",
            headers={"X-Robots-Tag": "noindex, nofollow, noarchive, nosnippet"},
        )

    def _artifact_unlocked(artifact: dict) -> Response:
        headers = {
            "X-Robots-Tag": "noindex, nofollow, noarchive, nosnippet, noimageindex",
            "Cache-Control": "private, no-cache, no-store, must-revalidate",
            "Pragma": "no-cache",
            "X-Content-Type-Options": "nosniff",
            "Content-Security-Policy": (
                "sandbox allow-scripts; "
                "frame-ancestors 'none'; "
                "default-src 'none'; "
                "script-src 'unsafe-inline'; "
                "style-src 'unsafe-inline'; "
                "img-src data: https:; "
                "font-src data:;"
            ),
        }
        return Response(
            content=artifact["content"],
            media_type=artifact["content_type"],
            headers=headers,
        )

    def _pin_is_valid(artifact: dict, supplied: str) -> bool:
        pin_hash = artifact.get("pin_hash")
        pin_salt = artifact.get("pin_salt")
        if pin_hash and pin_salt:
            return pins_match(supplied, pin_hash, pin_salt)
        legacy = artifact.get("pin_code")
        if legacy:
            return hmac.compare_digest(supplied, str(legacy))
        return True

    async def _view_shared_artifact(token: str, request: Request, pin: str) -> Response:
        artifact = artifact_service.get_artifact(token, increment_views=False)
        if not artifact:
            return _artifact_not_found()

        # Key the PIN limiter by token alone (not token:IP): per-IP keys let an
        # attacker rotate source addresses to bypass the 5-attempt window.
        limit_key = f"pin:{token}"
        requires_pin = bool(
            artifact.get("pin_hash") or artifact.get("pin_code")
        )
        if requires_pin:
            if not _pin_limiter.allowed(limit_key):
                return _pin_form(artifact, locked_out=True)
            if not pin or not _pin_is_valid(artifact, pin):
                if pin:
                    _pin_limiter.record_failure(limit_key)
                return _pin_form(artifact)
            _pin_limiter.reset(limit_key)

        artifact_service.record_view(token)
        return _artifact_unlocked(artifact)

    @application.get("/share/{token}", tags=["Public Artifacts"])
    async def view_shared_artifact(token: str, request: Request):
        return await _view_shared_artifact(token, request, "")

    @application.post("/share/{token}", tags=["Public Artifacts"])
    async def unlock_shared_artifact(token: str, request: Request):
        form = await request.form()
        pin = str(form.get("pin") or "").strip()
        return await _view_shared_artifact(token, request, pin)

    # Include API Routers
    application.include_router(api_v1_router, prefix=settings.API_V1_PREFIX)

    return application


app = create_app()


def start() -> None:
    uvicorn.run(
        "backend.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
    )


if __name__ == "__main__":
    start()
