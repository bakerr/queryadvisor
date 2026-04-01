from app.models import Finding, Severity, Category
from app.scoring.scorer import score_findings


def _finding(sev: Severity) -> Finding:
    return Finding(category=Category.STYLE, severity=sev, title="x", explanation="y")


def test_no_findings_scores_100():
    card = score_findings([])
    assert card.score == 100
    assert card.grade == "A"


def test_one_critical_deducts_20():
    card = score_findings([_finding(Severity.CRITICAL)])
    assert card.score == 80
    assert card.grade == "B"


def test_one_warning_deducts_10():
    card = score_findings([_finding(Severity.WARNING)])
    assert card.score == 90
    assert card.grade == "A"


def test_score_floors_at_zero():
    findings = [_finding(Severity.CRITICAL)] * 10
    card = score_findings(findings)
    assert card.score == 0
    assert card.grade == "F"


def test_category_scores_computed():
    findings = [
        Finding(category=Category.INDEXING, severity=Severity.CRITICAL, title="x", explanation="y"),
        Finding(category=Category.STYLE, severity=Severity.INFO, title="x", explanation="y"),
    ]
    card = score_findings(findings)
    idx_score = next(s for s in card.category_scores if s.category == Category.INDEXING)
    style_score = next(s for s in card.category_scores if s.category == Category.STYLE)
    assert idx_score.score == 80
    assert style_score.score == 97
