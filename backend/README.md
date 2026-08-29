# WorkFromPhone Backend

FastAPI server for the WorkFromPhone project.

## Features

- **FastAPI**: Modern, high-performance web framework.
- **Pydantic v2**: Strict type safety, validation, and serialization.
- **Pydantic Settings**: Centralized environment variable management (`.env`).
- **CORS Middleware**: Pre-configured for Flutter web/mobile/desktop development.
- **Modular Structure**: Organized by `core`, `schemas`, `api/v1`.
- **Package Management**: Powered by [`uv`](https://github.com/astral-sh/uv) (fast Python package manager).

---

## Project Structure

```text
backend/
├── src/
│   └── backend/
│       ├── api/
│       │   └── v1/
│       │       ├── endpoints/
│       │       │   ├── __init__.py
│       │       │   └── health.py
│       │       ├── __init__.py
│       │       └── router.py
│       ├── core/
│       │   ├── __init__.py
│       │   └── config.py
│       ├── schemas/
│       │   ├── __init__.py
│       │   └── health.py
│       ├── __init__.py
│       └── main.py
├── .env.example
├── .gitignore
├── pyproject.toml
├── requirements.txt
└── README.md
```

---

## Getting Started

### 1. Using `uv` (Recommended)

Make sure you are in the `backend/` directory:

```bash
cd backend
```

#### Run the development server with auto-reload:
```bash
uv run uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
```
or simply:
```bash
uv run backend
```

---

### 2. Using Standard Python Virtual Environment (`venv`)

```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
```

---

## Interactive Documentation

Once the server is running, access:

- **Swagger UI**: [http://localhost:8000/docs](http://localhost:8000/docs)
- **ReDoc**: [http://localhost:8000/redoc](http://localhost:8000/redoc)
- **Health Check**: [http://localhost:8000/api/v1/health](http://localhost:8000/api/v1/health)
