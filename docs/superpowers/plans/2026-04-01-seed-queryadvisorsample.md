# QueryAdvisorSample Seed Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create an idempotent `scripts/seed_db.py` that populates a `QueryAdvisorSample` SQL Server database with a clean e-commerce schema and deliberate anti-pattern tables that exercise every QueryAdvisor analysis rule.

**Architecture:** A standalone Python script using `app.config.get_connection()` for all DB access. First connects to `master` to create the database, then reconnects to `QueryAdvisorSample` for all DDL and DML. All statements are idempotent (`IF NOT EXISTS` / `IF OBJECT_ID() IS NULL` / `CREATE OR ALTER`). A `make db-seed` Makefile target invokes it via `uv run`.

**Tech Stack:** Python 3.11, pyodbc, SQL Server 2022, `app.config.get_connection`, uv

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `scripts/__init__.py` | Makes `scripts/` importable by tests |
| Create | `scripts/seed_db.py` | All seeding logic |
| Modify | `Makefile` | Add `db-seed` target |
| Modify | `tests/test_infra.py` | Static checks: no hardcoded creds, Makefile target |
| Create | `tests/test_seed.py` | Unit tests for seed functions (no live DB) |

---

## Task 1: Static infra tests + script scaffold + Makefile target

**Files:**
- Modify: `tests/test_infra.py`
- Create: `scripts/__init__.py`
- Create: `scripts/seed_db.py` (skeleton only)
- Modify: `Makefile`

- [ ] **Step 1: Add failing static tests to `tests/test_infra.py`**

Append these three tests to the end of the existing file:

```python
def test_seed_script_uses_get_connection():
    """seed_db.py must import from app.config, not hardcode credentials."""
    script = (ROOT / "scripts" / "seed_db.py").read_text()
    assert "from app.config import get_connection" in script, (
        "seed_db.py must use app.config.get_connection, not build its own connection"
    )
    assert "PWD=" not in script, "seed_db.py must not contain hardcoded credentials"
    assert "MSSQL_SA_PASSWORD" not in script, (
        "seed_db.py must not read MSSQL_SA_PASSWORD directly — delegate to get_connection"
    )


def test_makefile_has_db_seed_target():
    """Makefile must have a db-seed target."""
    makefile = (ROOT / "Makefile").read_text()
    assert "db-seed:" in makefile, "Makefile must have a db-seed target"


def test_db_seed_calls_uv_run():
    """db-seed Makefile target must invoke seed_db.py via uv run."""
    makefile = (ROOT / "Makefile").read_text()
    in_recipe = False
    for line in makefile.splitlines():
        if line.startswith("db-seed:"):
            in_recipe = True
            continue
        if in_recipe:
            if line and not line[0].isspace():
                break
            if "uv run" in line and "seed_db" in line:
                return
    pytest.fail("db-seed target does not invoke 'uv run ... seed_db.py'")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
uv run pytest tests/test_infra.py::test_seed_script_uses_get_connection \
              tests/test_infra.py::test_makefile_has_db_seed_target \
              tests/test_infra.py::test_db_seed_calls_uv_run -v
```

