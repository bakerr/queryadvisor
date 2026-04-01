from app.models import Category, Finding, MetadataBundle, QueryProfile, Severity


def check_select_star(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    if "*" not in profile.selected_columns:
        return []
    return [Finding(
        category=Category.STYLE, severity=Severity.WARNING,
        title="SELECT * detected",
        explanation=(
            "SELECT * retrieves every column, preventing covering index scans and increasing "
            "network traffic. List only the columns you need."
        ),
    )]


def check_order_without_paging(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    if not profile.has_order_by or profile.has_top_or_offset:
        return []
    return [Finding(
        category=Category.STYLE, severity=Severity.INFO,
        title="ORDER BY without TOP or OFFSET",
        explanation=(
            "Sorting a full result set forces SQL Server to process all rows before returning any. "
            "Remove ORDER BY if the application doesn't require sorted output, or add "
            "TOP / OFFSET...FETCH NEXT for paging."
        ),
    )]


def check_unnecessary_distinct(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    if not profile.has_distinct:
        return []
    return [Finding(
        category=Category.STYLE, severity=Severity.INFO,
        title="DISTINCT detected",
        explanation=(
            "DISTINCT requires SQL Server to sort or hash the full result set. "
            "If duplicates arise from unnecessary JOINs, restructure the query to avoid "
            "them rather than filtering them after the fact."
        ),
    )]


def check_redundant_join(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    findings = []
    referenced_via_alias: set[str] = set()
    for col in profile.selected_columns:
        if "." in col:
            referenced_via_alias.add(col.split(".")[0].lower())
    for pred in profile.where_predicates:
        if pred.table_alias:
            referenced_via_alias.add(pred.table_alias.lower())

    for join in profile.joins:
        if join.join_type in ("CROSS", "FULL"):
            continue
        rt = join.right_table.lower()
        aliases = {
            t.alias.lower() for t in profile.tables
            if t.name.lower() == rt and t.alias
        }
        if rt not in referenced_via_alias and not (aliases & referenced_via_alias):
            findings.append(Finding(
                category=Category.STYLE, severity=Severity.WARNING,
                title=f"Possibly redundant JOIN on {join.right_table}",
                explanation=(
                    f"'{join.right_table}' is joined but none of its columns appear in "
                    f"SELECT or WHERE. If not needed for filtering, removing this JOIN "
                    f"will improve performance."
                ),
            ))
    return findings
