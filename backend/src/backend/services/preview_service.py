import asyncio
import hashlib
import json
from datetime import datetime, timezone
from typing import Optional

from fastapi import WebSocket, WebSocketDisconnect

from backend.schemas.preview import PreviewEntry


def _make_id(project_path: str, port: int, explicit: Optional[str]) -> str:
    if explicit:
        return explicit
    digest = hashlib.sha1(f"{project_path}:{port}".encode("utf-8")).hexdigest()[:12]
    return f"prev_{port}_{digest}"


class PreviewRegistry:
    """In-memory registry of preview targets per project.

    Entries are added either by the LLM harness (via the ``register_preview``
    tool when it starts a dev server) or by a user-issued request (manual
    register). A websocket fan-out broadcasts every change so the Flutter
    client can refresh its preview tab immediately.
    """

    def __init__(self) -> None:
        self._entries: dict[str, PreviewEntry] = {}
        self._listeners: set[WebSocket] = set()
        self._lock = asyncio.Lock()

    @staticmethod
    def _now() -> datetime:
        return datetime.now(timezone.utc)

    @staticmethod
    def _normalize_base_path(base_path: str) -> str:
        normalized = "/" + base_path.strip().strip("/") if base_path.strip() else ""
        if normalized == "/":
            return ""
        return normalized + "/"

    @staticmethod
    def _normalize_source(source: str) -> str:
        lowered = source.strip().lower()
        return lowered if lowered in {"llm", "manual"} else "manual"

    async def register(
        self,
        *,
        project_path: str,
        port: int,
        label: str,
        base_path: str = "",
        source: str = "manual",
        entry_id: Optional[str] = None,
    ) -> PreviewEntry:
        resolved_id = _make_id(project_path, port, entry_id)
        entry = PreviewEntry(
            id=resolved_id,
            project_path=project_path,
            port=port,
            label=label.strip()[:120] or f"Port {port}",
            base_path=self._normalize_base_path(base_path),
            registered_at=self._now(),
            source=self._normalize_source(source),
        )
        async with self._lock:
            self._entries[resolved_id] = entry
        await self._broadcast(entry, event="registered")
        return entry

    async def unregister(self, entry_id: str) -> bool:
        async with self._lock:
            entry = self._entries.pop(entry_id, None)
        if entry is None:
            return False
        await self._broadcast(entry, event="unregistered")
        return True

    async def clear_project(self, project_path: str) -> int:
        async with self._lock:
            victims = [key for key, entry in self._entries.items() if entry.project_path == project_path]
            for key in victims:
                self._entries.pop(key, None)
        return len(victims)

    def list_for_project(self, project_path: str) -> list[PreviewEntry]:
        return [
            entry
            for entry in self._entries.values()
            if entry.project_path == project_path
        ]

    def get(self, entry_id: str) -> Optional[PreviewEntry]:
        return self._entries.get(entry_id)

    async def attach(self, websocket: WebSocket) -> None:
        async with self._lock:
            self._listeners.add(websocket)
            snapshot = list(self._entries.values())

        await websocket.send_json(
            {
                "type": "snapshot",
                "entries": [entry.model_dump(mode="json") for entry in snapshot],
            }
        )

    async def detach(self, websocket: WebSocket) -> None:
        async with self._lock:
            self._listeners.discard(websocket)

    async def _broadcast(self, entry: PreviewEntry, *, event: str) -> None:
        async with self._lock:
            listeners = list(self._listeners)
        if not listeners:
            return

        message = json.dumps(
            {"type": event, "entry": entry.model_dump(mode="json")},
            default=str,
        )
        stale: list[WebSocket] = []
        for listener in listeners:
            try:
                await listener.send_text(message)
            except (RuntimeError, WebSocketDisconnect):
                stale.append(listener)
        if stale:
            async with self._lock:
                for listener in stale:
                    self._listeners.discard(listener)

    async def handle_websocket(self, websocket: WebSocket) -> None:
        await websocket.accept()
        await self.attach(websocket)
        try:
            while True:
                await websocket.receive_text()
        except WebSocketDisconnect:
            return
        finally:
            await self.detach(websocket)


preview_registry = PreviewRegistry()