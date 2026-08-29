from pathlib import Path
from typing import Optional
from fastapi import APIRouter, HTTPException, Query

from backend.schemas.fs import (
    BrowseResponse,
    QuickPathsResponse,
    ValidatePathRequest,
    ValidatePathResponse,
)
from backend.services.fs_service import fs_service

router = APIRouter(prefix="/fs", tags=["FileSystem"])


@router.get("/browse", response_model=BrowseResponse, summary="Browse Directory")
async def browse(
    path: Optional[str] = Query(None, description="Directory path to browse")
) -> BrowseResponse:
    return fs_service.browse(path)


@router.post("/validate", response_model=ValidatePathResponse, summary="Validate Directory Path")
async def validate_path(req: ValidatePathRequest) -> ValidatePathResponse:
    return fs_service.validate_path(req.path)


@router.get("/quick-paths", response_model=QuickPathsResponse, summary="Get Quick Access Project Folders")
async def get_quick_paths() -> QuickPathsResponse:
    return fs_service.get_quick_paths()


@router.get("/file", summary="Read File Content")
async def read_file(
    project_path: str = Query(..., description="Project root path"),
    relative_path: str = Query(..., description="File relative path"),
    start_line: Optional[int] = Query(None),
    end_line: Optional[int] = Query(None),
):
    try:
        p_root = Path(project_path).resolve()
        target = (p_root / relative_path).resolve()
        target.relative_to(p_root)

        if not target.exists() or not target.is_file():
            raise HTTPException(status_code=404, detail="File not found")

        with open(target, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()

        if start_line is not None or end_line is not None:
            s = max(1, start_line or 1)
            e = min(len(lines), end_line or len(lines))
            content = "".join(lines[s - 1 : e])
        else:
            content = "".join(lines)

        return {
            "path": relative_path,
            "total_lines": len(lines),
            "content": content,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid path traversal")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
