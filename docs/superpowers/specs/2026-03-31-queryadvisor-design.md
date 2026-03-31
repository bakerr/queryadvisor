# QueryAdvisor — Design Spec

**Date:** 2026-03-31  
**Status:** Approved  

---

## Context

QueryAdvisor is an internal web tool that helps developers and analysts optimize T-SQL queries before
running them in production. Users paste a SQL script, select a target database, and receive a graded
report of optimization issues — missing indexes, non-sargable predicates, implicit type conversions,
bad join patterns, and style issues.

The tool connects to SQL Server's catalog views to enrich its analysis with actual schema metadata
(indexes, column types, statistics freshness), but deliberately avoids executing EXPLAIN plans to
keep the tool read-only and low-overhead. Most high-value optimization advice can be derived from
static analysis + catalog metadata alone.

---

## Tech Stack

| Layer | Choice | Reason |
|-------|--------|--------|
| Web framework | FastAPI | Async, typed, Pydantic-native |
| Frontend | HTMX + Jinja2 | No JS build toolchain; server-rendered partials |
| SQL Parser | sqlglot (tsql dialect) | Full AST, good T-SQL support, pure Python |
| DB connectivity | pyodbc + msodbcsql18 | Windows Integrated Auth via Kerberos |
| Auth | None initially; Ping SSO later | Username entered manually in v1 |
| Persistence | None | Fully stateless; in-memory dict for result session |
| Container | Linux + Kerberos (existing infra pattern) | |

---

## Architecture

Linear pipeline: **Parse → Extract → Collect Metadata → Evaluate Rules → Score → Render**

Each stage has a clean input/output contract. No parallel execution in v1; easy to add later.

```
SQL text + database name
    ↓ parser/
AST → QueryProfile (tables, joins, predicates, columns, temp tables)
    ↓ metadata/
QueryProfile → MetadataBundle (indexes, column types, stats, missing index suggestions)
    ↓ rules/
(QueryProfile + MetadataBundle) → list[Finding]
    ↓ scoring/
list[Finding] → ReportCard (grade, per-category grades, findings)
    ↓ templates/
ReportCard → HTML partial (via HTMX)
```

---

## Project Structure

```
queryadvisor/
├── app/
│   ├── main.py                  # FastAPI app, routes, HTMX endpoints
│   ├── config.py                # Settings (SQL Server hostname, driver config)
│   ├── models.py                # Pydantic: AnalysisRequest, QueryProfile, Finding, ReportCard
│   ├── parser/
│   │   ├── extractor.py         # sqlglot AST walker → QueryProfile
│   │   └── temp_tables.py       # Temp table schema tracking across statements
│   ├── metadata/
│   │   └── collector.py         # sys.* catalog view queries → MetadataBundle
│   ├── rules/
│   │   ├── engine.py            # Runs all rules, returns list[Finding]
│   │   ├── indexing.py          # Missing/unused index rules
│   │   ├── predicates.py        # Non-sargable predicates, implicit conversions
│   │   ├── joins.py             # Missing predicates, type mismatches, unindexed join cols
│   │   └── style.py             # SELECT *, unnecessary DISTINCT, ORDER BY without paging
│   ├── scoring/
│   │   └── scorer.py            # list[Finding] → ReportCard with letter grades
│   └── templates/
│       ├── base.html
│       ├── index.html           # Main page
│       └── partials/
│           ├── report_card.html
│           ├── findings_list.html
│           └── annotated_sql.html
├── static/
│   └── css/
├── tests/
│   ├── test_parser/
│   ├── test_rules/
│   ├── test_metadata/
│   └── test_scoring/
├── pyproject.toml
├── Dockerfile
└── README.md
```

---

## Data Models

