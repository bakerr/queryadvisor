# tests/test_api/test_endpoints.py
from unittest.mock import MagicMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.exceptions import DatabaseConnectionError
from app.main import app


@pytest.fixture
def mock_db_list():
    mock_conn = MagicMock()
    mock_cursor = MagicMock()
    mock_conn.cursor.return_value = mock_cursor
    mock_cursor.fetchall.return_value = [("master",), ("AdventureWorks",)]
    return mock_conn


@pytest.mark.asyncio
async def test_index_returns_200():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/")
    assert response.status_code == 200
    assert "QueryAdvisor" in response.text


@pytest.mark.asyncio
async def test_databases_endpoint(mock_db_list):
    with patch("app.main.get_connection", return_value=mock_db_list):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get("/api/databases")
    assert response.status_code == 200
    data = response.json()
    assert "AdventureWorks" in data["databases"]


@pytest.mark.asyncio
async def test_databases_endpoint_returns_503_on_connection_failure():
    """GET /api/databases returns 503 when DB is unreachable."""
    with patch("app.main.get_connection", side_effect=DatabaseConnectionError("master")):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get("/api/databases")
    assert response.status_code == 503
    body = response.json()
    assert "master" in body["detail"]
    assert "PWD" not in body["detail"]
    assert "password" not in body["detail"].lower()


@pytest.mark.asyncio
async def test_databases_options_endpoint_returns_503_on_connection_failure():
    """GET /api/databases/options returns 503 when DB is unreachable."""
    with patch("app.main.get_connection", side_effect=DatabaseConnectionError("master")):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get("/api/databases/options")
    assert response.status_code == 503
    body = response.json()
    assert "master" in body["detail"]


@pytest.mark.asyncio
async def test_analyze_endpoint_returns_503_on_connection_failure():
    """POST /api/analyze returns 503 when DB is unreachable."""
    with patch("app.main.get_connection", side_effect=DatabaseConnectionError("mydb")):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post(
                "/api/analyze",
                data={"sql": "SELECT 1", "database": "mydb", "username": "user"},
            )
    assert response.status_code == 503
    body = response.json()
    assert "mydb" in body["detail"]


@pytest.mark.asyncio
async def test_analyze_endpoint_returns_503_when_metadata_connection_fails():
    """POST /api/analyze returns 503 when collect_metadata's DB connection fails."""
    # Ping succeeds; the connection inside collect_metadata fails.
    mock_conn = MagicMock()
    mock_conn.close.return_value = None
    collector_patch = patch(
        "app.metadata.collector.get_connection",
        side_effect=DatabaseConnectionError("mydb"),
    )
    with patch("app.main.get_connection", return_value=mock_conn), collector_patch:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post(
                "/api/analyze",
                data={"sql": "SELECT * FROM dbo.Orders", "database": "mydb", "username": "user"},
            )
    assert response.status_code == 503
    body = response.json()
    assert "mydb" in body["detail"]
