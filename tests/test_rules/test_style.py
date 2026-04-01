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
    profile = _profile(
        tables=tables, joins=joins,
        selected_columns=["id"],
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
