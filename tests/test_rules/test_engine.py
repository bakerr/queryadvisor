from app.models import QueryProfile, MetadataBundle, Category
from app.rules.engine import evaluate_rules


def test_evaluate_rules_returns_list():
    profile = QueryProfile(selected_columns=["*"])
    findings = evaluate_rules(profile, MetadataBundle())
    assert isinstance(findings, list)


def test_evaluate_rules_detects_select_star():
    profile = QueryProfile(selected_columns=["*"])
    findings = evaluate_rules(profile, MetadataBundle())
    categories = [f.category for f in findings]
    assert Category.STYLE in categories