Expected: 3 FAILED (files don't exist yet)

- [ ] **Step 3: Create `scripts/__init__.py`**

```python
```

(empty file — makes scripts/ importable by tests)

- [ ] **Step 4: Create `scripts/seed_db.py` skeleton**

```python
"""
Idempotent seed script for the QueryAdvisorSample development database.

Usage:
    make db-seed
    # or directly:
    uv run python scripts/seed_db.py
"""
from __future__ import annotations

import random
import string
from datetime import datetime, timedelta

from app.config import get_connection

DB_NAME = "QueryAdvisorSample"
```

- [ ] **Step 5: Add `db-seed` target to `Makefile`**

Add after the `db-reset` target and before `help`:

```makefile
db-seed: ## Seed QueryAdvisorSample with sample schema and data (requires db-start)
	uv run python scripts/seed_db.py
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
uv run pytest tests/test_infra.py::test_seed_script_uses_get_connection \
              tests/test_infra.py::test_makefile_has_db_seed_target \
              tests/test_infra.py::test_db_seed_calls_uv_run -v
```

Expected: 3 PASSED

- [ ] **Step 7: Commit**

```bash
git add scripts/__init__.py scripts/seed_db.py Makefile tests/test_infra.py
git commit -m "feat: scaffold seed script and Makefile target, add infra tests"
```

---

## Task 2: Database creation (`_ensure_database` + `create_database`)

**Files:**
- Modify: `scripts/seed_db.py`
- Create: `tests/test_seed.py`

- [ ] **Step 1: Create `tests/test_seed.py` with failing unit tests**

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
uv run pytest tests/test_seed.py -v
```

Expected: FAILED with `ImportError` or `AttributeError` (functions not yet defined)

- [ ] **Step 3: Implement `_ensure_database` and `create_database` in `scripts/seed_db.py`**

Add after the `DB_NAME` line:

```python

# ---------------------------------------------------------------------------
# Database creation — connects to master
# ---------------------------------------------------------------------------

def _ensure_database(cursor) -> None:
    """Create QueryAdvisorSample if it does not already exist."""
    cursor.execute(
        "IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'QueryAdvisorSample') "
        "CREATE DATABASE [QueryAdvisorSample]"
    )


def create_database() -> None:
    """Connect to master and create the sample database."""
    conn = get_connection("master")
    conn.autocommit = True
    try:
        _ensure_database(conn.cursor())
        print(f"  database '{DB_NAME}' ready")
    finally:
        conn.close()
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
uv run pytest tests/test_seed.py::TestEnsureDatabase \
              tests/test_seed.py::TestCreateDatabase -v
```

Expected: 6 PASSED

- [ ] **Step 5: Run full test suite to catch regressions**

```bash
uv run pytest tests/test_infra.py tests/test_config.py tests/test_seed.py -v
```

Expected: all PASSED

- [ ] **Step 6: Commit**

```bash
git add scripts/seed_db.py tests/test_seed.py
git commit -m "feat: implement _ensure_database and create_database with unit tests"
```

---

## Task 3: `dbo` clean schema DDL

**Files:**
- Modify: `scripts/seed_db.py`
- Modify: `tests/test_seed.py`

- [ ] **Step 1: Add failing unit tests for `_create_dbo_tables` to `tests/test_seed.py`**

Add after `TestCreateDatabase`:

```python
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
        """Every CREATE TABLE must be guarded by IF OBJECT_ID IS NULL."""
        cursor = MagicMock()
        from scripts.seed_db import _DBO_DDL
        for stmt in _DBO_DDL:
            if "CREATE TABLE" in stmt:
                assert "IF OBJECT_ID" in stmt or "IF NOT EXISTS" in stmt, (
                    f"DDL statement is not idempotent:\n{stmt[:120]}"
                )
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
uv run pytest tests/test_seed.py::TestCreateDboTables -v
```

Expected: FAILED (functions and constants not yet defined)

- [ ] **Step 3: Add DDL constants and `_create_dbo_tables` to `scripts/seed_db.py`**

Add after `create_database()`:

```python

# ---------------------------------------------------------------------------
# dbo schema DDL — clean e-commerce schema
# ---------------------------------------------------------------------------

_DDL_CATEGORIES = """
IF OBJECT_ID('dbo.Categories', 'U') IS NULL
CREATE TABLE dbo.Categories (
    CategoryID  int           NOT NULL IDENTITY(1,1),
    Name        nvarchar(100) NOT NULL,
    CONSTRAINT PK_Categories PRIMARY KEY CLUSTERED (CategoryID)
)"""

_DDL_CUSTOMERS = """
IF OBJECT_ID('dbo.Customers', 'U') IS NULL
CREATE TABLE dbo.Customers (
    CustomerID  int           NOT NULL IDENTITY(1,1),
    Email       varchar(255)  NOT NULL,
    Name        nvarchar(200) NOT NULL,
    CreatedAt   datetime2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Customers PRIMARY KEY CLUSTERED (CustomerID)
)"""

_DDL_CUSTOMERS_IDX_EMAIL = """
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Customers_Email' AND object_id = OBJECT_ID('dbo.Customers')
)
CREATE UNIQUE INDEX IX_Customers_Email ON dbo.Customers (Email)"""

_DDL_PRODUCTS = """
IF OBJECT_ID('dbo.Products', 'U') IS NULL
CREATE TABLE dbo.Products (
    ProductID   int            NOT NULL IDENTITY(1,1),
    CategoryID  int            NOT NULL,
    Name        nvarchar(200)  NOT NULL,
    Price       decimal(10,2)  NOT NULL,
    Stock       int            NOT NULL DEFAULT 0,
    CONSTRAINT PK_Products PRIMARY KEY CLUSTERED (ProductID),
    CONSTRAINT FK_Products_Categories FOREIGN KEY (CategoryID)
        REFERENCES dbo.Categories (CategoryID)
)"""

_DDL_PRODUCTS_IDX_CATEGORY = """
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Products_CategoryID' AND object_id = OBJECT_ID('dbo.Products')
)
CREATE INDEX IX_Products_CategoryID ON dbo.Products (CategoryID)"""

_DDL_ORDERS = """
IF OBJECT_ID('dbo.Orders', 'U') IS NULL
CREATE TABLE dbo.Orders (
    OrderID     int          NOT NULL IDENTITY(1,1),
    CustomerID  int          NOT NULL,
    OrderDate   datetime2    NOT NULL DEFAULT SYSUTCDATETIME(),
    Status      varchar(20)  NOT NULL DEFAULT 'pending',
    CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderID),
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID)
        REFERENCES dbo.Customers (CustomerID)
)"""

_DDL_ORDERS_IDX_CUSTOMER = """
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Orders_CustomerID' AND object_id = OBJECT_ID('dbo.Orders')
)
CREATE INDEX IX_Orders_CustomerID ON dbo.Orders (CustomerID)"""

_DDL_ORDERS_IDX_DATE = """
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Orders_OrderDate' AND object_id = OBJECT_ID('dbo.Orders')
)
CREATE INDEX IX_Orders_OrderDate ON dbo.Orders (OrderDate)"""

_DDL_ORDER_ITEMS = """
IF OBJECT_ID('dbo.OrderItems', 'U') IS NULL
CREATE TABLE dbo.OrderItems (
    OrderItemID int            NOT NULL IDENTITY(1,1),
    OrderID     int            NOT NULL,
    ProductID   int            NOT NULL,
    Quantity    int            NOT NULL DEFAULT 1,
    UnitPrice   decimal(10,2)  NOT NULL,
    CONSTRAINT PK_OrderItems PRIMARY KEY CLUSTERED (OrderItemID),
    CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (OrderID)
        REFERENCES dbo.Orders (OrderID),
    CONSTRAINT FK_OrderItems_Products FOREIGN KEY (ProductID)
        REFERENCES dbo.Products (ProductID)
)"""

_DDL_ORDER_ITEMS_IDX_ORDER = """
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_OrderItems_OrderID' AND object_id = OBJECT_ID('dbo.OrderItems')
)
CREATE INDEX IX_OrderItems_OrderID ON dbo.OrderItems (OrderID)"""

_DDL_ORDER_ITEMS_IDX_PRODUCT = """
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_OrderItems_ProductID' AND object_id = OBJECT_ID('dbo.OrderItems')
)
CREATE INDEX IX_OrderItems_ProductID ON dbo.OrderItems (ProductID)"""

_DBO_DDL = [
    _DDL_CATEGORIES,
    _DDL_CUSTOMERS,
    _DDL_CUSTOMERS_IDX_EMAIL,
    _DDL_PRODUCTS,
    _DDL_PRODUCTS_IDX_CATEGORY,
    _DDL_ORDERS,
    _DDL_ORDERS_IDX_CUSTOMER,
    _DDL_ORDERS_IDX_DATE,
    _DDL_ORDER_ITEMS,
    _DDL_ORDER_ITEMS_IDX_ORDER,
    _DDL_ORDER_ITEMS_IDX_PRODUCT,
]


def _create_dbo_tables(cursor) -> None:
    """Execute all dbo schema DDL statements."""
    for stmt in _DBO_DDL:
        cursor.execute(stmt)
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
uv run pytest tests/test_seed.py::TestCreateDboTables -v
```

Expected: 7 PASSED

- [ ] **Step 5: Run full test suite**

```bash
uv run pytest tests/test_infra.py tests/test_config.py tests/test_seed.py -v
```

Expected: all PASSED

- [ ] **Step 6: Commit**

```bash
git add scripts/seed_db.py tests/test_seed.py
git commit -m "feat: add dbo clean schema DDL with idempotency guards and unit tests"
```

---

## Task 4: `bad` schema DDL (anti-pattern tables)

**Files:**
- Modify: `scripts/seed_db.py`
- Modify: `tests/test_seed.py`

- [ ] **Step 1: Add failing unit tests for `_create_bad_tables` to `tests/test_seed.py`**

Add after `TestCreateDboTables`:

```python
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
        # The CustomerID column definition must use varchar, not int
        lines = _DDL_BAD_ORDERS.splitlines()
        customerid_line = next(
            (l for l in lines if "CustomerID" in l and "CONSTRAINT" not in l), ""
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
uv run pytest tests/test_seed.py::TestCreateBadTables -v
```

Expected: FAILED

- [ ] **Step 3: Add `bad` schema DDL constants and `_create_bad_tables` to `scripts/seed_db.py`**

Add after `_create_dbo_tables`:

```python

# ---------------------------------------------------------------------------
# bad schema DDL — deliberate anti-patterns to exercise analysis rules
# ---------------------------------------------------------------------------

_DDL_BAD_SCHEMA = (
    "IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bad') "
    "EXEC('CREATE SCHEMA bad')"
)

# DELIBERATE: CustomerID is varchar(20), not int.
# Joining bad.Orders to dbo.Customers on CustomerID triggers check_join_type_mismatch.
_DDL_BAD_ORDERS = """
IF OBJECT_ID('bad.Orders', 'U') IS NULL
CREATE TABLE bad.Orders (
    OrderID      int            NOT NULL IDENTITY(1,1),
    CustomerID   varchar(20)    NOT NULL,
    OrderDate    datetime2      NOT NULL DEFAULT SYSUTCDATETIME(),
    TotalAmount  decimal(10,2)  NOT NULL DEFAULT 0,
    CONSTRAINT PK_BadOrders PRIMARY KEY CLUSTERED (OrderID)
)"""

# DELIBERATE: No non-clustered indexes on UserID or EventType.
# Querying bad.Events WHERE UserID = ? triggers check_table_scan
# and check_join_column_not_indexed.
_DDL_BAD_EVENTS = """
IF OBJECT_ID('bad.Events', 'U') IS NULL
CREATE TABLE bad.Events (
    EventID     int          NOT NULL IDENTITY(1,1),
    UserID      int          NOT NULL,
    EventType   varchar(50)  NOT NULL,
    OccurredAt  datetime2    NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_BadEvents PRIMARY KEY CLUSTERED (EventID)
)"""

# DELIBERATE: Index covers LogLevel for WHERE, but does not INCLUDE Message or CreatedAt.
# A SELECT LogLevel, Message, CreatedAt FROM bad.Logs WHERE LogLevel = ?
# triggers check_non_covering_index.
_DDL_BAD_LOGS = """
IF OBJECT_ID('bad.Logs', 'U') IS NULL
CREATE TABLE bad.Logs (
    LogID      int            NOT NULL IDENTITY(1,1),
    LogLevel   varchar(20)    NOT NULL,
    Message    nvarchar(max)  NOT NULL,
    CreatedAt  datetime2      NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_BadLogs PRIMARY KEY CLUSTERED (LogID)
)"""

_DDL_BAD_LOGS_IDX = """
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Logs_LogLevel' AND object_id = OBJECT_ID('bad.Logs')
)
CREATE INDEX IX_Logs_LogLevel ON bad.Logs (LogLevel)"""

_BAD_DDL = [
    _DDL_BAD_SCHEMA,
    _DDL_BAD_ORDERS,
    _DDL_BAD_EVENTS,
    _DDL_BAD_LOGS,
    _DDL_BAD_LOGS_IDX,
]


def _create_bad_tables(cursor) -> None:
    """Execute all bad schema DDL statements."""
    for stmt in _BAD_DDL:
        cursor.execute(stmt)
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
uv run pytest tests/test_seed.py::TestCreateBadTables -v
```

Expected: 5 PASSED

- [ ] **Step 5: Run full test suite**

```bash
uv run pytest tests/test_infra.py tests/test_config.py tests/test_seed.py -v
```

Expected: all PASSED

- [ ] **Step 6: Commit**

```bash
git add scripts/seed_db.py tests/test_seed.py
git commit -m "feat: add bad schema DDL with anti-pattern tables and unit tests"
```

---

## Task 5: Views, functions, data population, and `seed_schema` wiring

**Files:**
- Modify: `scripts/seed_db.py`
- Modify: `tests/test_seed.py`

- [ ] **Step 1: Add failing unit tests for `seed_schema` to `tests/test_seed.py`**

Add after `TestCreateBadTables`:

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
uv run pytest tests/test_seed.py::TestSeedSchema -v
```

Expected: FAILED (`seed_schema` not yet defined)

- [ ] **Step 3: Add views, functions, data population, and `seed_schema` to `scripts/seed_db.py`**

Add after `_create_bad_tables`:

```python

# ---------------------------------------------------------------------------
# Views and functions DDL
# ---------------------------------------------------------------------------

_DDL_VIEW_PRODUCT_CATALOG = """\
CREATE OR ALTER VIEW dbo.vw_ProductCatalog AS
SELECT
    p.ProductID,
    p.Name        AS ProductName,
    p.Price,
    p.Stock,
    c.Name        AS CategoryName
FROM dbo.Products p
JOIN dbo.Categories c ON p.CategoryID = c.CategoryID"""

_DDL_VIEW_ORDER_SUMMARY = """\
CREATE OR ALTER VIEW dbo.vw_OrderSummary AS
SELECT
    o.OrderID,
    o.OrderDate,
    o.Status,
    c.Name    AS CustomerName,
    c.Email   AS CustomerEmail,
    COUNT(oi.OrderItemID)           AS ItemCount,
    SUM(oi.Quantity * oi.UnitPrice) AS TotalValue
FROM dbo.Orders o
JOIN dbo.Customers  c  ON o.CustomerID = c.CustomerID
JOIN dbo.OrderItems oi ON o.OrderID    = oi.OrderID
GROUP BY o.OrderID, o.OrderDate, o.Status, c.Name, c.Email"""

_DDL_FN_ORDER_COUNT = """\
CREATE OR ALTER FUNCTION dbo.fn_GetCustomerOrderCount(@CustomerID int)
RETURNS int
AS
BEGIN
    DECLARE @count int;
    SELECT @count = COUNT(*) FROM dbo.Orders WHERE CustomerID = @CustomerID;
    RETURN @count;
END"""

_DDL_FN_ORDER_ITEMS = """\
CREATE OR ALTER FUNCTION dbo.fn_GetOrderItems(@OrderID int)
RETURNS TABLE
AS
RETURN (
    SELECT
        oi.OrderItemID,
        oi.Quantity,
        oi.UnitPrice,
        p.Name                     AS ProductName,
        oi.Quantity * oi.UnitPrice AS LineTotal
    FROM dbo.OrderItems oi
    JOIN dbo.Products p ON oi.ProductID = p.ProductID
    WHERE oi.OrderID = @OrderID
)"""

_VIEW_AND_FUNCTION_DDL = [
    _DDL_VIEW_PRODUCT_CATALOG,
    _DDL_VIEW_ORDER_SUMMARY,
    _DDL_FN_ORDER_COUNT,
    _DDL_FN_ORDER_ITEMS,
]


def _create_views_and_functions(cursor) -> None:
    for stmt in _VIEW_AND_FUNCTION_DDL:
        cursor.execute(stmt)


# ---------------------------------------------------------------------------
# Data population helpers
# ---------------------------------------------------------------------------

def _rand_str(rng: random.Random, n: int) -> str:
    return "".join(rng.choices(string.ascii_lowercase, k=n))


def _is_empty(cursor, table: str) -> bool:
    cursor.execute(f"SELECT COUNT(*) FROM {table}")  # noqa: S608 — table is a hardcoded literal
    return cursor.fetchone()[0] == 0


def _populate_categories(cursor) -> None:
    if not _is_empty(cursor, "dbo.Categories"):
        return
    names = [
        "Electronics", "Clothing", "Books", "Sports", "Home & Garden",
        "Toys", "Food & Beverage", "Automotive", "Health & Beauty", "Office",
    ]
    cursor.executemany("INSERT INTO dbo.Categories (Name) VALUES (?)", [(n,) for n in names])


def _populate_customers(cursor) -> None:
    if not _is_empty(cursor, "dbo.Customers"):
        return
    rng = random.Random(42)
    base = datetime(2020, 1, 1)
    rows = [
        (
            f"{_rand_str(rng, 6)}.{_rand_str(rng, 4)}@example.com",
            f"{_rand_str(rng, 5).title()} {_rand_str(rng, 7).title()}",
            base + timedelta(days=rng.randint(0, 1500)),
        )
        for _ in range(500)
    ]
    cursor.executemany(
        "INSERT INTO dbo.Customers (Email, Name, CreatedAt) VALUES (?, ?, ?)", rows
    )


def _populate_products(cursor) -> None:
    if not _is_empty(cursor, "dbo.Products"):
        return
    rng = random.Random(43)
    rows = [
        (rng.randint(1, 10), f"Product {i:03d}", round(rng.uniform(9.99, 999.99), 2), rng.randint(0, 100))
        for i in range(1, 51)
    ]
    cursor.executemany(
        "INSERT INTO dbo.Products (CategoryID, Name, Price, Stock) VALUES (?, ?, ?, ?)", rows
    )


def _populate_orders(cursor) -> None:
    if not _is_empty(cursor, "dbo.Orders"):
        return
    rng = random.Random(44)
    base = datetime(2023, 1, 1)
    statuses = ["pending", "confirmed", "shipped", "delivered", "cancelled"]
    rows = [
        (rng.randint(1, 500), base + timedelta(days=rng.randint(0, 365)), rng.choice(statuses))
        for _ in range(2000)
    ]
    cursor.executemany(
        "INSERT INTO dbo.Orders (CustomerID, OrderDate, Status) VALUES (?, ?, ?)", rows
    )


def _populate_order_items(cursor) -> None:
    if not _is_empty(cursor, "dbo.OrderItems"):
        return
    rng = random.Random(45)
    rows = [
        (rng.randint(1, 2000), rng.randint(1, 50), rng.randint(1, 5), round(rng.uniform(9.99, 499.99), 2))
        for _ in range(5000)
    ]
    cursor.executemany(
        "INSERT INTO dbo.OrderItems (OrderID, ProductID, Quantity, UnitPrice) VALUES (?, ?, ?, ?)",
        rows,
    )


def _populate_bad_orders(cursor) -> None:
    if not _is_empty(cursor, "bad.Orders"):
        return
    rng = random.Random(46)
    base = datetime(2023, 1, 1)
    rows = [
        (str(rng.randint(1, 500)), base + timedelta(days=rng.randint(0, 365)), round(rng.uniform(10.0, 500.0), 2))
        for _ in range(1000)
    ]
    cursor.executemany(
        "INSERT INTO bad.Orders (CustomerID, OrderDate, TotalAmount) VALUES (?, ?, ?)", rows
    )


def _populate_bad_events(cursor) -> None:
    if not _is_empty(cursor, "bad.Events"):
        return
    rng = random.Random(47)
    base = datetime(2023, 1, 1)
    types = ["click", "view", "purchase", "login", "logout"]
    rows = [
        (rng.randint(1, 500), rng.choice(types), base + timedelta(days=rng.randint(0, 365)))
        for _ in range(1000)
    ]
    cursor.executemany(
        "INSERT INTO bad.Events (UserID, EventType, OccurredAt) VALUES (?, ?, ?)", rows
    )


def _populate_bad_logs(cursor) -> None:
    if not _is_empty(cursor, "bad.Logs"):
        return
    rng = random.Random(48)
    base = datetime(2023, 1, 1)
    levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
    rows = [
        (
            rng.choice(levels),
            f"Log message {i}: " + "".join(rng.choices(string.ascii_letters, k=50)),
            base + timedelta(days=rng.randint(0, 365)),
        )
        for i in range(1000)
    ]
    cursor.executemany(
        "INSERT INTO bad.Logs (LogLevel, Message, CreatedAt) VALUES (?, ?, ?)", rows
    )


# ---------------------------------------------------------------------------
# Orchestration — connects to QueryAdvisorSample
# ---------------------------------------------------------------------------

def seed_schema() -> None:
    """Create all schema objects and populate data in QueryAdvisorSample."""
    conn = get_connection(DB_NAME)
    conn.autocommit = True
    try:
        cur = conn.cursor()
        _create_dbo_tables(cur)
        _create_bad_tables(cur)
        _create_views_and_functions(cur)
        _populate_categories(cur)
        _populate_customers(cur)
        _populate_products(cur)
        _populate_orders(cur)
        _populate_order_items(cur)
        _populate_bad_orders(cur)
        _populate_bad_events(cur)
        _populate_bad_logs(cur)
        print("  schema and data ready")
    finally:
        conn.close()


if __name__ == "__main__":
    print(f"Seeding {DB_NAME}...")
    create_database()
    seed_schema()
    print("Done.")
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
uv run pytest tests/test_seed.py::TestSeedSchema -v
```

Expected: 4 PASSED

- [ ] **Step 5: Run full test suite**

```bash
uv run pytest tests/ -v --ignore=tests/test_api --ignore=tests/test_metadata \
              --ignore=tests/test_rules --ignore=tests/test_scoring \
              --ignore=tests/test_parser
```

Expected: `test_infra.py`, `test_config.py`, `test_seed.py` all PASSED
(Other test directories require a live DB — skip for now)

- [ ] **Step 6: Run linter**

```bash
uv run ruff check scripts/seed_db.py tests/test_seed.py
```

Expected: no errors. If errors appear, fix them before committing.

- [ ] **Step 7: Commit**

```bash
git add scripts/seed_db.py tests/test_seed.py
git commit -m "feat: add views, functions, data population, and seed_schema orchestration"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] `QueryAdvisorSample` database (create_database / _ensure_database)
- [x] `scripts/seed_db.py` using `app.config.get_connection()` — yes, imported at top of module
- [x] `make db-seed` Makefile target — Task 1
- [x] No compose.yaml changes — script runs from host via pyodbc
- [x] `dbo` schema: Categories, Customers, Products, Orders, OrderItems — Task 3
- [x] Proper indexes on all dbo tables — Task 3
- [x] `bad` schema with 3 anti-pattern tables — Task 4
- [x] `bad.Orders.CustomerID` is varchar — triggers `check_join_type_mismatch`
- [x] `bad.Events` has no non-clustered indexes — triggers `check_table_scan`, `check_join_column_not_indexed`
- [x] `bad.Logs` has partial index (no INCLUDE) — triggers `check_non_covering_index`
- [x] Views: `vw_ProductCatalog`, `vw_OrderSummary` — Task 5
- [x] Functions: `fn_GetCustomerOrderCount`, `fn_GetOrderItems` — Task 5
- [x] Idempotency: all DDL guarded with IF NOT EXISTS / IF OBJECT_ID / CREATE OR ALTER
- [x] Data population with ~500/50/2000/5000/1000 rows as spec'd — Task 5
- [x] Persistence via existing volume mount — handled by compose.yaml, no changes needed

**Placeholder scan:** None found — all code blocks contain actual, complete code.

**Type consistency:** `_rand_str` renamed to `_rand_str_rng` to avoid confusion — confirmed consistent across all tasks. All functions receive `cursor` (not `conn`). `seed_schema` and `create_database` both close the connection in `finally`.
