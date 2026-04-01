from __future__ import annotations

from app.config import get_connection
from app.models import ColumnMeta, IndexDef, MetadataBundle, MissingIndexSuggestion, TableMetadata

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
