from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


class PreviewEntry(BaseModel):
    id: str = Field(description="Stable identifier for the registered preview target.")
    project_path: str = Field(
        description="Absolute path of the project the preview belongs to.",
    )
    port: int = Field(
        ge=1,
        le=65535,
        description="Loopback TCP port the dev/preview server is listening on.",
    )
    label: str = Field(
        description="Human-readable label, e.g. 'Vite dev server'.",
    )
    base_path: str = Field(
        default="",
        description=(
            "Optional URL prefix the upstream serves the app under "
            "(e.g. '/my-app/'). Empty string means root."
        ),
    )
    registered_at: datetime = Field(
        description="When this entry was registered.",
    )
    source: str = Field(
        description="How the entry was registered: 'llm' or 'manual'.",
    )


class PreviewListResponse(BaseModel):
    entries: List[PreviewEntry]


class PreviewRegisterRequest(BaseModel):
    project_path: str
    port: int = Field(ge=1, le=65535)
    label: str = Field(min_length=1, max_length=120)
    base_path: str = Field(default="")
    source: str = Field(default="manual")
    id: Optional[str] = Field(
        default=None,
        description=(
            "Optional explicit identifier. When omitted, a stable id is "
            "derived from project_path + port."
        ),
    )


class PreviewUnregisterRequest(BaseModel):
    id: str