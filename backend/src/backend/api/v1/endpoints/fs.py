import os
import shutil
from pathlib import Path
from typing import Optional
from uuid import uuid4

from fastapi import APIRouter, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse

from backend.core.config import settings
from backend.schemas.fs import (
    BrowseResponse,
    CreateItemRequest,
    DeleteItemRequest,
    FileActionResponse,
    ProjectFilesResponse,
    QuickPathsResponse,
    UploadFilesResponse,
    ValidatePathRequest,
    ValidatePathResponse,
    WriteFileRequest,
)
from backend.services.fs_service import fs_service

router = APIRouter(prefix="/fs", tags=["FileSystem"])


def _resolve_project_target(project_path: str, relative_path: str) -> tuple[Path, Path]:
    project_root = Path(os.path.expanduser(project_path)).resolve()
    target = (project_root / relative_path).resolve()
    try:
        target.relative_to(project_root)
    except ValueError as error:
        raise HTTPException(
            status_code=400,
            detail="Invalid path traversal outside project root",
        ) from error
    return project_root, target


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


@router.get(
    "/project-files",
    response_model=ProjectFilesResponse,
    summary="List Project Files for Composer Mentions",
)
async def list_project_files(
    project_path: str = Query(..., description="Project root path"),
    limit: int = Query(default=5000, ge=1, le=5000),
) -> ProjectFilesResponse:
    try:
        return fs_service.list_project_files(project_path, limit)
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error


@router.get("/file", summary="Read File Content")
async def read_file(
    project_path: str = Query(..., description="Project root path"),
    relative_path: str = Query(..., description="File relative path"),
    start_line: Optional[int] = Query(None),
    end_line: Optional[int] = Query(None),
):
    try:
        p_root = Path(os.path.expanduser(project_path)).resolve()
        target = (p_root / relative_path).resolve()
        target.relative_to(p_root)

        if not target.exists() or not target.is_file():
            raise HTTPException(status_code=404, detail=f"File '{relative_path}' not found")

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
        raise HTTPException(status_code=400, detail="Invalid path traversal outside project root")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/file", response_model=FileActionResponse, summary="Save/Write File Content")
async def write_file(req: WriteFileRequest) -> FileActionResponse:
    try:
        p_root = Path(os.path.expanduser(req.project_path)).resolve()
        target = (p_root / req.relative_path).resolve()
        target.relative_to(p_root)

        target.parent.mkdir(parents=True, exist_ok=True)
        with open(target, "w", encoding="utf-8") as f:
            f.write(req.content)

        return FileActionResponse(
            success=True,
            message="File saved successfully",
            path=req.relative_path,
            size_bytes=len(req.content.encode("utf-8")),
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid path traversal outside project root")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post(
    "/upload",
    response_model=UploadFilesResponse,
    summary="Upload Files to a Project Directory",
)
async def upload_files(
    project_path: str = Form(...),
    relative_directory: str = Form(default=""),
    overwrite: bool = Form(default=False),
    files: list[UploadFile] = File(...),
) -> UploadFilesResponse:
    project_root, target_directory = _resolve_project_target(
        project_path,
        relative_directory,
    )
    if not target_directory.exists() or not target_directory.is_dir():
        raise HTTPException(status_code=404, detail="Upload directory not found")
    if not files:
        raise HTTPException(status_code=400, detail="No files were provided")

    targets: list[tuple[UploadFile, Path, str]] = []
    seen_names: set[str] = set()
    for upload in files:
        filename = (upload.filename or "").strip()
        if (
            not filename
            or filename in {".", ".."}
            or "/" in filename
            or "\\" in filename
            or Path(filename).name != filename
        ):
            raise HTTPException(status_code=400, detail="Invalid upload filename")
        if filename in seen_names:
            raise HTTPException(
                status_code=400,
                detail=f"Duplicate upload filename: {filename}",
            )
        seen_names.add(filename)
        target = target_directory / filename
        if target.exists() and not overwrite:
            raise HTTPException(
                status_code=409,
                detail=f"File already exists: {filename}",
            )
        targets.append((upload, target, filename))

    uploaded: list[FileActionResponse] = []
    for upload, target, filename in targets:
        temporary = target.with_name(f".{filename}.{uuid4().hex}.upload")
        size = 0
        try:
            with temporary.open("wb") as output:
                while chunk := await upload.read(1024 * 1024):
                    size += len(chunk)
                    if size > settings.MAX_UPLOAD_BYTES:
                        raise HTTPException(
                            status_code=413,
                            detail=(
                                f"{filename} exceeds the "
                                f"{settings.MAX_UPLOAD_BYTES}-byte upload limit"
                            ),
                        )
                    output.write(chunk)
            os.replace(temporary, target)
            uploaded.append(
                FileActionResponse(
                    success=True,
                    message="File uploaded successfully",
                    path=str(target.relative_to(project_root)),
                    size_bytes=size,
                ),
            )
        finally:
            await upload.close()
            temporary.unlink(missing_ok=True)

    return UploadFilesResponse(success=True, files=uploaded)


@router.get("/download", summary="Download a Project File")
async def download_file(
    project_path: str = Query(..., description="Project root path"),
    relative_path: str = Query(..., description="File relative path"),
) -> FileResponse:
    _, target = _resolve_project_target(project_path, relative_path)
    if not target.exists() or not target.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(
        path=target,
        filename=target.name,
        media_type="application/octet-stream",
    )


@router.post("/create", response_model=FileActionResponse, summary="Create File or Folder")
async def create_item(req: CreateItemRequest) -> FileActionResponse:
    try:
        p_root = Path(os.path.expanduser(req.project_path)).resolve()
        target = (p_root / req.relative_path).resolve()
        target.relative_to(p_root)

        if req.is_dir:
            target.mkdir(parents=True, exist_ok=True)
            return FileActionResponse(
                success=True,
                message="Folder created successfully",
                path=req.relative_path,
            )
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists():
                with open(target, "w", encoding="utf-8") as f:
                    f.write("")
            return FileActionResponse(
                success=True,
                message="File created successfully",
                path=req.relative_path,
                size_bytes=0,
            )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid path traversal outside project root")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/file", response_model=FileActionResponse, summary="Delete File or Folder")
async def delete_item(req: DeleteItemRequest) -> FileActionResponse:
    try:
        p_root = Path(os.path.expanduser(req.project_path)).resolve()
        target = (p_root / req.relative_path).resolve()
        target.relative_to(p_root)

        if not target.exists():
            raise HTTPException(status_code=404, detail="File or directory does not exist")

        if target == p_root:
            raise HTTPException(status_code=400, detail="Cannot delete project root")

        if target.is_file():
            os.remove(target)
        elif target.is_dir():
            shutil.rmtree(target)

        return FileActionResponse(
            success=True,
            message="Deleted successfully",
            path=req.relative_path,
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid path traversal outside project root")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
