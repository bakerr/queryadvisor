from app.models import Finding, MetadataBundle, QueryProfile
from app.rules import indexing, joins, predicates, style

_RULES = [
    style.check_select_star,
    style.check_order_without_paging,
    style.check_unnecessary_distinct,
    style.check_redundant_join,
    predicates.check_nonsargable_function,
    predicates.check_implicit_conversion,
    predicates.check_leading_wildcard,
    joins.check_missing_join_predicate,
    joins.check_join_type_mismatch,
    joins.check_join_column_not_indexed,
    indexing.check_missing_index_suggestion,
    indexing.check_table_scan,
    indexing.check_non_covering_index,
]


def evaluate_rules(profile: QueryProfile, bundle: MetadataBundle) -> list[Finding]:
    findings = []
    for rule in _RULES:
        findings.extend(rule(profile, bundle))
    return findings
