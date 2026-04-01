import os
import pytest
from unittest.mock import patch
from app.config import build_connection_string


def test_windows_auth_is_default():
    """No SQL_AUTH_METHOD → Trusted_Connection used."""
    env = {
        "SQL_SERVER_HOST": "localhost",
        "ODBC_DRIVER": "ODBC Driver 18 for SQL Server",
    }
    with patch.dict(os.environ, env, clear=True):
        conn_str = build_connection_string("testdb")
    assert "Trusted_Connection=yes" in conn_str
    assert "DATABASE=testdb" in conn_str
    assert "SERVER=localhost" in conn_str
    assert "PWD=" not in conn_str


def test_windows_auth_explicit():
    """SQL_AUTH_METHOD=windows → Trusted_Connection used."""
    env = {
        "SQL_AUTH_METHOD": "windows",
        "SQL_SERVER_HOST": "winhost",
        "ODBC_DRIVER": "ODBC Driver 18 for SQL Server",
    }
    with patch.dict(os.environ, env, clear=True):
        conn_str = build_connection_string("mydb")
    assert "Trusted_Connection=yes" in conn_str
    assert "SERVER=winhost" in conn_str
    assert "PWD=" not in conn_str


def test_sql_auth_connection_string():
    """SQL_AUTH_METHOD=sql → SA password, TrustServerCertificate."""
    env = {
        "SQL_AUTH_METHOD": "sql",
        "SQL_SERVER_HOST": "localhost",
        "MSSQL_SA_PASSWORD": "TestPass123!",
        "ODBC_DRIVER": "ODBC Driver 18 for SQL Server",
    }
    with patch.dict(os.environ, env, clear=True):
        conn_str = build_connection_string("mydb")
    assert "Trusted_Connection" not in conn_str
    assert "UID=sa" in conn_str
    assert "PWD=TestPass123!" in conn_str
    assert "TrustServerCertificate=yes" in conn_str
    assert "DATABASE=mydb" in conn_str
    assert "SERVER=localhost" in conn_str


def test_sql_auth_raises_without_password():
    """SQL_AUTH_METHOD=sql without MSSQL_SA_PASSWORD → ValueError."""
    env = {"SQL_AUTH_METHOD": "sql"}
    with patch.dict(os.environ, env, clear=True):
        with pytest.raises(ValueError, match="MSSQL_SA_PASSWORD"):
            build_connection_string("mydb")


def test_custom_driver_is_used():
    """ODBC_DRIVER env var propagates into the connection string."""
    env = {
        "ODBC_DRIVER": "ODBC Driver 17 for SQL Server",
        "SQL_SERVER_HOST": "localhost",
    }
    with patch.dict(os.environ, env, clear=True):
        conn_str = build_connection_string("mydb")
    assert "ODBC Driver 17 for SQL Server" in conn_str
