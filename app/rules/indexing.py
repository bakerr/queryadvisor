from app.models import Category, Finding, MetadataBundle, QueryProfile, Severity

_SCAN_ROW_THRESHOLD = 1_000_000


def check_missing_index_suggestion(profile: QueryProfile,
                                    bundle: MetadataBundle) -> list[Finding]:
    findings = []
    for table_ref in profile.tables:
        if table_ref.is_temp:
            continue
        key = f"{table_ref.schema_name}.{table_ref.name}".lower()
        meta = bundle.tables.get(key)
        if not meta:
            continue
        for suggestion in meta.missing_index_suggestions:
            cols = suggestion.equality_columns + suggestion.inequality_columns
            findings.append(Finding(
                category=Category.INDEXING, severity=Severity.WARNING,
                title=f"Missing index on {table_ref.name} (SQL Server suggestion)",
                explanation=(
                    f"SQL Server's workload history suggests creating an index on "
                    f"'{table_ref.name}' covering [{', '.join(cols)}] "
                    f"(estimated {suggestion.avg_user_impact:.0f}% improvement). "
                    f"Review and consider: CREATE INDEX IX_suggested ON "
                    f"{table_ref.schema_name}.{table_ref.name} "
                    f"({', '.join(suggestion.equality_columns)})"
                    + (f" INCLUDE ({', '.join(suggestion.included_columns)})"
                       if suggestion.included_columns else "") + "."
                ),
            ))
    return findings


def check_table_scan(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    findings = []
    pred_cols = {p.column.lower() for p in profile.where_predicates}
    if not pred_cols:
        return []

    for table_ref in profile.tables:
        if table_ref.is_temp:
            continue
        key = f"{table_ref.schema_name}.{table_ref.name}".lower()
        meta = bundle.tables.get(key)
        if not meta:
            continue

        indexed_cols = {c.lower() for idx in meta.indexes for c in idx.key_columns}
        unindexed_pred_cols = pred_cols - indexed_cols
        if not unindexed_pred_cols:
            continue

        row_count = meta.row_count or 0
        severity = Severity.CRITICAL if row_count > _SCAN_ROW_THRESHOLD else Severity.WARNING
        findings.append(Finding(
            category=Category.INDEXING, severity=severity,
            title=f"Possible table scan on {table_ref.name}",
            explanation=(
                f"Predicate column(s) [{', '.join(unindexed_pred_cols)}] on "
                f"'{table_ref.name}' ({row_count:,} rows) have no supporting index. "
                f"SQL Server may perform a full table scan. Consider adding an index "
                f"on [{', '.join(unindexed_pred_cols)}]."
            ),
        ))
    return findings


def check_non_covering_index(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    findings = []
    pred_cols = {p.column.lower() for p in profile.where_predicates}
    selected = {c.lower() for c in profile.selected_columns if c != "*"}

    for table_ref in profile.tables:
        if table_ref.is_temp:
            continue
        key = f"{table_ref.schema_name}.{table_ref.name}".lower()
        meta = bundle.tables.get(key)
        if not meta:
            continue

        for idx in meta.indexes:
            if idx.is_clustered:
                continue
            key_set = {c.lower() for c in idx.key_columns}
            incl_set = {c.lower() for c in idx.include_columns}
            covered = key_set | incl_set

            if not (pred_cols & key_set):
                continue

            missing = selected - covered - pred_cols
            if missing:
                table_key = f"{table_ref.schema_name}.{table_ref.name}"
                findings.append(Finding(
                    category=Category.INDEXING, severity=Severity.WARNING,
                    title=f"Non-covering index '{idx.index_name}' on {table_ref.name}",
                    explanation=(
                        f"Index '{idx.index_name}' can satisfy the WHERE clause but does not "
                        f"cover selected column(s) [{', '.join(missing)}], forcing a key lookup "
                        f"for each matching row. Add [{', '.join(missing)}] to the INCLUDE "
                        f"clause: CREATE INDEX {idx.index_name} ON {table_key} "
                        f"({', '.join(idx.key_columns)}) INCLUDE ({', '.join(missing)})."
                    ),
                ))
    return findings
