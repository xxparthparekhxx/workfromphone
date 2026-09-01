from typing import List, Optional
from fastapi import APIRouter, HTTPException, Query

from backend.core.security import INTERNAL_ERROR_DETAIL
from backend.schemas.git import (
    GitActionResult,
    GitCommitRequest,
    GitDiffResponse,
    GitDiscardRequest,
    GitStageRequest,
    GitStatusResponse,
    GitUnstageRequest,
)
from backend.services.git_service import git_service

router = APIRouter(prefix="/git", tags=["Git Source Control"])


@router.get("/status", response_model=GitStatusResponse, summary="Get Git Status")
async def get_status(project_path: str = Query(..., description="Project root directory")):
    try:
        return await git_service.get_status(project_path)
    except Exception:
        raise HTTPException(status_code=500, detail=INTERNAL_ERROR_DETAIL)


@router.get("/diff", response_model=GitDiffResponse, summary="Get Git Diff")
async def get_diff(
    project_path: str = Query(..., description="Project root directory"),
    relative_path: Optional[str] = Query(None, description="Optional relative file path"),
    staged: bool = Query(False, description="Whether to show staged diff"),
):
    try:
        return await git_service.get_diff(project_path, relative_path=relative_path, staged=staged)
    except Exception:
        raise HTTPException(status_code=500, detail=INTERNAL_ERROR_DETAIL)


@router.post("/stage", response_model=GitActionResult, summary="Stage Files (git add)")
async def stage_files(req: GitStageRequest):
    try:
        return await git_service.stage_files(req.project_path, req.paths)
    except Exception:
        raise HTTPException(status_code=500, detail=INTERNAL_ERROR_DETAIL)


@router.post("/unstage", response_model=GitActionResult, summary="Unstage Files (git restore --staged)")
async def unstage_files(req: GitUnstageRequest):
    try:
        return await git_service.unstage_files(req.project_path, req.paths)
    except Exception:
        raise HTTPException(status_code=500, detail=INTERNAL_ERROR_DETAIL)


@router.post("/discard", response_model=GitActionResult, summary="Discard File Changes")
async def discard_changes(req: GitDiscardRequest):
    try:
        return await git_service.discard_changes(req.project_path, req.paths)
    except Exception:
        raise HTTPException(status_code=500, detail=INTERNAL_ERROR_DETAIL)


@router.post("/commit", response_model=GitActionResult, summary="Commit Changes")
async def commit(req: GitCommitRequest):
    try:
        return await git_service.commit(req)
    except Exception:
        raise HTTPException(status_code=500, detail=INTERNAL_ERROR_DETAIL)


@router.post("/push", response_model=GitActionResult, summary="Push to Remote (git push)")
async def push(project_path: str = Query(..., description="Project root directory")):
    try:
        return await git_service.push(project_path)
    except Exception:
        raise HTTPException(status_code=500, detail=INTERNAL_ERROR_DETAIL)


@router.post("/pull", response_model=GitActionResult, summary="Pull from Remote (git pull)")
async def pull(project_path: str = Query(..., description="Project root directory")):
    try:
        return await git_service.pull(project_path)
    except Exception:
        raise HTTPException(status_code=500, detail=INTERNAL_ERROR_DETAIL)


@router.get("/branches", response_model=List[str], summary="List Git Branches")
async def get_branches(project_path: str = Query(..., description="Project root directory")):
    try:
        return await git_service.get_branches(project_path)
    except Exception:
        raise HTTPException(status_code=500, detail=INTERNAL_ERROR_DETAIL)
