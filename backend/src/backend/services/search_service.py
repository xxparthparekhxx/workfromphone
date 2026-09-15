import html
import re
import urllib.parse
from typing import List

import httpx

from backend.core.config import settings
from backend.core.security import assert_safe_outbound_url
from backend.schemas.search import SearchRequest, SearchResponse, SearchResultItem


class SearchService:
    async def _search_searxng(
        self,
        query: str,
        limit: int,
        base_url: str,
    ) -> List[SearchResultItem]:
        endpoint = f"{base_url.rstrip('/')}/search"
        assert_safe_outbound_url(endpoint)
        # NOTE: redirects are followed manually below (max 3 hops, each hop
        # re-validated) so a compromised SearXNG cannot bounce us at a
        # metadata / link-local URL. DNS is validated at request time; see
        # assert_safe_outbound_url docs on the residual DNS TOCTOU.
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

        async with httpx.AsyncClient(timeout=8.0, follow_redirects=False) as client:
            resp = await self._get_with_validated_redirects(
                client, endpoint, params=params, headers=headers, method="GET"
            )
            if resp.status_code != 200:
                # Try POST method as some SearXNG instances require POST
                resp = await self._get_with_validated_redirects(
                    client, endpoint, params=params, headers=headers, method="POST"
                )
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
            async with httpx.AsyncClient(timeout=10.0, follow_redirects=False) as client:
                resp = await client.post(url, data={"q": query}, headers=headers)
                resp = await self._follow_public_redirects(client, resp, url)
                if resp.status_code == 200:
                    text = resp.text
                    blocks = re.findall(
                        r"<div[^>]+class=[\"\'][^\"\']*result[^\"\']*results_links[^\"\']*[\"\'][^>]*>(.*?)</div>\s*</div>",
                        text,
                        re.DOTALL | re.IGNORECASE,
                    )
                    if not blocks:
                        blocks = re.findall(
                            r"<div[^>]+class=[\"\'][^\"\']*result[^\"\']*[\"\'][^>]*>(.*?)</div>\s*</div>",
                            text,
                            re.DOTALL | re.IGNORECASE,
                        )

                    for block in blocks:
                        if len(results) >= limit:
                            break

                        title_match = re.search(
                            r"<a[^>]+class=[\"\'][^\"\']*result__a[^\"\']*[\"\'][^>]+href=[\"\']([^\"\']+)[\"\'][^>]*>(.*?)</a>",
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
                            r"<a[^>]+class=[\"\'][^\"\']*result__snippet[^\"\']*[\"\'][^>]*>(.*?)</a>",
                            block,
                            re.DOTALL | re.IGNORECASE,
                        )
                        snippet = ""
                        if snippet_match:
                            snippet = html.unescape(re.sub(r"<[^>]+>", "", snippet_match.group(1))).strip()

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

    @staticmethod
    async def _get_with_validated_redirects(client, url, *, params, headers, method: str):
        """Follow up to 3 redirects, re-validating every hop with SSRF checks."""
        current_url = url
        current_params = params
        for _ in range(4):
            assert_safe_outbound_url(current_url)
            if method == "POST":
                resp = await client.post(current_url, data=current_params, headers=headers)
            else:
                resp = await client.get(current_url, params=current_params, headers=headers)
            if resp.status_code not in {301, 302, 303, 307, 308}:
                return resp
            location = resp.headers.get("location", "")
            if not location:
                return resp
            current_url = httpx.URL(current_url).join(location).__str__()
            current_params = None
            method = "GET"
        return resp

    @staticmethod
    async def _follow_public_redirects(client, resp, url: str):
        for _ in range(3):
            if resp.status_code not in {301, 302, 303, 307, 308}:
                return resp
            location = resp.headers.get("location", "")
            if not location:
                return resp
            next_url = httpx.URL(url).join(location).__str__()
            if next_url.startswith("http"):
                return resp  # fixed DDG endpoint: do not chase off-host
            url = next_url
            resp = await client.get(url)
        return resp

    async def search(self, req: SearchRequest) -> SearchResponse:
        query = req.query.strip()
        limit = req.limit
        # Per-request SearXNG overrides were an authenticated SSRF probe
        # (any bearer holder could make the backend fetch an arbitrary URL).
        # The server-configured instance is the only one used now.
        searxng_url = settings.SEARXNG_URL

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
