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
