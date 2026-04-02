# Playwright Browser Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Playwright end-to-end browser tests covering smoke checks and the full analyze happy-path flow against a real server and SQL Server instance.

**Architecture:** A `live_server` session-scoped fixture starts a real uvicorn subprocess on a free port so Playwright drives an actual HTTP server. A `requires_db` pytest marker gates tests that need SQL Server — they are skipped when the container is not running. Smoke tests (no DB) and flow tests (requires DB) live in `tests/test_browser/`.

**Tech Stack:** pytest-playwright, Playwright (Chromium headless), uvicorn subprocess, pytest markers, pyproject.toml marker registration

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `pyproject.toml` | Modify | Add `pytest-playwright` to dev deps; register `requires_db` marker |
| `Makefile` | Modify | Add `browser-deps` target for `playwright install chromium` |
| `tests/test_browser/__init__.py` | Create | Package marker |
| `tests/test_browser/conftest.py` | Create | `live_server` fixture + `requires_db` skip hook |
| `tests/test_browser/test_smoke.py` | Create | Page load, form visibility, dropdown population |
| `tests/test_browser/test_analyze_flow.py` | Create | Full submit → results → view-toggle flow |

---

### Task 1: Add dependencies, Makefile target, and register pytest marker

**Files:**
- Modify: `pyproject.toml`
- Modify: `Makefile`

- [ ] **Step 1: Add `pytest-playwright` to dev dependencies in `pyproject.toml`**

In `pyproject.toml`, update `[project.optional-dependencies]`:

```toml
[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.23",
    "httpx>=0.27",
    "ruff>=0.4",
    "pytest-playwright>=0.5",
]
```

- [ ] **Step 2: Register the `requires_db` marker in `pyproject.toml`**

In `pyproject.toml`, update `[tool.pytest.ini_options]`:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
markers = [
    "requires_db: mark test as requiring a live SQL Server at localhost:1433",
]
```

- [ ] **Step 3: Add `browser-deps` target to `Makefile`**

After the existing `.PHONY` line, add `browser-deps` to the phony list and add the target:

```makefile
.PHONY: db-start db-stop db-status db-logs db-shell db-reset db-seed browser-deps help
```

Add before the `help` target:

```makefile
browser-deps: ## Install Playwright Chromium browser binary
	uv run playwright install chromium
```

- [ ] **Step 4: Install the dependency**

```bash
uv sync --extra dev
```

Expected: resolves and installs `pytest-playwright` and `playwright`.

- [ ] **Step 5: Install Chromium**

```bash
uv run playwright install chromium
```

Expected: Downloads Chromium browser binary. Output ends with something like `✓ Chromium ... downloaded`.

- [ ] **Step 6: Commit**

```bash
git add pyproject.toml Makefile uv.lock
git commit -m "feat: add pytest-playwright dev dependency and browser-deps Makefile target"
```

---

### Task 2: Create `tests/test_browser/conftest.py` with `live_server` and `requires_db`

**Files:**
- Create: `tests/test_browser/__init__.py`
- Create: `tests/test_browser/conftest.py`

- [ ] **Step 1: Create the package marker**

Create `tests/test_browser/__init__.py` as an empty file.

- [ ] **Step 2: Write `tests/test_browser/conftest.py`**

```python
# tests/test_browser/conftest.py
import socket
import subprocess
import time

import pytest


def _find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


def _db_reachable() -> bool:
    try:
        with socket.create_connection(("localhost", 1433), timeout=2):
            return True
    except OSError:
        return False


