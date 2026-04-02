# Sanitize pyodbc Exceptions (Issue #17) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent pyodbc connection errors (which may contain plaintext SA passwords) from propagating to HTTP clients; return a sanitized 503 response instead.

**Architecture:** Introduce a `DatabaseConnectionError` exception class in `app/exceptions.py`. Wrap `pyodbc.connect()` in `get_connection()` to catch `pyodbc.Error` and raise `DatabaseConnectionError` with `from None` (suppresses exception chain). Register a FastAPI exception handler in `app/main.py` that maps `DatabaseConnectionError` → HTTP 503.

**Tech Stack:** Python 3.11, FastAPI, pyodbc, pytest, httpx (async test client)

---

### Task 1: Define `DatabaseConnectionError` and fix `get_connection()`

**Files:**
- Create: `app/exceptions.py`
- Modify: `app/config.py`
- Test: `tests/test_config.py`

- [ ] **Step 1: Write the failing tests**

Add these two tests to `tests/test_config.py` (after the existing imports and tests):

```python
from unittest.mock import patch, MagicMock
from app.exceptions import DatabaseConnectionError


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
```

Also add `from app.config import get_connection` to the imports at the top of `tests/test_config.py`.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/lowell/projects/work/queryadvisor
python -m pytest tests/test_config.py::test_get_connection_raises_database_connection_error_on_pyodbc_failure tests/test_config.py::test_get_connection_exception_message_contains_no_credentials -v
```

Expected: FAIL with `ImportError: cannot import name 'DatabaseConnectionError'` or `ModuleNotFoundError`

- [ ] **Step 3: Create `app/exceptions.py`**

```python
from __future__ import annotations


class DatabaseConnectionError(Exception):
    """Raised when a database connection attempt fails.

    Carries only the database name — no connection string fragments,
    credentials, driver info, or server addresses.
    """

    def __init__(self, database: str) -> None:
        self.database = database
        super().__init__(f"Database connection failed for '{database}'")
```

- [ ] **Step 4: Modify `app/config.py` — wrap `get_connection()`**

Replace the existing `get_connection` function (lines ~27-30) with:

```python
def get_connection(database: str):
    import pyodbc  # noqa: PLC0415 — lazy import; pyodbc is a production dep only

    from app.exceptions import DatabaseConnectionError  # noqa: PLC0415

    try:
        return pyodbc.connect(build_connection_string(database), timeout=10)
    except pyodbc.Error:
        raise DatabaseConnectionError(database) from None
```

- [ ] **Step 5: Run the new tests to verify they pass**

```bash
python -m pytest tests/test_config.py::test_get_connection_raises_database_connection_error_on_pyodbc_failure tests/test_config.py::test_get_connection_exception_message_contains_no_credentials -v
```

Expected: PASS both tests

- [ ] **Step 6: Run all existing config tests to verify nothing broke**

```bash
python -m pytest tests/test_config.py -v
```

Expected: All tests PASS (6 original + 2 new = 8 total)

- [ ] **Step 7: Commit**

```bash
git add app/exceptions.py app/config.py tests/test_config.py
git commit -m "fix: sanitize pyodbc exceptions in get_connection() to prevent credential leakage"
```

---

### Task 2: Add FastAPI 503 exception handler

**Files:**
- Modify: `app/main.py`
- Test: `tests/test_api/test_endpoints.py`

- [ ] **Step 1: Write failing API tests**

Add these tests to `tests/test_api/test_endpoints.py` (after existing imports and tests):

```python
from app.exceptions import DatabaseConnectionError


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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python -m pytest tests/test_api/test_endpoints.py::test_databases_endpoint_returns_503_on_connection_failure tests/test_api/test_endpoints.py::test_databases_options_endpoint_returns_503_on_connection_failure tests/test_api/test_endpoints.py::test_analyze_endpoint_returns_503_on_connection_failure -v
```

Expected: FAIL — all three return 500 (handler not registered yet), or unhandled exception

- [ ] **Step 3: Add the 503 handler to `app/main.py`**

Add these imports at the top of `app/main.py` (alongside existing imports):

```python
from fastapi.responses import JSONResponse

from app.exceptions import DatabaseConnectionError
```

Then add the exception handler immediately after the `app = FastAPI(...)` line:

```python
@app.exception_handler(DatabaseConnectionError)
async def database_connection_error_handler(
    request: Request, exc: DatabaseConnectionError
) -> JSONResponse:
    return JSONResponse(
        status_code=503,
        content={"detail": f"Database unavailable: '{exc.database}'"},
    )
```

- [ ] **Step 4: Run the new API tests to verify they pass**

```bash
python -m pytest tests/test_api/test_endpoints.py::test_databases_endpoint_returns_503_on_connection_failure tests/test_api/test_endpoints.py::test_databases_options_endpoint_returns_503_on_connection_failure tests/test_api/test_endpoints.py::test_analyze_endpoint_returns_503_on_connection_failure -v
```

Expected: PASS all three

- [ ] **Step 5: Run all API tests to verify nothing broke**

```bash
python -m pytest tests/test_api/ -v
```

Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add app/main.py tests/test_api/test_endpoints.py
git commit -m "feat: return 503 for database connection failures via FastAPI exception handler"
```

---

### Task 3: Full verification

**Files:** No changes — verification only

- [ ] **Step 1: Run the full test suite**

```bash
python -m pytest tests/ -v
```

Expected: All tests PASS

- [ ] **Step 2: Run lint**

```bash
python -m ruff check app/ tests/
```

Expected: No errors

- [ ] **Step 3: Run type check**

```bash
python -m mypy app/ --ignore-missing-imports
```

Expected: No errors (or same errors as before this change)

- [ ] **Step 4: Commit plan file**

```bash
git add docs/superpowers/plans/2026-04-01-17-sanitize-pyodbc-exceptions.md
git commit -m "docs: add implementation plan for issue #17"
```
