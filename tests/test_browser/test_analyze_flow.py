# tests/test_browser/test_analyze_flow.py
import pytest
from playwright.sync_api import Page, expect

# A query guaranteed to produce at least one finding (SELECT * triggers a style rule)
_TEST_SQL = "SELECT * FROM dbo.Orders"
_TEST_DB = "QueryAdvisorSample"
_TEST_USER = "browser-test"


@pytest.mark.requires_db
def test_analyze_happy_path_list_view(page: Page, live_server: str) -> None:
    """Submit a SQL query and verify the results render in list view."""
    page.goto(live_server)

    # Wait for DB dropdown to populate, then select QueryAdvisorSample
    page.wait_for_function(
        """() => {
            const sel = document.querySelector('#database');
            return sel && Array.from(sel.options).some(o => o.value === 'QueryAdvisorSample');
        }"""
    )
    page.locator("#username").fill(_TEST_USER)
    page.locator("#database").select_option(_TEST_DB)
    page.locator("#sql").fill(_TEST_SQL)

    # Submit the form; HTMX POSTs to /api/analyze and swaps #results
    page.locator("button[type='submit']").click()

    # Wait for the report card to appear inside #results
    results = page.locator("#results")
    expect(results.locator(".report-card")).to_be_visible(timeout=15000)

    # Grade letter is rendered (A–F)
    grade = results.locator(".grade-letter")
    expect(grade).to_be_visible()
    grade_text = grade.inner_text()
    assert grade_text in {"A", "B", "C", "D", "F"}, f"Unexpected grade: {grade_text!r}"


@pytest.mark.requires_db
def test_analyze_happy_path_annotated_view(page: Page, live_server: str) -> None:
    """After analyzing, clicking 'Annotated SQL' renders the annotated view."""
    page.goto(live_server)

    # Wait for DB dropdown to populate
    page.wait_for_function(
        """() => {
            const sel = document.querySelector('#database');
            return sel && Array.from(sel.options).some(o => o.value === 'QueryAdvisorSample');
        }"""
    )
    page.locator("#username").fill(_TEST_USER)
    page.locator("#database").select_option(_TEST_DB)
    page.locator("#sql").fill(_TEST_SQL)
    page.locator("button[type='submit']").click()

    # Wait for results to load
    expect(page.locator("#results .report-card")).to_be_visible(timeout=15000)

    # Click the Annotated SQL toggle; HTMX swaps #detail-panel
    page.locator("button", has_text="Annotated SQL").click()

    # The .annotated-sql div is rendered inside #detail-panel
    expect(page.locator("#detail-panel .annotated-sql")).to_be_visible(timeout=10000)
