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
