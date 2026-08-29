from fastapi.testclient import TestClient
from backend.main import app

client = TestClient(app)


def test_root_endpoint():
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "message" in data
    assert data["version"] == "0.1.0"


def test_health_check_endpoint():
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert data["app_name"] == "WorkFromPhone Backend"
    assert "timestamp" in data


def test_fs_browse_endpoint():
    response = client.get("/api/v1/fs/browse")
    assert response.status_code == 200
    data = response.json()
    assert "current_path" in data
    assert "items" in data
    assert isinstance(data["items"], list)


def test_fs_quick_paths_endpoint():
    response = client.get("/api/v1/fs/quick-paths")
    assert response.status_code == 200
    data = response.json()
    assert "home" in data
    assert "common_paths" in data


def test_llm_models_endpoint():
    response = client.post(
        "/api/v1/llm/models",
        json={"base_url": "https://openrouter.ai/api/v1", "api_key": ""},
    )
    assert response.status_code == 200
    data = response.json()
    assert "models" in data
    assert len(data["models"]) > 0
    assert any("claude" in m["id"] or "gpt" in m["id"] for m in data["models"])
