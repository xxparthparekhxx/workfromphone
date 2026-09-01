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


class WriteFileRequest(BaseModel):
    project_path: str
    relative_path: str
    content: str = Field(..., max_length=8 * 1024 * 1024)


class CreateItemRequest(BaseModel):
    project_path: str
    relative_path: str
    is_dir: bool = False


class DeleteItemRequest(BaseModel):
    project_path: str
    relative_path: str


class FileActionResponse(BaseModel):
    success: bool
    message: str
    path: str
    size_bytes: Optional[int] = None


class UploadFilesResponse(BaseModel):
    success: bool
    files: List[FileActionResponse]


class ProjectFilesResponse(BaseModel):
    files: List[str]
    truncated: bool = False
