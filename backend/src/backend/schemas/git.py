from typing import List, Optional
from pydantic import BaseModel, Field


class GitFileChange(BaseModel):
    path: str
    status: str  # 'M' (Modified), 'U' (Untracked), 'D' (Deleted), 'A' (Added), 'R' (Renamed), 'S' (Staged)
    is_staged: bool = False
    old_path: Optional[str] = None


class GitStatusResponse(BaseModel):
    is_repo: bool
    branch: Optional[str] = None
    tracking: Optional[str] = None
    ahead: int = 0
    behind: int = 0
    is_clean: bool = True
    staged: List[GitFileChange] = Field(default_factory=list)
    unstaged: List[GitFileChange] = Field(default_factory=list)
    untracked: List[GitFileChange] = Field(default_factory=list)
    last_commit_hash: Optional[str] = None
    last_commit_message: Optional[str] = None
    last_commit_author: Optional[str] = None
    last_commit_date: Optional[str] = None


class GitDiffRequest(BaseModel):
    project_path: str
    relative_path: Optional[str] = None
    staged: bool = False


class GitDiffResponse(BaseModel):
    diff: str
    path: Optional[str] = None
    staged: bool = False


class GitStageRequest(BaseModel):
    project_path: str
    paths: Optional[List[str]] = None  # None or empty = all


class GitUnstageRequest(BaseModel):
    project_path: str
    paths: Optional[List[str]] = None


class GitDiscardRequest(BaseModel):
    project_path: str
    paths: List[str]


class GitCommitRequest(BaseModel):
    project_path: str
    message: str
    stage_all: bool = False


class GitActionResult(BaseModel):
    success: bool
    message: str
    stdout: Optional[str] = None
    stderr: Optional[str] = None