```python
# AnalysisRequest — inbound from form POST
class AnalysisRequest(BaseModel):
    sql: str
    database: str
    username: str

# QueryProfile — output of parser stage
class TableRef(BaseModel):
    name: str
    schema_name: str
    alias: str | None
    is_temp: bool

class Predicate(BaseModel):
    column: str
    table_alias: str | None
    operator: str          # =, >, LIKE, IN, etc.
    value_expr: str        # raw value/expression on RHS
    has_function_wrap: bool  # e.g., YEAR(col) = 2024

class JoinDef(BaseModel):
    join_type: str         # INNER, LEFT, CROSS, etc.
    left_table: str
    right_table: str
    predicates: list[Predicate]

class QueryProfile(BaseModel):
    tables: list[TableRef]
    joins: list[JoinDef]
    where_predicates: list[Predicate]
    selected_columns: list[str]  # ["*"] if SELECT *
    has_distinct: bool
    has_order_by: bool
    has_top_or_offset: bool
    ctes: list["QueryProfile"]
    subqueries: list["QueryProfile"]
    temp_table_schemas: dict[str, list[ColumnDef]]  # "#temp" → columns

# MetadataBundle — output of metadata stage
class IndexDef(BaseModel):
    index_name: str
    is_unique: bool
    is_clustered: bool
    key_columns: list[str]
    include_columns: list[str]

class ColumnMeta(BaseModel):
    column_name: str
    data_type: str
    is_nullable: bool

class MissingIndexSuggestion(BaseModel):
    table: str
    equality_columns: list[str]
    inequality_columns: list[str]
    included_columns: list[str]
    avg_user_impact: float  # % improvement SQL Server estimates

class TableMetadata(BaseModel):
    table: str
    indexes: list[IndexDef]
    columns: list[ColumnMeta]
    stats_last_updated: datetime | None
    row_count: int | None
    missing_index_suggestions: list[MissingIndexSuggestion]

class MetadataBundle(BaseModel):
    tables: dict[str, TableMetadata]  # "schema.table" → TableMetadata

# Finding — output of rules stage
class Severity(str, Enum):
    CRITICAL = "critical"   # -20 pts
    WARNING = "warning"     # -10 pts
    INFO = "info"           # -3 pts

class Category(str, Enum):
    INDEXING = "indexing"
    PREDICATES = "predicates"
    JOINS = "joins"
    STYLE = "style"

class Finding(BaseModel):
    category: Category
    severity: Severity
    title: str
    explanation: str         # templated explanation text
    affected_sql: str | None # snippet of offending SQL
    line_start: int | None   # for annotation view
    line_end: int | None

# ReportCard — output of scoring stage
class CategoryScore(BaseModel):
    category: Category
    score: int       # 0-100
    grade: str       # A-F

class ReportCard(BaseModel):
    score: int
    grade: str
    category_scores: list[CategoryScore]
    findings: list[Finding]
```

---

## Analysis Rules (v1)

### Indexing Rules (`rules/indexing.py`)
1. **Missing index opportunity** — SQL Server has a `dm_db_missing_index_*` suggestion for a table referenced in the query with impact > 10%. Severity: WARNING.
2. **Table scan on large table** — predicate columns have no usable index, row count > configurable threshold. Severity: CRITICAL if table is large, WARNING otherwise.
3. **Non-covering index** — query selects columns not in index key or INCLUDE columns, forcing a key lookup. Severity: WARNING.

### Predicate Rules (`rules/predicates.py`)
4. **Non-sargable: function on column** — e.g., `YEAR(created_at) = 2024`, `UPPER(name) = 'FOO'`. Index cannot be used. Severity: CRITICAL.
5. **Implicit type conversion** — column is varchar, predicate compares to numeric literal (or vice versa). Forces scan. Severity: CRITICAL.
6. **Leading wildcard LIKE** — `WHERE col LIKE '%foo'`. Cannot use index. Severity: WARNING.
7. **OR on indexed column** — `WHERE indexed_col = 1 OR indexed_col = 2`. Suggest `IN` or UNION. Severity: INFO.

### Join Rules (`rules/joins.py`)
8. **Missing join predicate** — a JOIN has no ON clause (cartesian product). Severity: CRITICAL.
9. **Join on mismatched types** — joining columns with different data types causes implicit conversion. Severity: WARNING.
10. **Join column not indexed** — join predicate column has no index on either side. Severity: WARNING.

### Style Rules (`rules/style.py`)
11. **SELECT \*** — selecting all columns. Severity: WARNING.
12. **Unnecessary DISTINCT** — DISTINCT on a result that cannot have duplicates (e.g., joining on PK). Severity: INFO.
13. **ORDER BY without TOP/OFFSET** — sorting a full result set with no paging. Severity: INFO.
14. **Redundant JOIN** — a joined table contributes no columns to SELECT and has no WHERE reference. Severity: WARNING.

---

## Scoring Model

```
base_score = 100
deductions:
  CRITICAL: -20 per finding
  WARNING:  -10 per finding
  INFO:      -3 per finding
score = max(0, base_score - total_deductions)

grade:
  A: 90-100
  B: 80-89
  C: 70-79
  D: 60-69
  F: 0-59

Per-category scores computed with same formula applied to each category's findings.
```

---

## HTMX Interaction Model

### Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/` | Serve main page |
| GET | `/api/databases` | List available databases (populates dropdown) |
| POST | `/api/analyze` | Run full pipeline, return report_card + findings_list partials |
| GET | `/api/results/{request_id}/list` | Return findings_list partial for existing result |
| GET | `/api/results/{request_id}/annotated` | Return annotated_sql partial for existing result |

### Session State
After `POST /api/analyze`, the `ReportCard` is stored in an in-memory dict:
`results: dict[str, ReportCard]` keyed by `request_id` (UUID).

