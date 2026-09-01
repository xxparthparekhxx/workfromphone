from typing import List
from fastapi import APIRouter, Header, HTTPException, Request

from backend.schemas.artifacts import (
    ArtifactMetadata,
    PublishArtifactRequest,
    PublishArtifactResponse,
)
from backend.services.artifact_service import artifact_service

router = APIRouter(prefix="/artifacts", tags=["Artifacts & Sharing"])


@router.post("/publish", response_model=PublishArtifactResponse, summary="Publish and share an artifact")
async def publish_artifact(req: PublishArtifactRequest, request: Request) -> PublishArtifactResponse:
    base_url = str(request.base_url).rstrip("/")
    return artifact_service.publish_artifact(req, base_url=base_url)


@router.get("", response_model=List[ArtifactMetadata], summary="List published artifacts")
async def list_artifacts() -> List[ArtifactMetadata]:
    return artifact_service.list_artifacts()


@router.delete("/{token}", summary="Delete a published artifact")
async def delete_artifact(token: str):
    success = artifact_service.delete_artifact(token)
    if not success:
        raise HTTPException(status_code=404, detail="Artifact not found")
    return {"success": True, "message": "Artifact deleted"}
