from app.models import Category, Finding, MetadataBundle, QueryProfile, Severity


def check_missing_join_predicate(profile: QueryProfile,
                                  bundle: MetadataBundle) -> list[Finding]:
    findings = []
    for join in profile.joins:
        if join.join_type == "CROSS":
            continue
        if not join.predicates:
            findings.append(Finding(
                category=Category.JOINS, severity=Severity.CRITICAL,
                title=f"Missing JOIN predicate: {join.left_table} ↔ {join.right_table}",
                explanation=(
                    f"The JOIN between '{join.left_table}' and '{join.right_table}' has no ON "
                    f"clause. This produces a Cartesian product — every row from the left table "
                    f"matched with every row from the right. Add an ON clause."
                ),
            ))
    return findings


def check_join_type_mismatch(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    findings = []
    alias_to_table = {t.alias: t for t in profile.tables if t.alias}

    for join in profile.joins:
        for pred in join.predicates:
            left_col = pred.column
            rhs = pred.value_expr.strip()
            if "." not in rhs:
                continue
            rhs_alias, rhs_col = rhs.split(".", 1)

            left_table = alias_to_table.get(pred.table_alias)
            right_table = alias_to_table.get(rhs_alias)
            if not left_table or not right_table:
                continue

            left_key = f"{left_table.schema_name}.{left_table.name}".lower()
            right_key = f"{right_table.schema_name}.{right_table.name}".lower()

            left_type = _col_type(bundle, left_key, left_col)
            right_type = _col_type(bundle, right_key, rhs_col)

            if left_type and right_type and left_type.lower() != right_type.lower():
                title = (
                    f"Join type mismatch: {left_col} ({left_type}) ↔ "
                    f"{rhs_col} ({right_type})"
                )
                findings.append(Finding(
                    category=Category.JOINS, severity=Severity.WARNING,
                    title=title,
                    explanation=(
                        f"Joining '{left_col}' ({left_type}) to '{rhs_col}' "
                        f"({right_type}) forces an implicit type conversion on "
                        f"every row, preventing index use. Ensure join columns "
                        f"have the same data type."
                    ),
                ))
    return findings


def check_join_column_not_indexed(profile: QueryProfile,
                                   bundle: MetadataBundle) -> list[Finding]:
    findings = []
    alias_to_table = {t.alias: t for t in profile.tables if t.alias}

    for join in profile.joins:
        for pred in join.predicates:
            left_table = alias_to_table.get(pred.table_alias)
            if not left_table:
                continue
            key = f"{left_table.schema_name}.{left_table.name}".lower()
            if key not in bundle.tables:
                continue
            meta = bundle.tables[key]
            indexed_cols = {c for idx in meta.indexes for c in idx.key_columns}
            if pred.column not in indexed_cols:
                title = (
                    f"Join column '{pred.column}' not indexed on "
                    f"{left_table.name}"
                )
                explanation = (
                    f"The join column '{pred.column}' on '{left_table.name}' "
                    f"has no index. SQL Server will scan the table for each "
                    f"matching row. Adding an index on '{pred.column}' may "
                    f"significantly improve join performance."
                )
                findings.append(Finding(
                    category=Category.JOINS, severity=Severity.WARNING,
                    title=title,
                    explanation=explanation,
                ))
    return findings


def _col_type(bundle: MetadataBundle, table_key: str, col_name: str) -> str | None:
    if table_key not in bundle.tables:
        return None
    for col in bundle.tables[table_key].columns:
        if col.column_name.lower() == col_name.lower():
            return col.data_type
    return None
