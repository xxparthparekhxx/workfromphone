"""Entrypoint used by the self-contained Linux release binary."""

import uvicorn

from backend.main import create_app
from backend.core.config import settings


def main() -> None:
    uvicorn.run(
        create_app(),
        host=settings.HOST,
        port=settings.PORT,
        reload=False,
    )


if __name__ == "__main__":
    main()
