from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator


_ALLOWED_CONTENT_TYPES = {
    "text/html",
    "text/plain",
    "text/markdown",
    "image/svg+xml",
}


class PublishArtifactRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=200, description="Title of the artifact")
    content: str = Field(..., max_length=2_000_000, description="HTML, SVG, Markdown, or code content")
    content_type: str = Field("text/html", description="MIME type (text/html, text/markdown, image/svg+xml, text/plain)")
    is_sandboxed: bool = Field(True, description="Always enforced; artifacts are served with a sandbox CSP")
    expires_in_hours: Optional[int] = Field(None, ge=1, le=24 * 30, description="Optional lifetime in hours")
    pin_code: Optional[str] = Field(None, description="Optional 4-8 digit access PIN code")

    @field_validator("content_type")
    @classmethod
    def validate_content_type(cls, value: str) -> str:
        normalized = value.split(";", 1)[0].strip().lower()
        if normalized not in _ALLOWED_CONTENT_TYPES:
            raise ValueError("Unsupported artifact content type")
        return normalized

    @field_validator("pin_code")
    @classmethod
    def validate_pin(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        pin = value.strip()
        if not pin:
            return None
        if not pin.isdigit() or not (4 <= len(pin) <= 8):
            raise ValueError("PIN must be 4 to 8 digits")
        return pin


class PublishArtifactResponse(BaseModel):
    id: str
    token: str
    share_url: str
    title: str
    content_type: str
    created_at: datetime
    expires_at: Optional[datetime] = None
    has_pin: bool = False


class ArtifactMetadata(BaseModel):
    id: str
    token: str
    title: str
    content_type: str
    created_at: datetime
    expires_at: Optional[datetime] = None
    has_pin: bool = False
    views_count: int = 0
