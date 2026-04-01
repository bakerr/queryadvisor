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
    bundle = MetadataBundle(tables={
        "dbo.orders": TableMetadata(table="dbo.orders",
            columns=[ColumnMeta(column_name="customer_id", data_type="int")],
            indexes=[]),
    })
    findings = check_join_column_not_indexed(QueryProfile(tables=tables, joins=joins), bundle)
    assert len(findings) >= 1
    assert findings[0].severity == Severity.WARNING
