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
