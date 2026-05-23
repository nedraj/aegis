import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock
from app import app, INFERENCE_URL, INFERENCE_ENGINE, MODEL_NAME

client = TestClient(app)


def test_health_degraded_when_backend_down():
    """Health should report degraded when the inference backend is unreachable."""
    with patch("app.client.get") as mock_get:
        mock_get.side_effect = Exception("connection refused")
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "degraded"
        assert data["inference_reachable"] is False


def test_model_info_returns_engine():
    response = client.get("/model-info")
    assert response.status_code == 200
    data = response.json()
    assert "model" in data
    assert "backend" in data


@patch("app.client.post")
def test_query_uses_openai_endpoint(mock_post):
    """The /query endpoint should always call the unified OpenAI-compatible path."""
    mock_response = MagicMock()
    mock_response.json.return_value = {
        "choices": [{"message": {"content": "MISSION UPDATE: All systems nominal."}}],
        "usage": {"completion_tokens": 42}
    }
    mock_post.return_value = mock_response

    response = client.post("/query", json={"prompt": "Status report?"})
    assert response.status_code == 200
    data = response.json()
    assert "MISSION UPDATE" in data["response"]
    assert data["backend"].endswith("-local")

    # Verify it called the OpenAI-compatible endpoint
    called_url = mock_post.call_args[0][0]
    assert called_url == "/v1/chat/completions"