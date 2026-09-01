from fastapi import APIRouter

from backend.schemas.search import SearchRequest, SearchResponse
from backend.services.search_service import search_service

router = APIRouter(prefix="/search", tags=["Web Search"])


@router.post("", response_model=SearchResponse, summary="Perform Web Search")
async def web_search(req: SearchRequest) -> SearchResponse:
    return await search_service.search(req)
