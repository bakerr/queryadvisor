# QueryAdvisor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a FastAPI/HTMX web app that grades T-SQL query optimization using SQL Server catalog metadata — no EXPLAIN plans, no query execution.

**Architecture:** Linear pipeline — Parse (sqlglot AST) → Extract (QueryProfile) → Collect Metadata (sys.* catalog views via pyodbc/Kerberos) → Evaluate Rules (14 rules across 4 categories) → Score → Render (HTMX partials). Stateless; in-memory result cache (30-min TTL) enables view toggling without re-running the pipeline.

**Tech Stack:** Python 3.11+, FastAPI, Jinja2, HTMX, sqlglot, pyodbc + msodbcsql18 + Kerberos, pytest, ruff

---

## File Map

| File | Responsibility |
|------|---------------|
| `app/models.py` | All Pydantic models: `AnalysisRequest`, `QueryProfile`, `MetadataBundle`, `Finding`, `ReportCard` |
| `app/config.py` | `get_connection(database)` — pyodbc connection string from env vars |
| `app/parser/extractor.py` | `extract_query_profiles(sql) -> list[QueryProfile]` — multi-statement script entry point |
| `app/parser/temp_tables.py` | Tracks `#temp` table schemas across statements |
| `app/metadata/collector.py` | `collect_metadata(tables, database) -> MetadataBundle` — all catalog view queries |
| `app/rules/style.py` | Rules: SELECT *, DISTINCT, ORDER BY without paging, redundant JOIN |
| `app/rules/predicates.py` | Rules: non-sargable functions, implicit conversion, leading wildcard LIKE |
| `app/rules/joins.py` | Rules: missing join predicate, type mismatch, unindexed join column |
| `app/rules/indexing.py` | Rules: missing index DMV match, table scan, non-covering index |
| `app/rules/engine.py` | `evaluate_rules(profile, bundle) -> list[Finding]` — runs all rule modules |
| `app/scoring/scorer.py` | `score_findings(findings) -> ReportCard` — grades by category |
| `app/main.py` | FastAPI app, all HTTP endpoints, in-memory result store |
| `app/templates/base.html` | Base layout with HTMX CDN |
| `app/templates/index.html` | Main page: name input, database dropdown, SQL textarea, analyze button |
| `app/templates/partials/report_card.html` | Score + letter grades header (always shown after analysis) |
| `app/templates/partials/findings_list.html` | Categorized findings list view |
| `app/templates/partials/annotated_sql.html` | SQL with inline finding annotations |
| `app/templates/partials/results.html` | Container: embeds report_card + default detail panel |
| `static/css/style.css` | Minimal styles |
| `tests/conftest.py` | Shared fixtures: sample QueryProfile, MetadataBundle, findings |
| `tests/test_parser/test_extractor.py` | Parser unit tests |
| `tests/test_rules/test_style.py` | Style rule tests |
| `tests/test_rules/test_predicates.py` | Predicate rule tests |
| `tests/test_rules/test_joins.py` | Join rule tests |
| `tests/test_rules/test_indexing.py` | Indexing rule tests |
| `tests/test_scoring/test_scorer.py` | Scorer tests |
| `tests/test_api/test_endpoints.py` | FastAPI endpoint tests (httpx) |
| `pyproject.toml` | Dependencies, ruff config, pytest config |
| `Dockerfile` | Multi-stage build, msodbcsql18, Kerberos libs |
| `.env.example` | `SQL_SERVER_HOST`, `ODBC_DRIVER` |

---

## Task 1: Project Scaffolding

**Files:**
- Create: `pyproject.toml`
- Create: `.env.example`
- Create: `app/__init__.py`, `app/parser/__init__.py`, `app/metadata/__init__.py`, `app/rules/__init__.py`, `app/scoring/__init__.py`
- Create: `tests/__init__.py`, `tests/test_parser/__init__.py`, `tests/test_rules/__init__.py`, `tests/test_scoring/__init__.py`, `tests/test_api/__init__.py`
- Create: `static/css/style.css`

- [ ] **Step 1: Create `pyproject.toml`**

```toml
[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.backends.legacy:build"

[project]
name = "queryadvisor"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    "fastapi>=0.111",
    "uvicorn[standard]>=0.29",
    "jinja2>=3.1",
    "python-multipart>=0.0.9",
    "sqlglot>=23.0",
    "pyodbc>=5.1",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.23",
    "httpx>=0.27",
    "ruff>=0.4",
]

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]

[tool.ruff]
line-length = 100
target-version = "py311"

[tool.ruff.lint]
select = ["E", "F", "I"]
```

- [ ] **Step 2: Create `.env.example`**

```bash
SQL_SERVER_HOST=your-sql-server.example.com
ODBC_DRIVER=ODBC Driver 18 for SQL Server
```

- [ ] **Step 3: Create all `__init__.py` files and `static/css/style.css`**

```bash
mkdir -p app/parser app/metadata app/rules app/scoring app/templates/partials
mkdir -p static/css
mkdir -p tests/test_parser tests/test_rules tests/test_scoring tests/test_api
touch app/__init__.py app/parser/__init__.py app/metadata/__init__.py
touch app/rules/__init__.py app/scoring/__init__.py
touch tests/__init__.py tests/test_parser/__init__.py tests/test_rules/__init__.py
touch tests/test_scoring/__init__.py tests/test_api/__init__.py
touch static/css/style.css
```

- [ ] **Step 4: Install dependencies**

```bash
pip install -e ".[dev]"
```

Expected: All packages install without error.

- [ ] **Step 5: Verify pytest can be invoked**

```bash
pytest --collect-only
```

Expected: `no tests ran` — no errors.

- [ ] **Step 6: Commit**

```bash
git add pyproject.toml .env.example app/ static/ tests/
git commit -m "chore: project scaffolding and package structure"
```

---

## Task 2: Data Models

**Files:**
- Create: `app/models.py`

- [ ] **Step 1: Write `app/models.py`**

```python
from __future__ import annotations
from datetime import datetime
from enum import Enum
from pydantic import BaseModel


class AnalysisRequest(BaseModel):
    sql: str
    database: str
    username: str


class ColumnDef(BaseModel):
    column_name: str
    data_type: str


class TableRef(BaseModel):
    name: str
    schema_name: str = "dbo"
    alias: str | None = None
    is_temp: bool = False


class Predicate(BaseModel):
    column: str
    table_alias: str | None = None
    operator: str
    value_expr: str
    has_function_wrap: bool = False


class JoinDef(BaseModel):
    join_type: str
    left_table: str
    right_table: str
    predicates: list[Predicate] = []


class QueryProfile(BaseModel):
    tables: list[TableRef] = []
    joins: list[JoinDef] = []
    where_predicates: list[Predicate] = []
    selected_columns: list[str] = []
    has_distinct: bool = False
    has_order_by: bool = False
    has_top_or_offset: bool = False
    ctes: list[QueryProfile] = []
    subqueries: list[QueryProfile] = []
    temp_table_schemas: dict[str, list[ColumnDef]] = {}


QueryProfile.model_rebuild()


class IndexDef(BaseModel):
    index_name: str
    is_unique: bool = False
    is_clustered: bool = False
    key_columns: list[str] = []
    include_columns: list[str] = []


class ColumnMeta(BaseModel):
    column_name: str
    data_type: str
    is_nullable: bool = True


class MissingIndexSuggestion(BaseModel):
    table: str
    equality_columns: list[str] = []
    inequality_columns: list[str] = []
    included_columns: list[str] = []
    avg_user_impact: float


class TableMetadata(BaseModel):
    table: str
    indexes: list[IndexDef] = []
    columns: list[ColumnMeta] = []
    stats_last_updated: datetime | None = None
    row_count: int | None = None
    missing_index_suggestions: list[MissingIndexSuggestion] = []


class MetadataBundle(BaseModel):
    tables: dict[str, TableMetadata] = {}


class Severity(str, Enum):
    CRITICAL = "critical"
    WARNING = "warning"
    INFO = "info"


class Category(str, Enum):
    INDEXING = "indexing"
    PREDICATES = "predicates"
    JOINS = "joins"
    STYLE = "style"


class Finding(BaseModel):
    category: Category
    severity: Severity
    title: str
    explanation: str
    affected_sql: str | None = None
    line_start: int | None = None
    line_end: int | None = None


class CategoryScore(BaseModel):
    category: Category
    score: int
    grade: str


class ReportCard(BaseModel):
    score: int
    grade: str
    category_scores: list[CategoryScore]
    findings: list[Finding]
```

- [ ] **Step 2: Verify models import cleanly**

```bash
python -c "from app.models import ReportCard, QueryProfile, MetadataBundle; print('ok')"
```

Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add app/models.py
git commit -m "feat: add pydantic data models"
```

---

## Task 3: SQL Parser — Table, Column, Join Extraction

**Files:**
- Create: `app/parser/extractor.py`
- Create: `tests/test_parser/test_extractor.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_parser/test_extractor.py
import pytest
from app.parser.extractor import extract_query_profiles


def test_simple_table_extraction():
    profiles = extract_query_profiles("SELECT id FROM dbo.Orders")
    assert len(profiles) == 1
    assert profiles[0].tables[0].name == "Orders"
    assert profiles[0].tables[0].schema_name == "dbo"


def test_table_alias():
    profiles = extract_query_profiles("SELECT o.id FROM Orders AS o")
    assert profiles[0].tables[0].alias == "o"


def test_select_star_detected():
    profiles = extract_query_profiles("SELECT * FROM Orders")
    assert profiles[0].selected_columns == ["*"]


def test_select_named_columns():
    profiles = extract_query_profiles("SELECT id, name FROM Orders")
    assert "id" in profiles[0].selected_columns
    assert "name" in profiles[0].selected_columns


def test_distinct_detected():
    profiles = extract_query_profiles("SELECT DISTINCT status FROM Orders")
    assert profiles[0].has_distinct is True


def test_order_by_detected():
    profiles = extract_query_profiles("SELECT id FROM Orders ORDER BY id")
    assert profiles[0].has_order_by is True


