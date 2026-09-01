from typing import List, Optional
from pydantic import BaseModel, Field


class SearchRequest(BaseModel):
    query: str = Field(..., description="The search query text")
    limit: int = Field(5, ge=1, le=20, description="Max number of search results to return")
    searxng_url: Optional[str] = Field(None, description="Optional custom SearXNG instance URL override")


class SearchResultItem(BaseModel):
    title: str
    url: str
    snippet: str


class SearchResponse(BaseModel):
    query: str
    results: List[SearchResultItem]
    count: int
    engine: str = "searxng"
