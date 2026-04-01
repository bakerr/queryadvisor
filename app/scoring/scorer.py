from app.models import Category, CategoryScore, Finding, ReportCard, Severity

_DEDUCTIONS = {Severity.CRITICAL: 20, Severity.WARNING: 10, Severity.INFO: 3}
_GRADES = [(90, "A"), (80, "B"), (70, "C"), (60, "D"), (0, "F")]


def _grade(score: int) -> str:
    for threshold, letter in _GRADES:
        if score >= threshold:
            return letter
    return "F"


def score_findings(findings: list[Finding]) -> ReportCard:
    total = sum(_DEDUCTIONS[f.severity] for f in findings)
    score = max(0, 100 - total)

    category_scores = []
    for cat in Category:
        cat_findings = [f for f in findings if f.category == cat]
        cat_total = sum(_DEDUCTIONS[f.severity] for f in cat_findings)
        cat_score = max(0, 100 - cat_total)
        category_scores.append(
            CategoryScore(category=cat, score=cat_score, grade=_grade(cat_score))
        )

    return ReportCard(
        score=score,
        grade=_grade(score),
        category_scores=category_scores,
        findings=findings,
    )