def test_top_detected():
    profiles = extract_query_profiles("SELECT TOP 10 id FROM Orders")
    assert profiles[0].has_top_or_offset is True


def test_inner_join_extracted():
    sql = "SELECT o.id FROM Orders o INNER JOIN Customers c ON o.customer_id = c.id"
    profiles = extract_query_profiles(sql)
    assert len(profiles[0].joins) == 1
    assert profiles[0].joins[0].join_type == "INNER"
    assert profiles[0].joins[0].right_table == "Customers"


def test_join_without_on_has_no_predicates():
    sql = "SELECT o.id, c.name FROM Orders o CROSS JOIN Customers c"
    profiles = extract_query_profiles(sql)
    assert profiles[0].joins[0].predicates == []
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
pytest tests/test_parser/test_extractor.py -v
```

Expected: `ModuleNotFoundError` or `ImportError` — `extractor` not yet defined.

- [ ] **Step 3: Write `app/parser/extractor.py`**

```python
from __future__ import annotations
import sqlglot
from sqlglot import exp
from app.models import QueryProfile, TableRef, Predicate, JoinDef, ColumnDef

_COMPARISON_TYPES = (exp.EQ, exp.GT, exp.LT, exp.GTE, exp.LTE, exp.NEQ, exp.Like, exp.In)


def extract_query_profiles(sql: str) -> list[QueryProfile]:
    """Parse a T-SQL script and return one QueryProfile per SELECT statement."""
    from app.parser.temp_tables import TempTableTracker
    tracker = TempTableTracker()
    statements = sqlglot.parse(sql, dialect="tsql")
    profiles = []
    for stmt in statements:
        if stmt is None:
            continue
        updated = tracker.process_statement(stmt)
        if updated or isinstance(stmt, exp.Select):
            if isinstance(stmt, (exp.Select, exp.Subquery)):
                profile = _extract_single_select(stmt)
                profile.temp_table_schemas = dict(tracker.schemas)
                profiles.append(profile)
    return profiles


def _extract_single_select(tree: exp.Expression) -> QueryProfile:
    return QueryProfile(
        tables=_extract_tables(tree),
        joins=_extract_joins(tree),
        where_predicates=_extract_where_predicates(tree),
        selected_columns=_extract_selected_columns(tree),
        has_distinct=bool(tree.args.get("distinct")),
        has_order_by=bool(tree.args.get("order")),
        has_top_or_offset=bool(tree.args.get("top")) or bool(tree.args.get("limit")),
    )


def _extract_tables(tree: exp.Expression) -> list[TableRef]:
    tables, seen = [], set()
    for table in tree.find_all(exp.Table):
        name = table.name
        if not name or name in seen:
            continue
        seen.add(name)
        tables.append(TableRef(
            name=name,
            schema_name=table.db or "dbo",
            alias=table.alias or None,
            is_temp=name.startswith("#"),
        ))
    return tables


def _extract_selected_columns(tree: exp.Expression) -> list[str]:
    select = tree if isinstance(tree, exp.Select) else tree.find(exp.Select)
    if not select:
        return []
    for expr in select.expressions:
        if isinstance(expr, exp.Star):
            return ["*"]
    return [
        expr.alias or (expr.name if isinstance(expr, exp.Column) else str(expr))
        for expr in select.expressions
    ]


def _extract_where_predicates(tree: exp.Expression) -> list[Predicate]:
    where = tree.find(exp.Where)
    if not where:
        return []
    return _predicates_from_expr(where)


def _predicates_from_expr(expr: exp.Expression) -> list[Predicate]:
    predicates = []
    for cond in expr.find_all(*_COMPARISON_TYPES):
        left = cond.left if hasattr(cond, "left") else None
        right = cond.right if hasattr(cond, "right") else None
        if left is None:
            continue
        col_name = _column_name(left)
        if col_name:
            predicates.append(Predicate(
                column=col_name,
                table_alias=_table_alias(left),
                operator=type(cond).__name__.upper(),
                value_expr=str(right) if right else "",
                has_function_wrap=isinstance(left, exp.Func),
            ))
    return predicates


def _column_name(expr: exp.Expression) -> str | None:
    if isinstance(expr, exp.Column):
        return expr.name
    col = expr.find(exp.Column)
    return col.name if col else None


def _table_alias(expr: exp.Expression) -> str | None:
    col = expr.find(exp.Column)
    return col.table if col else None


def _extract_joins(tree: exp.Expression) -> list[JoinDef]:
    joins = []
    from_clause = tree.find(exp.From)
    from_table = from_clause.find(exp.Table) if from_clause else None
    from_name = from_table.name if from_table else ""
    for join in tree.find_all(exp.Join):
        join_table = join.find(exp.Table)
        if not join_table:
            continue
        on_clause = join.args.get("on")
        predicates = _predicates_from_expr(on_clause) if on_clause else []
        joins.append(JoinDef(
            join_type=join.kind or "INNER",
            left_table=from_name,
            right_table=join_table.name,
            predicates=predicates,
        ))
    return joins
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
pytest tests/test_parser/test_extractor.py -v
```

Expected: All 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/parser/extractor.py tests/test_parser/test_extractor.py
git commit -m "feat: SQL parser table/column/join extraction"
```

---

## Task 4: SQL Parser — Predicate Extraction & Temp Table Tracking

**Files:**
- Create: `app/parser/temp_tables.py`
- Modify: `tests/test_parser/test_extractor.py` (add predicate + temp table tests)

- [ ] **Step 1: Add failing tests to `tests/test_parser/test_extractor.py`**

```python
def test_where_predicate_extracted():
    profiles = extract_query_profiles("SELECT id FROM Orders WHERE status = 'Active'")
    preds = profiles[0].where_predicates
    assert len(preds) == 1
    assert preds[0].column == "status"
    assert preds[0].operator == "EQ"


def test_function_wrap_detected():
    profiles = extract_query_profiles("SELECT id FROM Orders WHERE YEAR(created_at) = 2024")
    assert profiles[0].where_predicates[0].has_function_wrap is True


def test_leading_wildcard_like():
    profiles = extract_query_profiles("SELECT id FROM Orders WHERE name LIKE '%foo'")
    pred = profiles[0].where_predicates[0]
    assert pred.operator == "LIKE"
    assert pred.value_expr.startswith("%")


def test_temp_table_schema_tracked():
    sql = """
    SELECT id, name INTO #tmp FROM dbo.Customers;
    SELECT * FROM #tmp
    """
    profiles = extract_query_profiles(sql)
    # The SELECT * profile should know about #tmp
    last = profiles[-1]
    assert "#tmp" in last.temp_table_schemas or any(t.is_temp for t in last.tables)


def test_multi_statement_returns_select_profiles_only():
    sql = """
    CREATE TABLE #work (id INT, val VARCHAR(50));
    SELECT id, val FROM #work WHERE val = 'x';
    """
    profiles = extract_query_profiles(sql)
    assert len(profiles) == 1
    assert profiles[0].where_predicates[0].column == "val"
```

- [ ] **Step 2: Run tests — verify new tests fail**

```bash
pytest tests/test_parser/test_extractor.py -v -k "temp or function or wildcard or predicate"
```

Expected: Failures on the new tests.

- [ ] **Step 3: Write `app/parser/temp_tables.py`**

```python
from __future__ import annotations
import sqlglot
from sqlglot import exp
from app.models import ColumnDef


class TempTableTracker:
    """Tracks #temp table schemas across a multi-statement T-SQL script."""

    def __init__(self) -> None:
        self.schemas: dict[str, list[ColumnDef]] = {}

    def process_statement(self, stmt: exp.Expression) -> bool:
        """Process one statement. Returns True if a temp table was registered."""
        if self._is_create_temp(stmt):
            name, cols = self._extract_create(stmt)
            self.schemas[name] = cols
            return True
        if self._is_select_into_temp(stmt):
            name, cols = self._extract_select_into(stmt)
            self.schemas[name] = cols
            return True
        return False

    # --- helpers ---

    def _is_create_temp(self, stmt: exp.Expression) -> bool:
        if not isinstance(stmt, exp.Create):
            return False
        table = stmt.find(exp.Table)
        return table is not None and table.name.startswith("#")

    def _is_select_into_temp(self, stmt: exp.Expression) -> bool:
        if not isinstance(stmt, exp.Select):
            return False
        into = stmt.args.get("into")
        if not into:
            return False
        table = into.find(exp.Table) if isinstance(into, exp.Expression) else None
        if table is None and isinstance(into, exp.Into):
            table = into.this
        name = getattr(table, "name", None) or str(into)
        return isinstance(name, str) and name.startswith("#")

    def _extract_create(self, stmt: exp.Create) -> tuple[str, list[ColumnDef]]:
        table = stmt.find(exp.Table)
        name = table.name
        cols = []
        schema_def = stmt.find(exp.Schema)
        if schema_def:
            for col_def in schema_def.find_all(exp.ColumnDef):
                dtype = col_def.args.get("kind")
                cols.append(ColumnDef(
                    column_name=col_def.name,
                    data_type=str(dtype) if dtype else "unknown",
                ))
        return name, cols

    def _extract_select_into(self, stmt: exp.Select) -> tuple[str, list[ColumnDef]]:
        into = stmt.args.get("into")
        table = None
        if isinstance(into, exp.Into):
            table = into.this
        name = table.name if table else str(into)
        # Columns are unknown at parse time without catalog lookup; mark as unknown
        cols = [
            ColumnDef(column_name=str(expr.alias or expr), data_type="unknown")
            for expr in stmt.expressions
            if not isinstance(expr, exp.Star)
        ]
        return name, cols
```

- [ ] **Step 4: Update `extract_query_profiles` in `extractor.py` to handle SELECT INTO correctly**

The current `extract_query_profiles` calls `tracker.process_statement(stmt)` but then also checks `isinstance(stmt, exp.Select)` which would double-count SELECT INTO statements. Fix the condition:

