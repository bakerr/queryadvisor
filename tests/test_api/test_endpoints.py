# tests/test_api/test_endpoints.py
import pytest
from unittest.mock import patch, MagicMock
from httpx import AsyncClient, ASGITransport
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
