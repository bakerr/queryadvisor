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
        tables=[TableRef(name="Orders", schema_name="dbo")],
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
        tables=[TableRef(name="Orders", schema_name="dbo")],
        where_predicates=[pred],
    )
    bundle = _bundle_with_column("dbo.orders", "order_id", "int")
    assert check_implicit_conversion(profile, bundle) == []


def test_leading_wildcard_is_warning():
    pred = Predicate(column="name", operator="LIKE",
                     value_expr="%smith", has_function_wrap=False)
    profile = QueryProfile(where_predicates=[pred])
    findings = check_leading_wildcard(profile, MetadataBundle())
    assert len(findings) == 1
    assert findings[0].severity == Severity.WARNING


def test_trailing_wildcard_no_finding():
    pred = Predicate(column="name", operator="LIKE",
                     value_expr="smith%", has_function_wrap=False)
    profile = QueryProfile(where_predicates=[pred])
    assert check_leading_wildcard(profile, MetadataBundle()) == []
