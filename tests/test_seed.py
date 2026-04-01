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


class TestCreateDboTables:
    def _all_sql(self, mock_cursor) -> str:
        from scripts.seed_db import _create_dbo_tables
        _create_dbo_tables(mock_cursor)
        return " ".join(call[0][0] for call in mock_cursor.execute.call_args_list)

    def test_all_five_tables_present(self):
        cursor = MagicMock()
        sql = self._all_sql(cursor)
        for table in ["Categories", "Customers", "Products", "Orders", "OrderItems"]:
            assert table in sql, f"Expected DDL for dbo.{table} but not found"

    def test_customers_email_index_created(self):
        cursor = MagicMock()
        sql = self._all_sql(cursor)
        assert "IX_Customers_Email" in sql

    def test_products_categoryid_index_created(self):
        cursor = MagicMock()
        sql = self._all_sql(cursor)
        assert "IX_Products_CategoryID" in sql

    def test_orders_customerid_index_created(self):
        cursor = MagicMock()
        sql = self._all_sql(cursor)
        assert "IX_Orders_CustomerID" in sql

    def test_orders_orderdate_index_created(self):
        cursor = MagicMock()
        sql = self._all_sql(cursor)
        assert "IX_Orders_OrderDate" in sql

    def test_orderitems_orderid_index_created(self):
        cursor = MagicMock()
        sql = self._all_sql(cursor)
        assert "IX_OrderItems_OrderID" in sql

    def test_orderitems_productid_index_created(self):
        cursor = MagicMock()
        sql = self._all_sql(cursor)
        assert "IX_OrderItems_ProductID" in sql

    def test_all_ddl_is_idempotent(self):
        """Every CREATE TABLE must be guarded by IF OBJECT_ID(...) IS NULL."""
        from scripts.seed_db import _DBO_DDL
        for stmt in _DBO_DDL:
            if "CREATE TABLE" in stmt:
                assert "IF OBJECT_ID" in stmt, (
                    f"CREATE TABLE statement missing IF OBJECT_ID guard:\n{stmt[:120]}"
                )


class TestCreateBadTables:
    def _all_sql(self, mock_cursor) -> str:
        from scripts.seed_db import _create_bad_tables
        _create_bad_tables(mock_cursor)
        return " ".join(call[0][0] for call in mock_cursor.execute.call_args_list)

    def test_bad_schema_created(self):
        cursor = MagicMock()
        sql = self._all_sql(cursor)
        assert "CREATE SCHEMA bad" in sql

    def test_bad_orders_table_created(self):
        cursor = MagicMock()
        sql = self._all_sql(cursor)
        assert "bad.Orders" in sql

    def test_bad_orders_customerid_is_varchar(self):
        """CustomerID must be varchar to trigger check_join_type_mismatch."""
        from scripts.seed_db import _DDL_BAD_ORDERS
        assert "CustomerID" in _DDL_BAD_ORDERS
        lines = _DDL_BAD_ORDERS.splitlines()
        customerid_line = next(
            (line for line in lines if "CustomerID" in line and "CONSTRAINT" not in line), ""
        )
        assert "varchar" in customerid_line.lower(), (
            "bad.Orders.CustomerID must be varchar to trigger type mismatch rule"
        )

    def test_bad_events_has_no_nonclustered_index(self):
        """bad.Events must have NO CREATE INDEX — triggers table scan rule."""
        from scripts.seed_db import _BAD_DDL
        events_index_stmts = [
            s for s in _BAD_DDL
            if "Events" in s and "CREATE INDEX" in s
        ]
        assert not events_index_stmts, (
            "bad.Events must have no non-clustered indexes to trigger table scan rule"
        )

    def test_bad_logs_has_partial_index_without_include(self):
        """bad.Logs index must NOT use INCLUDE — triggers non-covering index rule."""
        from scripts.seed_db import _DDL_BAD_LOGS_IDX
        assert "IX_Logs_LogLevel" in _DDL_BAD_LOGS_IDX
        assert "INCLUDE" not in _DDL_BAD_LOGS_IDX, (
            "bad.Logs index must not have INCLUDE clause to trigger non-covering index rule"
        )


class TestSeedSchema:
    def test_connects_to_sample_db(self, mock_conn):
        with patch("scripts.seed_db.get_connection", return_value=mock_conn) as mock_get:
            from scripts.seed_db import seed_schema
            seed_schema()
        mock_get.assert_called_once_with("QueryAdvisorSample")

    def test_sets_autocommit(self, mock_conn):
        with patch("scripts.seed_db.get_connection", return_value=mock_conn):
            from scripts.seed_db import seed_schema
            seed_schema()
        assert mock_conn.autocommit is True

    def test_closes_connection_on_success(self, mock_conn):
        with patch("scripts.seed_db.get_connection", return_value=mock_conn):
            from scripts.seed_db import seed_schema
            seed_schema()
        mock_conn.close.assert_called_once()

    def test_closes_connection_on_exception(self, mock_conn):
        mock_conn.cursor.return_value.execute.side_effect = RuntimeError("db error")
        with patch("scripts.seed_db.get_connection", return_value=mock_conn):
            from scripts.seed_db import seed_schema
            with pytest.raises(RuntimeError):
                seed_schema()
        mock_conn.close.assert_called_once()
