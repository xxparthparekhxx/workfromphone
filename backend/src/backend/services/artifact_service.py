import json
import os
import secrets
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, List, Optional

from backend.core.security import hash_pin
from backend.schemas.artifacts import (
    ArtifactMetadata,
    PublishArtifactRequest,
    PublishArtifactResponse,
)


class ArtifactService:
    def __init__(self) -> None:
        self.storage_dir = Path(
            os.getenv("WFP_STORAGE_DIR", Path.home() / ".workfromphone" / "artifacts")
        )
        self.storage_dir.mkdir(parents=True, exist_ok=True)

    def _get_artifact_path(self, token: str) -> Path:
        clean_token = "".join(c for c in token if c.isalnum() or c in "-_")
        return self.storage_dir / f"{clean_token}.json"

    def publish_artifact(self, req: PublishArtifactRequest, base_url: str = "") -> PublishArtifactResponse:
        artifact_id = f"art_{secrets.token_hex(8)}"
        token = secrets.token_urlsafe(32)
        now = datetime.now(timezone.utc)
        expires_at = (
            now + timedelta(hours=req.expires_in_hours)
            if req.expires_in_hours and req.expires_in_hours > 0
            else None
        )

        pin = req.pin_code.strip() if req.pin_code else ""
        pin_salt = secrets.token_hex(16) if pin else None
        pin_hash = hash_pin(pin, pin_salt) if pin and pin_salt else None

        data = {
            "id": artifact_id,
            "token": token,
            "title": req.title,
            "content": req.content,
            "content_type": req.content_type,
            "is_sandboxed": True,
            "pin_hash": pin_hash,
            "pin_salt": pin_salt,
            "created_at": now.isoformat(),
            "expires_at": expires_at.isoformat() if expires_at else None,
            "views_count": 0,
        }

        path = self._get_artifact_path(token)
        path.write_text(json.dumps(data, indent=2), encoding="utf-8")

        share_url = f"{base_url.rstrip('/')}/share/{token}" if base_url else f"/share/{token}"

        return PublishArtifactResponse(
            id=artifact_id,
            token=token,
            share_url=share_url,
            title=req.title,
            content_type=req.content_type,
            created_at=now,
            expires_at=expires_at,
            has_pin=bool(pin),
        )

    def _load_artifact(self, token: str) -> Optional[Dict]:
        path = self._get_artifact_path(token)
        if not path.is_file():
            return None

        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return None

        if data.get("expires_at"):
            expires_at = datetime.fromisoformat(data["expires_at"])
            if datetime.now(timezone.utc) > expires_at:
                return None
        return data

    def get_artifact(self, token: str, increment_views: bool = False) -> Optional[Dict]:
        data = self._load_artifact(token)
        if data is None:
            return None
        if increment_views:
            self.record_view(token)
            data["views_count"] = data.get("views_count", 0) + 1
        return data

    def record_view(self, token: str) -> None:
        path = self._get_artifact_path(token)
        data = self._load_artifact(token)
        if data is None:
            return
        data["views_count"] = data.get("views_count", 0) + 1
        path.write_text(json.dumps(data, indent=2), encoding="utf-8")

    def list_artifacts(self) -> List[ArtifactMetadata]:
        results: List[ArtifactMetadata] = []
        now = datetime.now(timezone.utc)

        for file in self.storage_dir.glob("*.json"):
            try:
                data = json.loads(file.read_text(encoding="utf-8"))
                expires_at = (
                    datetime.fromisoformat(data["expires_at"])
                    if data.get("expires_at")
                    else None
                )
                if expires_at and now > expires_at:
                    continue

                results.append(
                    ArtifactMetadata(
                        id=data["id"],
                        token=data["token"],
                        title=data["title"],
                        content_type=data["content_type"],
                        created_at=datetime.fromisoformat(data["created_at"]),
                        expires_at=expires_at,
                        has_pin=bool(data.get("pin_hash") or data.get("pin_code")),
                        views_count=data.get("views_count", 0),
                    )
                )
            except Exception:
                continue

        results.sort(key=lambda a: a.created_at, reverse=True)
        return results

    def delete_artifact(self, token: str) -> bool:
        path = self._get_artifact_path(token)
        if path.is_file():
            path.unlink()
            return True
        return False


artifact_service = ArtifactService()
