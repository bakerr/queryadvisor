from app.models import Category, Finding, MetadataBundle, QueryProfile, Severity

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
        value_looks_numeric = _is_numeric_literal(pred.value_expr)
        col_is_string = col_type.lower() in _STRING_TYPES
        col_is_numeric = col_type.lower() in _NUMERIC_TYPES
        if (col_is_string and value_looks_numeric) or (col_is_numeric and not value_looks_numeric):
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
        if pred.value_expr.startswith("%"):
            findings.append(Finding(
                category=Category.PREDICATES, severity=Severity.WARNING,
                title=f"Leading wildcard LIKE on '{pred.column}'",
                explanation=(
                    f"LIKE '{pred.value_expr}' starts with a wildcard, which forces a full table "
                    f"or index scan. SQL Server cannot use a B-tree index to seek when the pattern "
                    f"begins with %. Consider full-text search if substring matching is required."
                ),
                affected_sql=f"{pred.column} LIKE '{pred.value_expr}'",
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
