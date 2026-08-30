from typing import Optional
from pydantic import BaseModel, Field


class TerminalRunRequest(BaseModel):
    project_path: str = Field(description="Project root directory where command executes")
    command: str = Field(description="Shell command line to execute")
    timeout_seconds: float = Field(default=60.0, ge=1.0, le=300.0)


class TerminalRunResponse(BaseModel):
    command: str
    exit_code: int
    stdout: str
    stderr: str
    duration_ms: int
    timed_out: bool = False