The `request_id` is embedded in the rendered HTML so the toggle endpoints can retrieve the cached result without re-running the analysis. Dict entries expire after 30 minutes (simple TTL via timestamp).

### UI Behavior
- Database dropdown populated on page load via `hx-get="/api/databases" hx-trigger="load"`
- Analyze button: `hx-post="/api/analyze" hx-target="#results" hx-indicator="#spinner"`
- Detail toggle buttons: `hx-get="/api/results/{id}/list"` or `.../annotated`, target `#detail-panel`
- Report card header always visible once a result is shown; only detail panel swaps

---

## SQL Parsing: Multi-Statement Scripts

Scripts are processed as an ordered sequence of statements:

1. Split on `GO` (T-SQL batch separator) and semicolons
2. For each statement:
   - If `CREATE TABLE #temp_name (...)` → register temp table schema in `temp_table_catalog`
   - If `SELECT ... INTO #temp_name ...` → infer temp table schema from SELECT columns + source table metadata
   - If SELECT statement → parse with sqlglot, resolve table refs against both real catalog and `temp_table_catalog`
3. All findings from all SELECT statements in the script are aggregated into one `ReportCard`

Temp table columns are typed as `unknown` if they come from `SELECT *` on another temp table (degenerate case; warn about it via rule #11).

---

## Database Connection

```python
# config.py
SQL_SERVER_HOST = os.getenv("SQL_SERVER_HOST", "localhost")
ODBC_DRIVER = os.getenv("ODBC_DRIVER", "ODBC Driver 18 for SQL Server")

def get_connection(database: str) -> pyodbc.Connection:
    conn_str = (
        f"DRIVER={{{ODBC_DRIVER}}};"
        f"SERVER={SQL_SERVER_HOST};"
        f"DATABASE={database};"
        "Trusted_Connection=yes;"
        "Authentication=ActiveDirectoryIntegrated;"
    )
    return pyodbc.connect(conn_str, timeout=10)
```

Connection is opened per-request, not pooled in v1. Can add connection pooling later if latency becomes an issue.

---

## Catalog View Queries

The metadata collector runs these queries for each real (non-temp) table referenced in the script:

```sql
-- Indexes and key columns
SELECT i.name, i.is_unique, i.type_desc, ic.key_ordinal, ic.is_included_column, c.name AS col_name
FROM sys.indexes i
JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE i.object_id = OBJECT_ID(?)
ORDER BY i.index_id, ic.key_ordinal;

-- Column metadata
SELECT c.name, t.name AS type_name, c.is_nullable
FROM sys.columns c
JOIN sys.types t ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID(?);

-- Statistics freshness
SELECT s.name, sp.last_updated, sp.rows
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE s.object_id = OBJECT_ID(?);

-- Missing index suggestions from SQL Server DMVs
SELECT mid.equality_columns, mid.inequality_columns, mid.included_columns,
       migs.avg_user_impact
FROM sys.dm_db_missing_index_details mid
JOIN sys.dm_db_missing_index_groups mig ON mid.index_handle = mig.index_handle
JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
WHERE mid.object_id = OBJECT_ID(?)
  AND migs.avg_user_impact > 10
ORDER BY migs.avg_user_impact DESC;
```

---

## Verification

End-to-end test scenarios:

1. **Happy path** — Paste a SELECT with a non-sargable predicate against a table with known schema. Verify finding appears, score is below 90, grade is correct.
2. **Missing index** — Paste a SELECT against a table that has `dm_db_missing_index_*` suggestions. Verify those suggestions appear in findings.
3. **Temp table script** — Multi-statement: `SELECT INTO #t`, then `SELECT ... FROM #t JOIN real_table`. Verify both temp table and real table are analyzed.
4. **SELECT \*** — Verify style warning appears.
5. **Cartesian join** — `FROM a, b` without WHERE join condition. Verify CRITICAL finding.
6. **No issues** — Clean, well-indexed query. Verify grade A, no findings.
7. **DB unreachable** — Connection failure returns user-friendly error, not 500.
8. **Databases endpoint** — Verify dropdown populates with `sys.databases` list.

Unit tests cover each rule module independently with mocked `MetadataBundle` fixtures.

---

## Future Enhancements (out of scope for v1)

- Ping SSO integration for automatic user identity
- LLM-powered explanation layer (rule detects, LLM explains in conversational prose)
- Query history / saved queries (SQLite)
- CodeMirror syntax highlighting in the SQL editor
- PostgreSQL adapter via sqlglot dialect switching
- Suggested index DDL generation (`CREATE INDEX ... ON table (col1) INCLUDE (col2)`)
- Execution plan analysis mode (opt-in EXPLAIN fallback)