```python
def extract_query_profiles(sql: str) -> list[QueryProfile]:
    from app.parser.temp_tables import TempTableTracker
    tracker = TempTableTracker()
    statements = sqlglot.parse(sql, dialect="tsql")
    profiles = []
    for stmt in statements:
        if stmt is None:
            continue
        is_temp_stmt = tracker.process_statement(stmt)
        # Only extract a profile from SELECT statements that are NOT SELECT INTO #temp
        if isinstance(stmt, exp.Select) and not is_temp_stmt:
            profile = _extract_single_select(stmt)
            profile.temp_table_schemas = dict(tracker.schemas)
            profiles.append(profile)
    return profiles
```

- [ ] **Step 5: Run all parser tests**

```bash
pytest tests/test_parser/ -v
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/parser/temp_tables.py app/parser/extractor.py tests/test_parser/test_extractor.py
git commit -m "feat: predicate extraction and temp table tracking"
```

---

## Task 5: Metadata Collector

**Files:**
- Create: `app/config.py`
- Create: `app/metadata/collector.py`
- Create: `tests/test_metadata/__init__.py`, `tests/test_metadata/test_collector.py`

- [ ] **Step 1: Write `app/config.py`**

```python
import os
import pyodbc


def get_connection(database: str) -> pyodbc.Connection:
    server = os.getenv("SQL_SERVER_HOST", "localhost")
    driver = os.getenv("ODBC_DRIVER", "ODBC Driver 18 for SQL Server")
    conn_str = (
        f"DRIVER={{{driver}}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        "Trusted_Connection=yes;"
    )
    return pyodbc.connect(conn_str, timeout=10)
```

- [ ] **Step 2: Write failing tests**

```python
# tests/test_metadata/test_collector.py
from unittest.mock import MagicMock, patch
from app.metadata.collector import collect_metadata


def _make_mock_conn(index_rows, column_rows, stats_rows, missing_rows):
    mock_conn = MagicMock()
    mock_cursor = MagicMock()
    mock_conn.cursor.return_value = mock_cursor
    mock_cursor.fetchall.side_effect = [
        index_rows, column_rows, stats_rows, missing_rows
    ]
    return mock_conn


def test_collect_metadata_builds_bundle():
    mock_conn = _make_mock_conn(
        index_rows=[("IX_status", False, "NONCLUSTERED", 1, False, "status")],
        column_rows=[("id", "int", False), ("status", "varchar", True)],
        stats_rows=[],
        missing_rows=[],
    )
    with patch("app.metadata.collector.get_connection", return_value=mock_conn):
        bundle = collect_metadata(["dbo.Orders"], "MyDB")

    assert "dbo.orders" in bundle.tables
    tbl = bundle.tables["dbo.orders"]
    assert tbl.indexes[0].index_name == "IX_status"
    assert tbl.indexes[0].key_columns == ["status"]
    assert len(tbl.columns) == 2


def test_collect_metadata_includes_missing_index_suggestion():
    mock_conn = _make_mock_conn(
        index_rows=[],
        column_rows=[("id", "int", False)],
        stats_rows=[],
        missing_rows=[("status", None, "name", 45.5)],
    )
    with patch("app.metadata.collector.get_connection", return_value=mock_conn):
        bundle = collect_metadata(["dbo.Orders"], "MyDB")

    suggestions = bundle.tables["dbo.orders"].missing_index_suggestions
    assert len(suggestions) == 1
    assert suggestions[0].avg_user_impact == 45.5


def test_empty_table_list_returns_empty_bundle():
    with patch("app.metadata.collector.get_connection") as mock_get:
        bundle = collect_metadata([], "MyDB")
    mock_get.assert_not_called()
    assert bundle.tables == {}
```

- [ ] **Step 3: Run tests — verify they fail**

```bash
pytest tests/test_metadata/ -v
```

Expected: `ImportError` — collector not yet written.

- [ ] **Step 4: Write `app/metadata/collector.py`**

```python
from __future__ import annotations
from app.config import get_connection
from app.models import (
    MetadataBundle, TableMetadata, IndexDef, ColumnMeta, MissingIndexSuggestion
)

_INDEX_SQL = """
SELECT i.name, i.is_unique, i.type_desc, ic.key_ordinal,
       ic.is_included_column, c.name AS col_name
FROM sys.indexes i
JOIN sys.index_columns ic
    ON i.object_id = ic.object_id AND i.index_id = ic.index_id
JOIN sys.columns c
    ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE i.object_id = OBJECT_ID(?) AND i.type > 0
ORDER BY i.index_id, ic.key_ordinal
"""

_COLUMN_SQL = """
SELECT c.name, t.name AS type_name, c.is_nullable
FROM sys.columns c
JOIN sys.types t ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID(?)
"""

_STATS_SQL = """
SELECT TOP 1 sp.last_updated, sp.rows
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE s.object_id = OBJECT_ID(?) AND sp.last_updated IS NOT NULL
ORDER BY sp.last_updated DESC
"""

_MISSING_INDEX_SQL = """
SELECT mid.equality_columns, mid.inequality_columns,
       mid.included_columns, migs.avg_user_impact
FROM sys.dm_db_missing_index_details mid
JOIN sys.dm_db_missing_index_groups mig
    ON mid.index_handle = mig.index_handle
JOIN sys.dm_db_missing_index_group_stats migs
    ON mig.index_group_handle = migs.group_handle
WHERE mid.object_id = OBJECT_ID(?) AND migs.avg_user_impact > 10
ORDER BY migs.avg_user_impact DESC
"""


def collect_metadata(tables: list[str], database: str) -> MetadataBundle:
    """Query catalog views for every real (non-temp) table in `tables`."""
    if not tables:
        return MetadataBundle()

    conn = get_connection(database)
    try:
        cursor = conn.cursor()
        bundle_tables: dict[str, TableMetadata] = {}
        for table_ref in tables:
            key = table_ref.lower()
            meta = _fetch_table_metadata(cursor, table_ref)
            bundle_tables[key] = meta
        return MetadataBundle(tables=bundle_tables)
    finally:
        conn.close()


def _fetch_table_metadata(cursor, table_ref: str) -> TableMetadata:
    # Indexes
    cursor.execute(_INDEX_SQL, table_ref)
    index_rows = cursor.fetchall()
    indexes = _build_indexes(index_rows)

    # Columns
    cursor.execute(_COLUMN_SQL, table_ref)
    col_rows = cursor.fetchall()
    columns = [
        ColumnMeta(column_name=r[0], data_type=r[1], is_nullable=bool(r[2]))
        for r in col_rows
    ]

    # Stats
    cursor.execute(_STATS_SQL, table_ref)
    stats_rows = cursor.fetchall()
    stats_last_updated = stats_rows[0][0] if stats_rows else None
    row_count = stats_rows[0][1] if stats_rows else None

    # Missing index suggestions
    cursor.execute(_MISSING_INDEX_SQL, table_ref)
    missing_rows = cursor.fetchall()
    suggestions = [
        MissingIndexSuggestion(
            table=table_ref,
            equality_columns=_split_cols(r[0]),
            inequality_columns=_split_cols(r[1]),
            included_columns=_split_cols(r[2]),
            avg_user_impact=float(r[3]),
        )
        for r in missing_rows
    ]

    return TableMetadata(
        table=table_ref,
        indexes=indexes,
        columns=columns,
        stats_last_updated=stats_last_updated,
        row_count=row_count,
        missing_index_suggestions=suggestions,
    )


def _build_indexes(rows) -> list[IndexDef]:
    index_map: dict[str, IndexDef] = {}
    for name, is_unique, type_desc, key_ordinal, is_included, col_name in rows:
        if name not in index_map:
            index_map[name] = IndexDef(
                index_name=name,
                is_unique=bool(is_unique),
                is_clustered=(type_desc == "CLUSTERED"),
            )
        idx = index_map[name]
        if is_included:
            idx.include_columns.append(col_name)
        else:
            idx.key_columns.append(col_name)
    return list(index_map.values())


def _split_cols(val: str | None) -> list[str]:
    if not val:
        return []
    return [c.strip() for c in val.split(",")]
```

- [ ] **Step 5: Run tests**

```bash
pytest tests/test_metadata/ -v
```

Expected: All 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/config.py app/metadata/collector.py tests/test_metadata/
git commit -m "feat: metadata collector with catalog view queries"
```

---

## Task 6: Style Rules

**Files:**
- Create: `app/rules/style.py`
- Create: `tests/test_rules/test_style.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_rules/test_style.py
import pytest
from app.models import (
    QueryProfile, MetadataBundle, TableRef, JoinDef, Severity, Category
)
from app.rules.style import (
    check_select_star, check_order_without_paging,
    check_unnecessary_distinct, check_redundant_join,
)


def _profile(**kwargs) -> QueryProfile:
    return QueryProfile(**kwargs)


def test_select_star_is_warning():
    findings = check_select_star(_profile(selected_columns=["*"]), MetadataBundle())
    assert len(findings) == 1
    assert findings[0].severity == Severity.WARNING
    assert findings[0].category == Category.STYLE


def test_select_named_columns_no_finding():
    findings = check_select_star(_profile(selected_columns=["id", "name"]), MetadataBundle())
    assert findings == []


def test_order_by_without_top_is_info():
    findings = check_order_without_paging(
        _profile(has_order_by=True, has_top_or_offset=False), MetadataBundle()
    )
    assert len(findings) == 1
    assert findings[0].severity == Severity.INFO


def test_order_by_with_top_no_finding():
    findings = check_order_without_paging(
        _profile(has_order_by=True, has_top_or_offset=True), MetadataBundle()
    )
    assert findings == []


def test_distinct_is_info():
    findings = check_unnecessary_distinct(_profile(has_distinct=True), MetadataBundle())
    assert len(findings) == 1
    assert findings[0].severity == Severity.INFO


