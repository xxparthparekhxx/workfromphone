from typing import List, Optional
from pydantic import BaseModel, Field


class DirectoryItem(BaseModel):
    name: str
    path: str
    is_dir: bool
    is_project: bool = False
    project_type: Optional[str] = None  # e.g., "flutter", "python", "node", "rust", "go", "git", "generic"
    size_bytes: Optional[int] = None
    modified_at: Optional[str] = None


class BrowseResponse(BaseModel):
    current_path: str
    parent_path: Optional[str] = None
    home_path: str
    items: List[DirectoryItem]
    is_project: bool = False
    project_type: Optional[str] = None


class ValidatePathRequest(BaseModel):
    path: str


class ValidatePathResponse(BaseModel):
    valid: bool
    path: str
    is_dir: bool = False
    exists: bool = False
    is_project: bool = False
    project_type: Optional[str] = None
    message: Optional[str] = None


class QuickPathsResponse(BaseModel):
    home: str
    current_workspace: str
    common_paths: List[DirectoryItem]
