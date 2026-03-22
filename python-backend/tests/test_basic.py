"""Basic tests for MarketCoach backend"""

import pytest
from fastapi.testclient import TestClient
from app.main import app


@pytest.fixture
def client():
    """Create test client"""
    return TestClient(app)


def test_root_endpoint(client):
    """Test root endpoint"""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["service"] == "MarketCoach Backend API"
    assert data["status"] == "operational"


def test_health_check(client):
    """Test health check endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"


def test_internal_health(client):
    """Test internal health endpoint"""
    response = client.get("/internal/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "services" in data


def test_api_docs_available(client):
    """Test that API docs are available"""
    response = client.get("/api/docs")
    assert response.status_code == 200


def test_openapi_schema(client):
    """Test OpenAPI schema endpoint"""
    response = client.get("/api/openapi.json")
    assert response.status_code == 200
    data = response.json()
    assert data["info"]["title"] == "MarketCoach Backend API"
