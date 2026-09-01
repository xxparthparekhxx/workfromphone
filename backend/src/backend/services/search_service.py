import html
import re
import urllib.parse
from typing import List, Optional

import httpx

from backend.core.config import settings
from backend.schemas.search import SearchRequest, SearchResponse, SearchResultItem


class SearchService:
    async def _search_searxng(
        self,
        query: str,
        limit: int,
        base_url: str,
    ) -> List[SearchResultItem]:
        endpoint = f"{base_url.rstrip('/')}/search"
        params = {
            "q": query,
            "format": "json",
            "categories": "general",
            "language": "auto",
        }
        headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/122.0.0.0 Safari/537.36"
            ),
            "Accept": "application/json",
        }

        async with httpx.AsyncClient(timeout=8.0, follow_redirects=True) as client:
            resp = await client.get(endpoint, params=params, headers=headers)
            if resp.status_code != 200:
                # Try POST method as some SearXNG instances require POST
                resp = await client.post(endpoint, data=params, headers=headers)
                if resp.status_code != 200:
                    return []

            data = resp.json()
            raw_results = data.get("results", [])
            items: List[SearchResultItem] = []

            for r in raw_results:
                if len(items) >= limit:
                    break
                title = r.get("title", "").strip()
                url = r.get("url", "").strip()
                snippet = (r.get("content") or r.get("snippet") or "").strip()

                if title and url.startswith("http"):
                    items.append(
                        SearchResultItem(
                            title=title,
                            url=url,
                            snippet=snippet,
                        )
                    )
            return items

    async def _search_web_engine(self, query: str, limit: int) -> List[SearchResultItem]:
        """Robust web scraper for web search queries."""
        url = "https://html.duckduckgo.com/html/"
        headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/122.0.0.0 Safari/537.36"
            ),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
        }

        results: List[SearchResultItem] = []
        try:
            async with httpx.AsyncClient(timeout=10.0, follow_redirects=True) as client:
                resp = await client.post(url, data={"q": query}, headers=headers)
                if resp.status_code == 200:
                    text = resp.text
                    blocks = re.findall(
                        r'<div[^>]+class=[\"\'][^\"\']*result[^\"\']*results_links[^\"\']*[\"\'][^>]*>(.*?)</div>\s*</div>',
                        text,
                        re.DOTALL | re.IGNORECASE,
                    )
                    if not blocks:
                        blocks = re.findall(
                            r'<div[^>]+class=[\"\'][^\"\']*result[^\"\']*[\"\'][^>]*>(.*?)</div>\s*</div>',
                            text,
                            re.DOTALL | re.IGNORECASE,
                        )

                    for block in blocks:
                        if len(results) >= limit:
                            break

                        title_match = re.search(
                            r'<a[^>]+class=[\"\'][^\"\']*result__a[^\"\']*[\"\'][^>]+href=[\"\']([^\"\']+)[\"\'][^>]*>(.*?)</a>',
                            block,
                            re.DOTALL | re.IGNORECASE,
                        )
                        if not title_match:
                            continue

                        raw_url, raw_title = title_match.group(1), title_match.group(2)

                        # Skip search engine ads or redirect wraps
                        if "duckduckgo.com/y.js" in raw_url:
                            continue
                        if "uddg=" in raw_url:
                            m = re.search(r"uddg=([^&]+)", raw_url)
                            if m:
                                raw_url = urllib.parse.unquote(m.group(1))

                        clean_title = html.unescape(re.sub(r"<[^>]+>", "", raw_title)).strip()

                        snippet_match = re.search(
                            r'<a[^>]+class=[\"\'][^\"\']*result__snippet[^\"\']*[\"\'][^>]*>(.*?)</a>',
                            block,
                            re.DOTALL | re.IGNORECASE,
                        )
                        snippet = ""
                        if snippet_match:
                            snippet = html.unescape(
                                re.sub(r"<[^>]+>", "", snippet_match.group(1))
                            ).strip()

                        if clean_title and raw_url.startswith("http"):
                            results.append(
                                SearchResultItem(
                                    title=clean_title,
                                    url=raw_url,
                                    snippet=snippet,
                                )
                            )
        except Exception:
            pass

        return results

    async def search(self, req: SearchRequest) -> SearchResponse:
        query = req.query.strip()
        limit = req.limit
        searxng_url = req.searxng_url or settings.SEARXNG_URL

        # 1. Try configured SearXNG
        if searxng_url:
            try:
                searxng_results = await self._search_searxng(query, limit, searxng_url)
                if searxng_results:
                    return SearchResponse(
                        query=query,
                        results=searxng_results,
                        count=len(searxng_results),
                        engine="searxng",
                    )
            except Exception:
                pass

        # 2. Try web engine fallback
        fallback_results = await self._search_web_engine(query, limit)
        return SearchResponse(
            query=query,
            results=fallback_results,
            count=len(fallback_results),
            engine="searxng-web-engine",
        )


search_service = SearchService()
