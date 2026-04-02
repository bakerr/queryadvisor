import os
from unittest.mock import patch

import pytest

from app.config import build_connection_string, get_connection
from app.exceptions import DatabaseConnectionError


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


def test_unknown_auth_method_falls_back_to_windows():
    """Unrecognized SQL_AUTH_METHOD falls back to Trusted_Connection."""
    env = {"SQL_AUTH_METHOD": "kerberos", "SQL_SERVER_HOST": "localhost",
           "ODBC_DRIVER": "ODBC Driver 18 for SQL Server"}
    with patch.dict(os.environ, env, clear=True):
        conn_str = build_connection_string("mydb")
    assert "Trusted_Connection=yes" in conn_str
    assert "PWD=" not in conn_str


def test_get_connection_raises_database_connection_error_on_pyodbc_failure():
    """pyodbc.Error is caught and re-raised as DatabaseConnectionError."""
    import pyodbc
    with patch("app.config.pyodbc") as mock_pyodbc:
        mock_pyodbc.Error = pyodbc.Error
        mock_pyodbc.connect.side_effect = pyodbc.Error(
            "08001",
            "[08001] [Microsoft][ODBC Driver 18] "
            "PWD=SuperSecret123; SERVER=localhost; (0) (SQLDriverConnect)",
        )
        env = {
            "SQL_AUTH_METHOD": "sql",
            "MSSQL_SA_PASSWORD": "SuperSecret123",
            "SQL_SERVER_HOST": "localhost",
            "ODBC_DRIVER": "ODBC Driver 18 for SQL Server",
        }
        with patch.dict(os.environ, env, clear=True):
            with pytest.raises(DatabaseConnectionError) as exc_info:
                get_connection("mydb")
    assert exc_info.value.database == "mydb"
    assert exc_info.value.__cause__ is None
    assert exc_info.value.__context__ is None


def test_get_connection_exception_message_contains_no_credentials():
    """The sanitized exception message must not contain password or connection string fragments."""
    import pyodbc
    with patch("app.config.pyodbc") as mock_pyodbc:
        mock_pyodbc.Error = pyodbc.Error
        mock_pyodbc.connect.side_effect = pyodbc.Error(
            "08001",
            "PWD=SuperSecret123; UID=sa; SERVER=10.0.0.1",
        )
        env = {
            "SQL_AUTH_METHOD": "sql",
            "MSSQL_SA_PASSWORD": "SuperSecret123",
            "SQL_SERVER_HOST": "10.0.0.1",
            "ODBC_DRIVER": "ODBC Driver 18 for SQL Server",
        }
        with patch.dict(os.environ, env, clear=True):
            with pytest.raises(DatabaseConnectionError) as exc_info:
                get_connection("mydb")
    msg = str(exc_info.value)
    assert "SuperSecret123" not in msg
    assert "10.0.0.1" not in msg
    assert "mydb" in msg
