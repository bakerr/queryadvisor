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
