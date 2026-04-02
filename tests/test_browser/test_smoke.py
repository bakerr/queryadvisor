# tests/test_browser/test_smoke.py
import pytest
from playwright.sync_api import Page, expect


def test_page_title(page: Page, live_server: str) -> None:
    """The index page title is 'QueryAdvisor'."""
    page.goto(live_server)
    expect(page).to_have_title("QueryAdvisor")


def test_form_elements_visible(page: Page, live_server: str) -> None:
    """All required form inputs are visible on the index page."""
    page.goto(live_server)
    expect(page.locator("#username")).to_be_visible()
    expect(page.locator("#database")).to_be_visible()
    expect(page.locator("#sql")).to_be_visible()
    expect(page.locator("button[type='submit']")).to_be_visible()


@pytest.mark.requires_db
def test_database_dropdown_populates(page: Page, live_server: str) -> None:
    """Database <select> is populated by HTMX on page load (requires live DB)."""
    page.goto(live_server)
    # HTMX fires GET /api/databases/options on load; wait for a real option value
    select = page.locator("#database")
    page.wait_for_function(
        """() => {
            const sel = document.querySelector('#database');
            return sel && sel.options.length > 0 && sel.options[0].value !== '';
        }"""
    )
    # At least one option should have a non-empty value
    first_option = select.locator("option").first
    expect(first_option).not_to_have_text("Loading...")