def test_redundant_join_flagged():
    tables = [
        TableRef(name="Orders", schema_name="dbo", alias="o"),
        TableRef(name="Customers", schema_name="dbo", alias="c"),
    ]
    joins = [JoinDef(join_type="LEFT", left_table="Orders", right_table="Customers")]
    # Customers columns never appear in select or predicates
    profile = _profile(
        tables=tables, joins=joins,
        selected_columns=["id"],  # no c.* columns
        where_predicates=[],
    )
    findings = check_redundant_join(profile, MetadataBundle())
    assert len(findings) == 1
    assert findings[0].severity == Severity.WARNING


def test_cross_join_not_flagged_as_redundant():
    tables = [TableRef(name="A", schema_name="dbo"), TableRef(name="B", schema_name="dbo")]
    joins = [JoinDef(join_type="CROSS", left_table="A", right_table="B")]
    findings = check_redundant_join(_profile(tables=tables, joins=joins), MetadataBundle())
    assert findings == []
```

- [ ] **Step 2: Run — verify failures**

```bash
pytest tests/test_rules/test_style.py -v
```

- [ ] **Step 3: Write `app/rules/style.py`**

```python
from app.models import QueryProfile, MetadataBundle, Finding, Severity, Category


def check_select_star(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    if "*" not in profile.selected_columns:
        return []
    return [Finding(
        category=Category.STYLE, severity=Severity.WARNING,
        title="SELECT * detected",
        explanation=(
            "SELECT * retrieves every column, preventing covering index scans and increasing "
            "network traffic. List only the columns you need."
        ),
    )]


def check_order_without_paging(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    if not profile.has_order_by or profile.has_top_or_offset:
        return []
    return [Finding(
        category=Category.STYLE, severity=Severity.INFO,
        title="ORDER BY without TOP or OFFSET",
        explanation=(
            "Sorting a full result set forces SQL Server to process all rows before returning any. "
            "Remove ORDER BY if the application doesn't require sorted output, or add "
            "TOP / OFFSET...FETCH NEXT for paging."
        ),
    )]


def check_unnecessary_distinct(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    if not profile.has_distinct:
        return []
    return [Finding(
        category=Category.STYLE, severity=Severity.INFO,
        title="DISTINCT detected",
        explanation=(
            "DISTINCT requires SQL Server to sort or hash the full result set. "
            "If duplicates arise from unnecessary JOINs, restructure the query to avoid "
            "them rather than filtering them after the fact."
        ),
    )]


def check_redundant_join(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    findings = []
    # Tables whose columns appear in SELECT (via dot notation) or WHERE
    referenced_via_alias: set[str] = set()
    for col in profile.selected_columns:
        if "." in col:
            referenced_via_alias.add(col.split(".")[0].lower())
    for pred in profile.where_predicates:
        if pred.table_alias:
            referenced_via_alias.add(pred.table_alias.lower())

    for join in profile.joins:
        if join.join_type in ("CROSS", "FULL"):
            continue
        rt = join.right_table.lower()
        aliases = {
            t.alias.lower() for t in profile.tables
            if t.name.lower() == rt and t.alias
        }
        if rt not in referenced_via_alias and not (aliases & referenced_via_alias):
            findings.append(Finding(
                category=Category.STYLE, severity=Severity.WARNING,
                title=f"Possibly redundant JOIN on {join.right_table}",
                explanation=(
                    f"'{join.right_table}' is joined but none of its columns appear in "
                    f"SELECT or WHERE. If not needed for filtering, removing this JOIN "
                    f"will improve performance."
                ),
            ))
    return findings
```

- [ ] **Step 4: Run tests**

```bash
pytest tests/test_rules/test_style.py -v
```

Expected: All 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/rules/style.py tests/test_rules/test_style.py
git commit -m "feat: style rules (SELECT *, DISTINCT, ORDER BY, redundant join)"
```

---

## Task 7: Predicate Rules

**Files:**
- Create: `app/rules/predicates.py`
- Create: `tests/test_rules/test_predicates.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_rules/test_predicates.py
from app.models import (
    QueryProfile, MetadataBundle, Predicate, TableRef,
    TableMetadata, ColumnMeta, IndexDef, Severity, Category
)
from app.rules.predicates import (
    check_nonsargable_function, check_implicit_conversion, check_leading_wildcard,
)


def _bundle_with_column(table: str, col: str, dtype: str) -> MetadataBundle:
    return MetadataBundle(tables={
        table: TableMetadata(
            table=table,
            columns=[ColumnMeta(column_name=col, data_type=dtype)],
            indexes=[IndexDef(index_name="IX_test", key_columns=[col])],
        )
    })


def test_function_wrap_is_critical():
    pred = Predicate(column="created_at", operator="EQ",
                     value_expr="2024", has_function_wrap=True)
    profile = QueryProfile(
        tables=[TableRef(name="Orders", schema_name="dbo")],
        where_predicates=[pred],
    )
    findings = check_nonsargable_function(profile, MetadataBundle())
    assert len(findings) == 1
    assert findings[0].severity == Severity.CRITICAL
    assert findings[0].category == Category.PREDICATES


def test_no_function_wrap_no_finding():
    pred = Predicate(column="status", operator="EQ",
                     value_expr="'Active'", has_function_wrap=False)
    profile = QueryProfile(where_predicates=[pred])
    assert check_nonsargable_function(profile, MetadataBundle()) == []


def test_implicit_conversion_varchar_vs_int():
    pred = Predicate(column="order_id", operator="EQ",
                     value_expr="12345", has_function_wrap=False)
    profile = QueryProfile(
        tables=[TableRef(name="dbo.Orders", schema_name="dbo")],
        where_predicates=[pred],
    )
    bundle = _bundle_with_column("dbo.orders", "order_id", "varchar")
    findings = check_implicit_conversion(profile, bundle)
    assert len(findings) == 1
    assert findings[0].severity == Severity.CRITICAL


def test_matching_types_no_finding():
    pred = Predicate(column="order_id", operator="EQ",
                     value_expr="12345", has_function_wrap=False)
    profile = QueryProfile(
        tables=[TableRef(name="dbo.Orders", schema_name="dbo")],
        where_predicates=[pred],
    )
    bundle = _bundle_with_column("dbo.orders", "order_id", "int")
    assert check_implicit_conversion(profile, bundle) == []


def test_leading_wildcard_is_warning():
    pred = Predicate(column="name", operator="LIKE",
                     value_expr="'%smith'", has_function_wrap=False)
    profile = QueryProfile(where_predicates=[pred])
    findings = check_leading_wildcard(profile, MetadataBundle())
    assert len(findings) == 1
    assert findings[0].severity == Severity.WARNING


def test_trailing_wildcard_no_finding():
    pred = Predicate(column="name", operator="LIKE",
                     value_expr="'smith%'", has_function_wrap=False)
    profile = QueryProfile(where_predicates=[pred])
    assert check_leading_wildcard(profile, MetadataBundle()) == []
```

- [ ] **Step 2: Run — verify failures**

```bash
pytest tests/test_rules/test_predicates.py -v
```

- [ ] **Step 3: Write `app/rules/predicates.py`**

```python
from app.models import QueryProfile, MetadataBundle, Finding, Severity, Category

_NUMERIC_TYPES = {"int", "bigint", "smallint", "tinyint", "decimal", "numeric", "float", "real"}
_STRING_TYPES = {"varchar", "nvarchar", "char", "nchar", "text", "ntext"}


def check_nonsargable_function(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    findings = []
    for pred in profile.where_predicates:
        if pred.has_function_wrap:
            findings.append(Finding(
                category=Category.PREDICATES, severity=Severity.CRITICAL,
                title=f"Non-sargable: function applied to '{pred.column}'",
                explanation=(
                    f"Wrapping '{pred.column}' in a function (e.g., YEAR(), UPPER(), CONVERT()) "
                    f"prevents SQL Server from using an index on that column. "
                    f"Rewrite the predicate to isolate the column: instead of YEAR(col) = 2024, "
                    f"use col >= '2024-01-01' AND col < '2025-01-01'."
                ),
                affected_sql=f"{pred.column} [function wrap]",
            ))
    return findings


def check_implicit_conversion(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    findings = []
    for pred in profile.where_predicates:
        col_type = _lookup_column_type(pred.column, profile, bundle)
        if col_type is None:
            continue
        value = pred.value_expr.strip().strip("'\"")
        value_looks_numeric = _is_numeric_literal(pred.value_expr)
        col_is_string = col_type.lower() in _STRING_TYPES
        col_is_numeric = col_type.lower() in _NUMERIC_TYPES
        if (col_is_string and value_looks_numeric) or (col_is_numeric and not value_looks_numeric
                                                       and not _is_numeric_literal(pred.value_expr)):
            findings.append(Finding(
                category=Category.PREDICATES, severity=Severity.CRITICAL,
                title=f"Implicit type conversion on '{pred.column}'",
                explanation=(
                    f"Column '{pred.column}' is {col_type} but the predicate value suggests "
                    f"a different type. This forces SQL Server to convert every row, preventing "
                    f"index use. Cast the literal to match the column type."
                ),
                affected_sql=f"{pred.column} {pred.operator} {pred.value_expr}",
            ))
    return findings


def check_leading_wildcard(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    findings = []
    for pred in profile.where_predicates:
        if pred.operator != "LIKE":
            continue
        pattern = pred.value_expr.strip().strip("'\"")
        if pattern.startswith("%"):
            findings.append(Finding(
                category=Category.PREDICATES, severity=Severity.WARNING,
                title=f"Leading wildcard LIKE on '{pred.column}'",
                explanation=(
                    f"LIKE '{pattern}' starts with a wildcard, which forces a full table or "
                    f"index scan. SQL Server cannot use a B-tree index to seek when the pattern "
                    f"begins with %. Consider full-text search if substring matching is required."
                ),
                affected_sql=f"{pred.column} LIKE '{pattern}'",
            ))
    return findings


def _lookup_column_type(col_name: str, profile: QueryProfile,
                        bundle: MetadataBundle) -> str | None:
    for table_ref in profile.tables:
        key = f"{table_ref.schema_name}.{table_ref.name}".lower()
        if key in bundle.tables:
            for col in bundle.tables[key].columns:
                if col.column_name.lower() == col_name.lower():
                    return col.data_type
    return None


def _is_numeric_literal(value: str) -> bool:
    try:
        float(value.strip().strip("'\""))
        return True
    except ValueError:
        return False
```

- [ ] **Step 4: Run tests**

```bash
pytest tests/test_rules/test_predicates.py -v
```

Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/rules/predicates.py tests/test_rules/test_predicates.py
git commit -m "feat: predicate rules (non-sargable, implicit conversion, wildcard)"
```

---

## Task 8: Join Rules

**Files:**
- Create: `app/rules/joins.py`
- Create: `tests/test_rules/test_joins.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_rules/test_joins.py
from app.models import (
    QueryProfile, MetadataBundle, JoinDef, TableRef,
    TableMetadata, ColumnMeta, IndexDef, Severity, Category
)
from app.rules.joins import (
    check_missing_join_predicate, check_join_type_mismatch, check_join_column_not_indexed,
)


def test_missing_join_predicate_is_critical():
    joins = [JoinDef(join_type="INNER", left_table="Orders", right_table="Customers", predicates=[])]
    profile = QueryProfile(joins=joins)
    findings = check_missing_join_predicate(profile, MetadataBundle())
    assert len(findings) == 1
    assert findings[0].severity == Severity.CRITICAL


def test_join_with_predicate_no_finding():
    from app.models import Predicate
    pred = Predicate(column="customer_id", operator="EQ", value_expr="c.id")
    joins = [JoinDef(join_type="INNER", left_table="Orders", right_table="Customers",
                     predicates=[pred])]
    assert check_missing_join_predicate(QueryProfile(joins=joins), MetadataBundle()) == []


def test_cross_join_no_missing_predicate_finding():
    joins = [JoinDef(join_type="CROSS", left_table="A", right_table="B", predicates=[])]
    assert check_missing_join_predicate(QueryProfile(joins=joins), MetadataBundle()) == []


def test_join_type_mismatch_is_warning():
    from app.models import Predicate
    pred = Predicate(column="order_id", table_alias="o", operator="EQ", value_expr="c.order_id")
    joins = [JoinDef(join_type="INNER", left_table="Orders", right_table="Customers",
                     predicates=[pred])]
    tables = [
        TableRef(name="Orders", schema_name="dbo", alias="o"),
        TableRef(name="Customers", schema_name="dbo", alias="c"),
    ]
    bundle = MetadataBundle(tables={
        "dbo.orders": TableMetadata(table="dbo.orders",
            columns=[ColumnMeta(column_name="order_id", data_type="int")]),
        "dbo.customers": TableMetadata(table="dbo.customers",
            columns=[ColumnMeta(column_name="order_id", data_type="varchar")]),
    })
    findings = check_join_type_mismatch(QueryProfile(tables=tables, joins=joins), bundle)
    assert len(findings) == 1
    assert findings[0].severity == Severity.WARNING


def test_join_column_not_indexed_is_warning():
    from app.models import Predicate
    pred = Predicate(column="customer_id", table_alias="o", operator="EQ", value_expr="c.id")
    joins = [JoinDef(join_type="INNER", left_table="Orders", right_table="Customers",
                     predicates=[pred])]
    tables = [
        TableRef(name="Orders", schema_name="dbo", alias="o"),
        TableRef(name="Customers", schema_name="dbo", alias="c"),
    ]
    # customer_id exists but has no index
    bundle = MetadataBundle(tables={
        "dbo.orders": TableMetadata(table="dbo.orders",
            columns=[ColumnMeta(column_name="customer_id", data_type="int")],
            indexes=[]),
    })
    findings = check_join_column_not_indexed(QueryProfile(tables=tables, joins=joins), bundle)
    assert len(findings) >= 1
    assert findings[0].severity == Severity.WARNING
```

- [ ] **Step 2: Run — verify failures**

```bash
pytest tests/test_rules/test_joins.py -v
```

- [ ] **Step 3: Write `app/rules/joins.py`**

```python
from app.models import QueryProfile, MetadataBundle, Finding, Severity, Category


def check_missing_join_predicate(profile: QueryProfile,
                                  bundle: MetadataBundle) -> list[Finding]:
    findings = []
    for join in profile.joins:
        if join.join_type == "CROSS":
            continue
        if not join.predicates:
            findings.append(Finding(
                category=Category.JOINS, severity=Severity.CRITICAL,
                title=f"Missing JOIN predicate: {join.left_table} ↔ {join.right_table}",
                explanation=(
                    f"The JOIN between '{join.left_table}' and '{join.right_table}' has no ON "
                    f"clause. This produces a Cartesian product — every row from the left table "
                    f"matched with every row from the right. Add an ON clause."
                ),
            ))
    return findings


def check_join_type_mismatch(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    findings = []
    alias_to_table = {t.alias: t for t in profile.tables if t.alias}

    for join in profile.joins:
        for pred in join.predicates:
            left_col = pred.column
            # Try to resolve right-hand side column from value_expr
            rhs = pred.value_expr.strip()
            if "." not in rhs:
                continue
            rhs_alias, rhs_col = rhs.split(".", 1)

            left_table = alias_to_table.get(pred.table_alias)
            right_table = alias_to_table.get(rhs_alias)
            if not left_table or not right_table:
                continue

            left_key = f"{left_table.schema_name}.{left_table.name}".lower()
            right_key = f"{right_table.schema_name}.{right_table.name}".lower()

            left_type = _col_type(bundle, left_key, left_col)
            right_type = _col_type(bundle, right_key, rhs_col)

            if left_type and right_type and left_type.lower() != right_type.lower():
                findings.append(Finding(
                    category=Category.JOINS, severity=Severity.WARNING,
                    title=f"Join type mismatch: {left_col} ({left_type}) ↔ {rhs_col} ({right_type})",
                    explanation=(
                        f"Joining '{left_col}' ({left_type}) to '{rhs_col}' ({right_type}) "
                        f"forces an implicit type conversion on every row, preventing index use. "
                        f"Ensure join columns have the same data type."
                    ),
                ))
    return findings


def check_join_column_not_indexed(profile: QueryProfile,
                                   bundle: MetadataBundle) -> list[Finding]:
    findings = []
    alias_to_table = {t.alias: t for t in profile.tables if t.alias}

    for join in profile.joins:
        for pred in join.predicates:
            left_table = alias_to_table.get(pred.table_alias)
            if not left_table:
                continue
            key = f"{left_table.schema_name}.{left_table.name}".lower()
            if key not in bundle.tables:
                continue
            meta = bundle.tables[key]
            indexed_cols = {c for idx in meta.indexes for c in idx.key_columns}
            if pred.column not in indexed_cols:
                findings.append(Finding(
                    category=Category.JOINS, severity=Severity.WARNING,
                    title=f"Join column '{pred.column}' not indexed on {left_table.name}",
                    explanation=(
                        f"The join column '{pred.column}' on '{left_table.name}' has no index. "
                        f"SQL Server will scan the table for each matching row. "
                        f"Adding an index on '{pred.column}' may significantly improve join performance."
                    ),
                ))
    return findings


def _col_type(bundle: MetadataBundle, table_key: str, col_name: str) -> str | None:
    if table_key not in bundle.tables:
        return None
    for col in bundle.tables[table_key].columns:
        if col.column_name.lower() == col_name.lower():
            return col.data_type
    return None
```

- [ ] **Step 4: Run tests**

```bash
pytest tests/test_rules/test_joins.py -v
```

Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/rules/joins.py tests/test_rules/test_joins.py
git commit -m "feat: join rules (missing predicate, type mismatch, unindexed column)"
```

---

## Task 9: Indexing Rules

**Files:**
- Create: `app/rules/indexing.py`
- Create: `tests/test_rules/test_indexing.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_rules/test_indexing.py
from app.models import (
    QueryProfile, MetadataBundle, Predicate, TableRef,
    TableMetadata, ColumnMeta, IndexDef, MissingIndexSuggestion, Severity, Category
)
from app.rules.indexing import (
    check_missing_index_suggestion, check_table_scan, check_non_covering_index,
)


def _profile_with_pred(table: str, col: str) -> QueryProfile:
    return QueryProfile(
        tables=[TableRef(name=table.split(".")[-1], schema_name="dbo")],
        where_predicates=[Predicate(column=col, operator="EQ", value_expr="1")],
        selected_columns=["id", "name", col],
    )


def test_missing_index_dmv_suggestion_is_warning():
    suggestion = MissingIndexSuggestion(
        table="dbo.Orders", equality_columns=["status"],
        avg_user_impact=45.0,
    )
    bundle = MetadataBundle(tables={
        "dbo.orders": TableMetadata(
            table="dbo.orders",
            columns=[ColumnMeta(column_name="status", data_type="varchar")],
            indexes=[],
            missing_index_suggestions=[suggestion],
        )
    })
    profile = _profile_with_pred("dbo.orders", "status")
    findings = check_missing_index_suggestion(profile, bundle)
    assert len(findings) == 1
    assert findings[0].severity == Severity.WARNING
    assert "45" in findings[0].explanation


def test_no_suggestion_no_finding():
    bundle = MetadataBundle(tables={
        "dbo.orders": TableMetadata(table="dbo.orders", missing_index_suggestions=[])
    })
    findings = check_missing_index_suggestion(_profile_with_pred("dbo.orders", "status"), bundle)
    assert findings == []


def test_table_scan_no_index_on_predicate_col():
    bundle = MetadataBundle(tables={
        "dbo.orders": TableMetadata(
            table="dbo.orders",
            columns=[ColumnMeta(column_name="status", data_type="varchar")],
            indexes=[IndexDef(index_name="PK_orders", is_clustered=True, key_columns=["id"])],
            row_count=100_000,
        )
    })
    profile = _profile_with_pred("dbo.orders", "status")
    findings = check_table_scan(profile, bundle)
    assert len(findings) == 1
    assert findings[0].severity == Severity.WARNING


def test_predicate_col_has_index_no_scan_finding():
    bundle = MetadataBundle(tables={
        "dbo.orders": TableMetadata(
            table="dbo.orders",
            columns=[ColumnMeta(column_name="status", data_type="varchar")],
            indexes=[IndexDef(index_name="IX_status", key_columns=["status"])],
            row_count=100_000,
        )
    })
    findings = check_table_scan(_profile_with_pred("dbo.orders", "status"), bundle)
    assert findings == []


def test_non_covering_index_is_warning():
    # Query selects 'name' but index on 'status' doesn't include 'name'
    bundle = MetadataBundle(tables={
        "dbo.orders": TableMetadata(
            table="dbo.orders",
            columns=[
                ColumnMeta(column_name="status", data_type="varchar"),
                ColumnMeta(column_name="name", data_type="varchar"),
            ],
            indexes=[IndexDef(index_name="IX_status", key_columns=["status"], include_columns=[])],
        )
    })
    profile = QueryProfile(
        tables=[TableRef(name="orders", schema_name="dbo")],
        where_predicates=[Predicate(column="status", operator="EQ", value_expr="'Active'")],
        selected_columns=["status", "name"],
    )
    findings = check_non_covering_index(profile, bundle)
    assert len(findings) == 1
    assert findings[0].severity == Severity.WARNING
```

- [ ] **Step 2: Run — verify failures**

```bash
pytest tests/test_rules/test_indexing.py -v
```

- [ ] **Step 3: Write `app/rules/indexing.py`**

```python
from app.models import QueryProfile, MetadataBundle, Finding, Severity, Category, TableMetadata

_SCAN_ROW_THRESHOLD = 10_000  # Flag scans on tables with more than this many rows


def check_missing_index_suggestion(profile: QueryProfile,
                                    bundle: MetadataBundle) -> list[Finding]:
    findings = []
    for table_ref in profile.tables:
        if table_ref.is_temp:
            continue
        key = f"{table_ref.schema_name}.{table_ref.name}".lower()
        meta = bundle.tables.get(key)
        if not meta:
            continue
        for suggestion in meta.missing_index_suggestions:
            cols = suggestion.equality_columns + suggestion.inequality_columns
            findings.append(Finding(
                category=Category.INDEXING, severity=Severity.WARNING,
                title=f"Missing index on {table_ref.name} (SQL Server suggestion)",
                explanation=(
                    f"SQL Server's workload history suggests creating an index on "
                    f"'{table_ref.name}' covering [{', '.join(cols)}] "
                    f"(estimated {suggestion.avg_user_impact:.0f}% improvement). "
                    f"Review and consider: CREATE INDEX IX_suggested ON "
                    f"{table_ref.schema_name}.{table_ref.name} "
                    f"({', '.join(suggestion.equality_columns)})"
                    + (f" INCLUDE ({', '.join(suggestion.included_columns)})"
                       if suggestion.included_columns else "") + "."
                ),
            ))
    return findings


def check_table_scan(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    findings = []
    pred_cols = {p.column.lower() for p in profile.where_predicates}
    if not pred_cols:
        return []

    for table_ref in profile.tables:
        if table_ref.is_temp:
            continue
        key = f"{table_ref.schema_name}.{table_ref.name}".lower()
        meta = bundle.tables.get(key)
        if not meta:
            continue

        indexed_cols = {c.lower() for idx in meta.indexes for c in idx.key_columns}
        unindexed_pred_cols = pred_cols - indexed_cols
        if not unindexed_pred_cols:
            continue

        row_count = meta.row_count or 0
        severity = Severity.CRITICAL if row_count > _SCAN_ROW_THRESHOLD else Severity.WARNING
        findings.append(Finding(
            category=Category.INDEXING, severity=severity,
            title=f"Possible table scan on {table_ref.name}",
            explanation=(
                f"Predicate column(s) [{', '.join(unindexed_pred_cols)}] on "
                f"'{table_ref.name}' ({row_count:,} rows) have no supporting index. "
                f"SQL Server may perform a full table scan. Consider adding an index "
                f"on [{', '.join(unindexed_pred_cols)}]."
            ),
        ))
    return findings


def check_non_covering_index(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    """Flag when a usable index exists for the WHERE but doesn't cover all selected columns."""
    findings = []
    pred_cols = {p.column.lower() for p in profile.where_predicates}
    selected = {c.lower() for c in profile.selected_columns if c != "*"}

    for table_ref in profile.tables:
        if table_ref.is_temp:
            continue
        key = f"{table_ref.schema_name}.{table_ref.name}".lower()
        meta = bundle.tables.get(key)
        if not meta:
            continue

        for idx in meta.indexes:
            if idx.is_clustered:
                continue
            key_set = {c.lower() for c in idx.key_columns}
            incl_set = {c.lower() for c in idx.include_columns}
            covered = key_set | incl_set

            # Index is usable for the WHERE clause
            if not (pred_cols & key_set):
                continue

            # But doesn't cover all selected columns
            missing = selected - covered - pred_cols
            if missing:
                findings.append(Finding(
                    category=Category.INDEXING, severity=Severity.WARNING,
                    title=f"Non-covering index '{idx.index_name}' on {table_ref.name}",
                    explanation=(
                        f"Index '{idx.index_name}' can satisfy the WHERE clause but does not "
                        f"cover selected column(s) [{', '.join(missing)}], forcing a key lookup "
                        f"for each matching row. Add [{', '.join(missing)}] to the INCLUDE clause: "
                        f"CREATE INDEX {idx.index_name} ON {table_ref.schema_name}.{table_ref.name} "
                        f"({', '.join(idx.key_columns)}) INCLUDE ({', '.join(missing)})."
                    ),
                ))
    return findings
```

- [ ] **Step 4: Run tests**

```bash
pytest tests/test_rules/test_indexing.py -v
```

Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/rules/indexing.py tests/test_rules/test_indexing.py
git commit -m "feat: indexing rules (DMV suggestions, table scan, non-covering index)"
```

---

## Task 10: Rules Engine & Scorer

**Files:**
- Create: `app/rules/engine.py`
- Create: `app/scoring/scorer.py`
- Create: `tests/test_rules/test_engine.py`
- Create: `tests/test_scoring/test_scorer.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_rules/test_engine.py
from app.models import QueryProfile, MetadataBundle, Category
from app.rules.engine import evaluate_rules


def test_evaluate_rules_returns_list():
    profile = QueryProfile(selected_columns=["*"])
    findings = evaluate_rules(profile, MetadataBundle())
    assert isinstance(findings, list)


def test_evaluate_rules_detects_select_star():
    profile = QueryProfile(selected_columns=["*"])
    findings = evaluate_rules(profile, MetadataBundle())
    categories = [f.category for f in findings]
    assert Category.STYLE in categories


# tests/test_scoring/test_scorer.py
from app.models import Finding, Severity, Category
from app.scoring.scorer import score_findings


def _finding(sev: Severity) -> Finding:
    return Finding(category=Category.STYLE, severity=sev, title="x", explanation="y")


def test_no_findings_scores_100():
    card = score_findings([])
    assert card.score == 100
    assert card.grade == "A"


def test_one_critical_deducts_20():
    card = score_findings([_finding(Severity.CRITICAL)])
    assert card.score == 80
    assert card.grade == "B"


def test_one_warning_deducts_10():
    card = score_findings([_finding(Severity.WARNING)])
    assert card.score == 90
    assert card.grade == "A"


def test_score_floors_at_zero():
    findings = [_finding(Severity.CRITICAL)] * 10
    card = score_findings(findings)
    assert card.score == 0
    assert card.grade == "F"


def test_category_scores_computed():
    findings = [
        Finding(category=Category.INDEXING, severity=Severity.CRITICAL, title="x", explanation="y"),
        Finding(category=Category.STYLE, severity=Severity.INFO, title="x", explanation="y"),
    ]
    card = score_findings(findings)
    idx_score = next(s for s in card.category_scores if s.category == Category.INDEXING)
    style_score = next(s for s in card.category_scores if s.category == Category.STYLE)
    assert idx_score.score == 80
    assert style_score.score == 97
```

- [ ] **Step 2: Run — verify failures**

```bash
pytest tests/test_rules/test_engine.py tests/test_scoring/test_scorer.py -v
```

- [ ] **Step 3: Write `app/rules/engine.py`**

```python
from app.models import QueryProfile, MetadataBundle, Finding
from app.rules import style, predicates, joins, indexing

_RULES = [
    style.check_select_star,
    style.check_order_without_paging,
    style.check_unnecessary_distinct,
    style.check_redundant_join,
    predicates.check_nonsargable_function,
    predicates.check_implicit_conversion,
    predicates.check_leading_wildcard,
    joins.check_missing_join_predicate,
    joins.check_join_type_mismatch,
    joins.check_join_column_not_indexed,
    indexing.check_missing_index_suggestion,
    indexing.check_table_scan,
    indexing.check_non_covering_index,
]


def evaluate_rules(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    findings = []
    for rule in _RULES:
        findings.extend(rule(profile, bundle))
    return findings
```

- [ ] **Step 4: Write `app/scoring/scorer.py`**

```python
from app.models import Finding, ReportCard, CategoryScore, Category, Severity

_DEDUCTIONS = {Severity.CRITICAL: 20, Severity.WARNING: 10, Severity.INFO: 3}
_GRADES = [(90, "A"), (80, "B"), (70, "C"), (60, "D"), (0, "F")]


def _grade(score: int) -> str:
    for threshold, letter in _GRADES:
        if score >= threshold:
            return letter
    return "F"


def score_findings(findings: list[Finding]) -> ReportCard:
    total = sum(_DEDUCTIONS[f.severity] for f in findings)
    score = max(0, 100 - total)

    category_scores = []
    for cat in Category:
        cat_findings = [f for f in findings if f.category == cat]
        cat_total = sum(_DEDUCTIONS[f.severity] for f in cat_findings)
        cat_score = max(0, 100 - cat_total)
        category_scores.append(CategoryScore(category=cat, score=cat_score, grade=_grade(cat_score)))

    return ReportCard(score=score, grade=_grade(score),
                      category_scores=category_scores, findings=findings)
```

- [ ] **Step 5: Run all tests**

```bash
pytest tests/ -v
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/rules/engine.py app/scoring/scorer.py tests/test_rules/test_engine.py tests/test_scoring/test_scorer.py
git commit -m "feat: rules engine and scorer"
```

---

## Task 11: FastAPI App & Database Endpoint

**Files:**
- Create: `app/main.py`
- Create: `tests/test_api/test_endpoints.py`

- [ ] **Step 1: Write failing tests**

```python
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
```

- [ ] **Step 2: Run — verify failures**

```bash
pytest tests/test_api/ -v
```

- [ ] **Step 3: Write `app/main.py`**

```python
from __future__ import annotations
import time
import uuid
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from app.config import get_connection
from app.models import ReportCard
from app.parser.extractor import extract_query_profiles
from app.metadata.collector import collect_metadata
from app.rules.engine import evaluate_rules
from app.scoring.scorer import score_findings

app = FastAPI(title="QueryAdvisor")
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="app/templates")

_results: dict[str, tuple[float, ReportCard]] = {}
_TTL = 1800.0


def _prune():
    now = time.time()
    stale = [k for k, (ts, _) in _results.items() if now - ts > _TTL]
    for k in stale:
        del _results[k]


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})


@app.get("/api/databases")
async def list_databases():
    conn = get_connection("master")
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sys.databases WHERE state_desc = 'ONLINE' ORDER BY name")
    databases = [row[0] for row in cursor.fetchall()]
    conn.close()
    return {"databases": databases}


@app.post("/api/analyze", response_class=HTMLResponse)
async def analyze(
    request: Request,
    sql: str = Form(...),
    database: str = Form(...),
    username: str = Form(...),
):
    _prune()
    profiles = extract_query_profiles(sql)
    real_tables = list({
        f"{t.schema_name}.{t.name}"
        for p in profiles for t in p.tables if not t.is_temp
    })
    bundle = collect_metadata(real_tables, database)
    all_findings = []
    for profile in profiles:
        all_findings.extend(evaluate_rules(profile, bundle))
    report_card = score_findings(all_findings)

    request_id = str(uuid.uuid4())
    _results[request_id] = (time.time(), report_card)

    return templates.TemplateResponse("partials/results.html", {
        "request": request,
        "report_card": report_card,
        "request_id": request_id,
        "view": "list",
    })


@app.get("/api/results/{request_id}/list", response_class=HTMLResponse)
async def results_list(request: Request, request_id: str):
    entry = _results.get(request_id)
    if not entry:
        return HTMLResponse("<p>Result expired. Please re-analyze.</p>", status_code=410)
    _, report_card = entry
    return templates.TemplateResponse("partials/findings_list.html", {
        "request": request, "report_card": report_card, "request_id": request_id,
    })


@app.get("/api/results/{request_id}/annotated", response_class=HTMLResponse)
async def results_annotated(request: Request, request_id: str):
    entry = _results.get(request_id)
    if not entry:
        return HTMLResponse("<p>Result expired. Please re-analyze.</p>", status_code=410)
    _, report_card = entry
    return templates.TemplateResponse("partials/annotated_sql.html", {
        "request": request, "report_card": report_card, "request_id": request_id,
    })
```

- [ ] **Step 4: Run tests**

```bash
pytest tests/test_api/ -v
```

Expected: Both tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/main.py tests/test_api/test_endpoints.py
git commit -m "feat: FastAPI app with analyze, databases, and result toggle endpoints"
```

---

## Task 12: HTML Templates

**Files:**
- Create: `app/templates/base.html`
- Create: `app/templates/index.html`
- Create: `app/templates/partials/results.html`
- Create: `app/templates/partials/report_card.html`
- Create: `app/templates/partials/findings_list.html`
- Create: `app/templates/partials/annotated_sql.html`

- [ ] **Step 1: Create `app/templates/base.html`**

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>QueryAdvisor</title>
    <script src="https://unpkg.com/htmx.org@1.9.12"></script>
    <link rel="stylesheet" href="/static/css/style.css">
</head>
<body>
    <header>
        <h1>QueryAdvisor</h1>
    </header>
    <main>
        {% block content %}{% endblock %}
    </main>
</body>
</html>
```

- [ ] **Step 2: Create `app/templates/index.html`**

```html
{% extends "base.html" %}
{% block content %}
<form id="analyze-form"
      hx-post="/api/analyze"
      hx-target="#results"
      hx-indicator="#spinner"
      hx-swap="innerHTML">

    <div class="form-row">
        <label for="username">Your name:</label>
        <input type="text" id="username" name="username" required placeholder="Jane Smith">
    </div>

    <div class="form-row">
        <label for="database">Database:</label>
        <select id="database" name="database"
                hx-get="/api/databases"
                hx-trigger="load"
                hx-target="#database-options"
                hx-swap="innerHTML">
            <option value="">Loading...</option>
        </select>
        <span id="database-options" style="display:none"></span>
    </div>

    <div class="form-row">
        <label for="sql">SQL Query:</label>
        <textarea id="sql" name="sql" rows="16" required
                  placeholder="Paste your T-SQL query here..."></textarea>
    </div>

    <button type="submit">Analyze Query</button>
    <span id="spinner" class="htmx-indicator">Analyzing...</span>
</form>

<div id="results"></div>

<script>
// Populate select from HTMX response
document.body.addEventListener("htmx:afterSwap", function(evt) {
    if (evt.detail.target.id === "database-options") {
        const select = document.getElementById("database");
        select.innerHTML = evt.detail.target.innerHTML;
        evt.detail.target.innerHTML = "";
    }
});
</script>
{% endblock %}
```

- [ ] **Step 3: Create `app/templates/partials/results.html`**

```html
{% include "partials/report_card.html" %}

<div class="view-toggle">
    <button hx-get="/api/results/{{ request_id }}/list"
            hx-target="#detail-panel"
            hx-swap="innerHTML"
            class="{% if view == 'list' %}active{% endif %}">
        Findings List
    </button>
    <button hx-get="/api/results/{{ request_id }}/annotated"
            hx-target="#detail-panel"
            hx-swap="innerHTML"
            class="{% if view == 'annotated' %}active{% endif %}">
        Annotated SQL
    </button>
</div>

<div id="detail-panel">
    {% if view == 'list' %}
        {% include "partials/findings_list.html" %}
    {% else %}
        {% include "partials/annotated_sql.html" %}
    {% endif %}
</div>
```

- [ ] **Step 4: Create `app/templates/partials/report_card.html`**

```html
<div class="report-card">
    <div class="overall-grade grade-{{ report_card.grade | lower }}">
        <span class="grade-letter">{{ report_card.grade }}</span>
        <span class="grade-score">{{ report_card.score }}/100</span>
    </div>
    <div class="category-scores">
        {% for cs in report_card.category_scores %}
        <div class="cat-score grade-{{ cs.grade | lower }}">
            <span class="cat-name">{{ cs.category.value | title }}</span>
            <span class="cat-grade">{{ cs.grade }}</span>
            <span class="cat-score-num">{{ cs.score }}</span>
        </div>
        {% endfor %}
    </div>
</div>
```

- [ ] **Step 5: Create `app/templates/partials/findings_list.html`**

```html
{% set grouped = {} %}
{% for f in report_card.findings %}
    {% set _ = grouped.setdefault(f.category.value, []).append(f) %}
{% endfor %}

{% if not report_card.findings %}
    <div class="no-findings">No issues found. Grade A!</div>
{% else %}
    {% for category, findings in grouped.items() %}
    <section class="finding-group">
        <h3>{{ category | title }} ({{ findings | length }})</h3>
        {% for finding in findings %}
        <div class="finding finding-{{ finding.severity.value }}">
            <div class="finding-header">
                <span class="severity-badge severity-{{ finding.severity.value }}">
                    {{ finding.severity.value | upper }}
                </span>
                <strong>{{ finding.title }}</strong>
            </div>
            <p class="finding-explanation">{{ finding.explanation }}</p>
            {% if finding.affected_sql %}
            <code class="affected-sql">{{ finding.affected_sql }}</code>
            {% endif %}
        </div>
        {% endfor %}
    </section>
    {% endfor %}
{% endif %}
```

- [ ] **Step 6: Create `app/templates/partials/annotated_sql.html`**

```html
<div class="annotated-sql">
    {% if not report_card.findings %}
        <p class="no-findings">No issues found.</p>
    {% else %}
        <div class="annotation-legend">
            <span class="severity-badge severity-critical">CRITICAL</span>
            <span class="severity-badge severity-warning">WARNING</span>
            <span class="severity-badge severity-info">INFO</span>
        </div>
        <div class="findings-as-annotations">
            {% for finding in report_card.findings %}
            <div class="annotation finding-{{ finding.severity.value }}">
                <span class="severity-badge severity-{{ finding.severity.value }}">
                    {{ finding.severity.value | upper }}
                </span>
                <strong>{{ finding.title }}</strong>
                {% if finding.affected_sql %}
                <code>{{ finding.affected_sql }}</code>
                {% endif %}
                <p>{{ finding.explanation }}</p>
            </div>
            {% endfor %}
        </div>
    {% endif %}
</div>
```

- [ ] **Step 7: Fix the database dropdown HTMX pattern in `index.html`**

The HTMX approach for populating a `<select>` needs the response to contain `<option>` tags. Update the `/api/databases` endpoint in `main.py` to support an HTMX response that returns options HTML, and simplify the template:

In `main.py`, add an HTML endpoint variant:

```python
@app.get("/api/databases/options", response_class=HTMLResponse)
async def list_databases_options(request: Request):
    conn = get_connection("master")
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sys.databases WHERE state_desc = 'ONLINE' ORDER BY name")
    databases = [row[0] for row in cursor.fetchall()]
    conn.close()
    options_html = "".join(f'<option value="{db}">{db}</option>' for db in databases)
    return HTMLResponse(options_html)
```

Update `index.html` select element:

```html
<select id="database" name="database"
        hx-get="/api/databases/options"
        hx-trigger="load"
        hx-swap="innerHTML">
    <option value="">Loading...</option>
</select>
```

Remove the `<script>` workaround block from `index.html`.

- [ ] **Step 8: Add basic CSS to `static/css/style.css`**

```css
* { box-sizing: border-box; }
body { font-family: system-ui, sans-serif; max-width: 960px; margin: 0 auto; padding: 1rem; }
header h1 { font-size: 1.5rem; margin-bottom: 1rem; }

.form-row { margin-bottom: 0.75rem; display: flex; flex-direction: column; gap: 0.25rem; }
label { font-weight: 600; font-size: 0.875rem; }
textarea { font-family: monospace; font-size: 0.875rem; padding: 0.5rem; width: 100%; }
select, input[type="text"] { padding: 0.4rem; font-size: 0.875rem; }
button[type="submit"] { padding: 0.5rem 1.25rem; font-size: 1rem; cursor: pointer; }

.htmx-indicator { display: none; margin-left: 1rem; }
.htmx-request .htmx-indicator { display: inline; }

.report-card { display: flex; align-items: center; gap: 1.5rem; padding: 1rem;
               border: 2px solid #ddd; border-radius: 6px; margin: 1rem 0; }
.overall-grade { font-size: 2rem; font-weight: bold; text-align: center; min-width: 80px; }
.grade-letter { font-size: 3rem; display: block; }
.category-scores { display: flex; gap: 1rem; }
.cat-score { text-align: center; padding: 0.5rem; border-radius: 4px; background: #f5f5f5; }

.grade-a { color: #166534; } .grade-b { color: #1e40af; }
.grade-c { color: #92400e; } .grade-d { color: #7c2d12; } .grade-f { color: #7f1d1d; }

.view-toggle { margin: 0.5rem 0; display: flex; gap: 0.5rem; }
.view-toggle button { padding: 0.4rem 0.9rem; cursor: pointer; border: 1px solid #ccc; background: #fff; }
.view-toggle button.active { background: #1e40af; color: white; border-color: #1e40af; }

.finding-group { margin-bottom: 1.25rem; }
.finding-group h3 { text-transform: capitalize; border-bottom: 1px solid #eee; padding-bottom: 0.25rem; }
.finding { padding: 0.75rem; margin-bottom: 0.5rem; border-left: 4px solid #ddd; background: #fafafa; }
.finding-critical { border-left-color: #dc2626; }
.finding-warning { border-left-color: #f59e0b; }
.finding-info { border-left-color: #3b82f6; }
.finding-header { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.4rem; }
.severity-badge { font-size: 0.7rem; font-weight: bold; padding: 0.15rem 0.4rem;
                  border-radius: 3px; text-transform: uppercase; }
.severity-critical { background: #fee2e2; color: #991b1b; }
.severity-warning { background: #fef3c7; color: #92400e; }
.severity-info { background: #dbeafe; color: #1e40af; }
.finding-explanation { margin: 0.3rem 0; font-size: 0.875rem; line-height: 1.5; }
.affected-sql { display: block; font-family: monospace; font-size: 0.8rem;
                background: #f0f0f0; padding: 0.3rem 0.5rem; margin-top: 0.3rem; }
.no-findings { padding: 1rem; color: #166534; background: #f0fdf4; border-radius: 4px; }
```

- [ ] **Step 9: Smoke test the app manually**

```bash
uvicorn app.main:app --reload
```

Open `http://localhost:8000` in a browser. Verify:
- Page loads with form
- Database dropdown populates (or shows error if no SQL Server — expected in dev without Kerberos)
- Submitting a query with SELECT * returns report card with a WARNING

- [ ] **Step 10: Run full test suite**

```bash
pytest tests/ -v
```

Expected: All tests pass.

- [ ] **Step 11: Commit**

```bash
git add app/templates/ app/main.py static/
git commit -m "feat: HTML templates, HTMX interactions, and CSS"
```

---

## Task 13: Dockerfile

**Files:**
- Create: `Dockerfile`
- Create: `.dockerignore`

- [ ] **Step 1: Create `Dockerfile`**

```dockerfile
FROM python:3.11-slim AS base

# Install ODBC driver and Kerberos dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg unixodbc-dev \
    krb5-user libgssapi-krb5-2 libkrb5-dev \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
       | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] \
       https://packages.microsoft.com/debian/12/prod bookworm main" \
       > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y msodbcsql18 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml .
RUN pip install --no-cache-dir -e .

COPY app/ ./app/
COPY static/ ./static/

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 2: Create `.dockerignore`**

```
.git
__pycache__
*.pyc
.env
tests/
docs/
*.md
```

- [ ] **Step 3: Build and verify image**

```bash
docker build -t queryadvisor:dev .
```

Expected: Build succeeds. Note: msodbcsql18 requires internet access.

- [ ] **Step 4: Commit**

```bash
git add Dockerfile .dockerignore
git commit -m "feat: Dockerfile with msodbcsql18 and Kerberos support"
```

---

## Task 14: GitHub Repository & Issues

**Files:** None — all git/GitHub CLI operations.

- [ ] **Step 1: Create GitHub repository**

```bash
gh repo create queryadvisor --public --description "T-SQL query optimization advisor — FastAPI/HTMX"
```

Expected: Repo created at `github.com/<your-org>/queryadvisor`

- [ ] **Step 2: Push existing code**

```bash
git remote add origin git@github.com:<your-org>/queryadvisor.git
git branch -M main
git push -u origin main
```

- [ ] **Step 3: Add GitHub issue labels**

```bash
gh label create "pipeline" --color "0075ca" --description "Core analysis pipeline"
gh label create "rules" --color "e4e669" --description "Optimization rules"
gh label create "ui" --color "d93f0b" --description "Frontend / templates"
gh label create "infra" --color "c2e0c6" --description "Docker / deployment"
gh label create "enhancement" --color "a2eeef" --description "Future improvement"
```

- [ ] **Step 4: Create issues for each remaining implementation task**

```bash
gh issue create --title "Task 1: Project scaffolding" \
  --body "pyproject.toml, directory structure, __init__.py files, install dependencies. See plan: docs/superpowers/plans/2026-03-31-queryadvisor-implementation.md" \
  --label "pipeline"

gh issue create --title "Task 2: Data models (Pydantic)" \
  --body "Implement app/models.py with all models: AnalysisRequest, QueryProfile, MetadataBundle, Finding, ReportCard. See plan Task 2." \
  --label "pipeline"

gh issue create --title "Task 3: SQL Parser — table/column/join extraction" \
  --body "app/parser/extractor.py using sqlglot tsql dialect. Extracts tables, selected columns, joins. See plan Task 3." \
  --label "pipeline"

gh issue create --title "Task 4: SQL Parser — predicate extraction and temp table tracking" \
  --body "WHERE clause predicates, function-wrap detection, #temp table schema tracking across multi-statement scripts. See plan Task 4." \
  --label "pipeline"

gh issue create --title "Task 5: Metadata collector" \
  --body "app/metadata/collector.py — queries sys.indexes, sys.columns, sys.stats, sys.dm_db_missing_index_* catalog views via pyodbc. See plan Task 5." \
  --label "pipeline"

gh issue create --title "Task 6: Style rules" \
  --body "SELECT *, unnecessary DISTINCT, ORDER BY without paging, redundant JOIN. See plan Task 6." \
  --label "rules"

gh issue create --title "Task 7: Predicate rules" \
  --body "Non-sargable function wrap, implicit type conversion, leading wildcard LIKE. See plan Task 7." \
  --label "rules"

gh issue create --title "Task 8: Join rules" \
  --body "Missing join predicate (cartesian), join type mismatch, unindexed join column. See plan Task 8." \
  --label "rules"

gh issue create --title "Task 9: Indexing rules" \
  --body "Missing index DMV suggestion, table scan detection, non-covering index. See plan Task 9." \
  --label "rules"

gh issue create --title "Task 10: Rules engine and scorer" \
  --body "app/rules/engine.py orchestrates all rules. app/scoring/scorer.py computes letter grades per category. See plan Task 10." \
  --label "pipeline"

gh issue create --title "Task 11: FastAPI app and endpoints" \
  --body "app/main.py — all routes: GET /, GET /api/databases/options, POST /api/analyze, GET /api/results/{id}/list, GET /api/results/{id}/annotated. See plan Task 11." \
  --label "ui"

gh issue create --title "Task 12: HTML templates and CSS" \
  --body "base.html, index.html, partials/results.html, report_card.html, findings_list.html, annotated_sql.html. HTMX interactions. Basic CSS. See plan Task 12." \
  --label "ui"

gh issue create --title "Task 13: Dockerfile" \
  --body "Multi-stage build with msodbcsql18, Kerberos libs (krb5-user, libgssapi-krb5-2). See plan Task 13." \
  --label "infra"
```

- [ ] **Step 5: Verify issues were created**

```bash
gh issue list
```

Expected: 13 issues listed.

- [ ] **Step 6: Push plan doc**

```bash
git push origin main
```

---

## Verification Checklist

Run these after all tasks are complete:

```bash
# Full test suite
pytest tests/ -v

# Lint
ruff check app/ tests/

# Smoke test: query with known issues
uvicorn app.main:app --reload
# Then POST to /api/analyze with: SELECT * FROM Orders WHERE YEAR(created_at) = 2024
# Expected: Grade < 90, at least 2 findings (SELECT *, non-sargable function)
```

End-to-end scenario matrix:

| Scenario | Expected grade | Expected findings |
|----------|---------------|-------------------|
| `SELECT * FROM Orders` | < A | SELECT * warning |
| `SELECT id FROM Orders WHERE YEAR(d) = 2024` | ≤ C | Non-sargable CRITICAL |
| `SELECT a.id FROM A, B WHERE a.x = 1` | F or D | Cartesian CRITICAL |
| `SELECT id FROM Orders ORDER BY name` | ≤ B | ORDER BY without paging INFO |
| `SELECT id FROM Orders WHERE id = 1` (indexed) | A | No findings |