@pytest.fixture(scope="session")
def live_server():
    """Start a real uvicorn server subprocess and yield its base URL."""
    port = _find_free_port()
    proc = subprocess.Popen(
        [
            "uv", "run", "uvicorn", "app.main:app",
            "--host", "127.0.0.1",
            "--port", str(port),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    # Wait up to 15 seconds for the server to accept connections
    for _ in range(30):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                break
        except OSError:
            time.sleep(0.5)
    else:
        proc.terminate()
        proc.wait(timeout=5)
        pytest.fail("live_server did not start within 15 seconds")

    yield f"http://127.0.0.1:{port}"

    proc.terminate()
    proc.wait(timeout=5)


def pytest_collection_modifyitems(items: list) -> None:
    """Skip requires_db tests when SQL Server is not reachable."""
    if _db_reachable():
        return
    skip = pytest.mark.skip(reason="SQL Server not reachable at localhost:1433 — run `make db-start`")
    for item in items:
        if item.get_closest_marker("requires_db"):
            item.add_marker(skip)
```

- [ ] **Step 3: Verify fixtures are collected without error**

```bash
uv run pytest tests/test_browser/ --collect-only
```

Expected output: `no tests ran` (no test files yet) with no errors. If you see `ERROR`, check for import issues in conftest.py.

- [ ] **Step 4: Commit**

```bash
git add tests/test_browser/__init__.py tests/test_browser/conftest.py
git commit -m "feat: add live_server fixture and requires_db skip hook for browser tests"
```

---

### Task 3: Write and verify smoke tests

**Files:**
- Create: `tests/test_browser/test_smoke.py`

These tests do **not** need SQL Server for the first two cases. The dropdown-population test requires the DB and is marked accordingly.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_browser/test_smoke.py`:

```python
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
```

- [ ] **Step 2: Run the two non-DB smoke tests (expect PASS)**

```bash
uv run pytest tests/test_browser/test_smoke.py -m "not requires_db" -v
```

Expected:
```
tests/test_browser/test_smoke.py::test_page_title PASSED
tests/test_browser/test_smoke.py::test_form_elements_visible PASSED
```

If they fail, check that the live_server fixture starts cleanly (add `-s` flag to see subprocess output).

- [ ] **Step 3: Commit**

```bash
git add tests/test_browser/test_smoke.py
git commit -m "test: add Playwright smoke tests for page load and form visibility"
```

---

### Task 4: Write and verify the happy-path analyze flow test

**Files:**
- Create: `tests/test_browser/test_analyze_flow.py`

This test requires a running SQL Server with the QueryAdvisorSample database seeded (`make db-seed`).

- [ ] **Step 1: Write the test**

Create `tests/test_browser/test_analyze_flow.py`:

```python
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
```

- [ ] **Step 2: With SQL Server running, run the requires_db tests**

First ensure the DB is running and seeded:
```bash
make db-start
# wait ~30s for container health check, then:
make db-seed
```

Then run:
```bash
uv run pytest tests/test_browser/ -m requires_db -v
```

Expected:
```
tests/test_browser/test_smoke.py::test_database_dropdown_populates PASSED
tests/test_browser/test_analyze_flow.py::test_analyze_happy_path_list_view PASSED
tests/test_browser/test_analyze_flow.py::test_analyze_happy_path_annotated_view PASSED
```

- [ ] **Step 3: Verify skip behavior without DB**

Stop the container, then run:
```bash
make db-stop
uv run pytest tests/test_browser/ -v
```

Expected: the three `requires_db` tests show `SKIPPED` with reason `SQL Server not reachable at localhost:1433`. The two non-DB smoke tests show `PASSED`.

- [ ] **Step 4: Commit**

```bash
git add tests/test_browser/test_analyze_flow.py
git commit -m "test: add Playwright happy-path analyze flow tests (requires_db)"
```

---

### Task 5: Final verification — full suite unaffected

- [ ] **Step 1: Run the existing test suite with the new marker filter**

```bash
uv run pytest tests/ -m "not requires_db" -v
```

Expected: all previously-passing tests still pass. No new failures.

- [ ] **Step 2: Run lint**

```bash
uv run ruff check .
```

Expected: no errors.

- [ ] **Step 3: Confirm headless mode is default**

pytest-playwright defaults to `--browser chromium` and headless. Verify by checking no `--headed` flag is needed:

```bash
uv run pytest tests/test_browser/ -m "not requires_db" -v --browser chromium
```

Expected: tests pass without a visible browser window.

- [ ] **Step 4: Commit final state if any lint fixes were needed**

```bash
git add -p
git commit -m "chore: fix any lint issues in browser test files"
```

(Skip if ruff reported no errors.)
