"""Unit tests for scripts/seed_db.py — no live database required."""
from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest


@pytest.fixture()
def mock_conn():
    conn = MagicMock()
    conn.cursor.return_value = MagicMock()
    return conn


class TestEnsureDatabase:
    def test_sql_contains_if_not_exists(self):
        from scripts.seed_db import _ensure_database
        cursor = MagicMock()
        _ensure_database(cursor)
        sql = cursor.execute.call_args[0][0]
        assert "IF NOT EXISTS" in sql

    def test_sql_targets_queryadvisorsample(self):
        from scripts.seed_db import _ensure_database
        cursor = MagicMock()
        _ensure_database(cursor)
        sql = cursor.execute.call_args[0][0]
        assert "QueryAdvisorSample" in sql

    def test_sql_creates_database(self):
        from scripts.seed_db import _ensure_database
        cursor = MagicMock()
        _ensure_database(cursor)
        sql = cursor.execute.call_args[0][0]
        assert "CREATE DATABASE" in sql


class TestCreateDatabase:
    def test_connects_to_master(self, mock_conn):
        with patch("scripts.seed_db.get_connection", return_value=mock_conn) as mock_get:
            from scripts.seed_db import create_database
            create_database()
        mock_get.assert_called_once_with("master")

    def test_sets_autocommit(self, mock_conn):
        with patch("scripts.seed_db.get_connection", return_value=mock_conn):
            from scripts.seed_db import create_database
            create_database()
        assert mock_conn.autocommit is True

    def test_closes_connection(self, mock_conn):
        with patch("scripts.seed_db.get_connection", return_value=mock_conn):
            from scripts.seed_db import create_database
            create_database()
        mock_conn.close.assert_called_once()
