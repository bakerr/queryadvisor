# Fix _load_dotenv() Quote Stripping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix `_load_dotenv()` in `tests/test_browser/conftest.py` to strip matching surrounding quotes from `.env` values, preventing silent authentication failures when `.env` files use quoted values.

**Architecture:** Add quote-stripping logic after the existing `value.strip()` call at line 24. Test via a new unit test file that uses `monkeypatch` to redirect `_REPO_ROOT` to a `tmp_path`, allowing isolated `.env` content testing without touching the real `.env` file or changing the function signature.

**Tech Stack:** Python 3.14+, pytest, monkeypatch, tmp_path

---

### Task 1: Write failing unit tests for `_load_dotenv()`

**Files:**
- Create: `tests/test_browser/test_load_dotenv.py`

- [ ] **Step 1: Create the test file with all required cases**

Create `tests/test_browser/test_load_dotenv.py` with this exact content:

```python
# tests/test_browser/test_load_dotenv.py
"""Unit tests for _load_dotenv() in tests/test_browser/conftest.py."""
from pathlib import Path

import pytest

import tests.test_browser.conftest as conftest_module


def _write_env(tmp_path: Path, content: str) -> None:
    """Write .env content to tmp_path/.env and redirect _REPO_ROOT."""


@pytest.fixture(autouse=True)
def redirect_repo_root(tmp_path, monkeypatch):
    """Redirect _REPO_ROOT so _load_dotenv() reads from tmp_path/.env."""
    monkeypatch.setattr(conftest_module, "_REPO_ROOT", tmp_path)


def test_bare_value(tmp_path):
    (tmp_path / ".env").write_text("KEY=value\n")
    assert conftest_module._load_dotenv() == {"KEY": "value"}


def test_double_quoted_value(tmp_path):
    (tmp_path / ".env").write_text('KEY="value"\n')
    assert conftest_module._load_dotenv() == {"KEY": "value"}


def test_single_quoted_value(tmp_path):
    (tmp_path / ".env").write_text("KEY='value'\n")
    assert conftest_module._load_dotenv() == {"KEY": "value"}


def test_mismatched_quotes_unchanged(tmp_path):
    (tmp_path / ".env").write_text("KEY=\"foo'\n")
    assert conftest_module._load_dotenv() == {"KEY": "\"foo'"}


def test_empty_double_quoted(tmp_path):
    (tmp_path / ".env").write_text('KEY=""\n')
    assert conftest_module._load_dotenv() == {"KEY": ""}


def test_internal_quotes_unchanged(tmp_path):
    (tmp_path / ".env").write_text('KEY=foo"bar\n')
    assert conftest_module._load_dotenv() == {"KEY": 'foo"bar'}


def test_comment_lines_ignored(tmp_path):
    (tmp_path / ".env").write_text("# comment\nKEY=value\n")
    assert conftest_module._load_dotenv() == {"KEY": "value"}


def test_blank_lines_ignored(tmp_path):
    (tmp_path / ".env").write_text("\nKEY=value\n\n")
    assert conftest_module._load_dotenv() == {"KEY": "value"}


def test_missing_env_file_returns_empty(tmp_path):
    # No .env written — tmp_path/.env does not exist
    assert conftest_module._load_dotenv() == {}


def test_password_with_double_quotes(tmp_path):
    """Regression test: the exact scenario from issue #33."""
    (tmp_path / ".env").write_text('MSSQL_SA_PASSWORD="ThuperThecret1!"\n')
    assert conftest_module._load_dotenv() == {"MSSQL_SA_PASSWORD": "ThuperThecret1!"}
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
cd /Users/lowell/projects/work/queryadvisor
uv run pytest tests/test_browser/test_load_dotenv.py -v
```

Expected output: Several FAILED assertions — `test_double_quoted_value`, `test_single_quoted_value`, `test_empty_double_quoted`, and `test_password_with_double_quotes` should fail because the current code returns values with literal quote characters.

---

### Task 2: Apply the quote-stripping fix

**Files:**
- Modify: `tests/test_browser/conftest.py:24`

- [ ] **Step 1: Apply the fix**

In `tests/test_browser/conftest.py`, replace line 24:

```python
            env[key.strip()] = value.strip()
```

with:

```python
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                value = value[1:-1]
            env[key.strip()] = value
```

The full updated `_load_dotenv()` function should look like this:

```python
def _load_dotenv() -> dict[str, str]:
    """Load key=value pairs from .env at repo root, ignoring comments and blanks."""
    env: dict[str, str] = {}
    dotenv = _REPO_ROOT / ".env"
    try:
        for line in dotenv.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, value = line.partition("=")
                value = value.strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                    value = value[1:-1]
                env[key.strip()] = value
    except FileNotFoundError:
        pass
    return env
```

- [ ] **Step 2: Run the unit tests to confirm they all pass**

```bash
uv run pytest tests/test_browser/test_load_dotenv.py -v
```

Expected output: All 10 tests PASSED.

- [ ] **Step 3: Commit**

```bash
git add tests/test_browser/test_load_dotenv.py tests/test_browser/conftest.py
git commit -m "fix: strip surrounding quotes from _load_dotenv() values (#33)

Quoted .env values like MSSQL_SA_PASSWORD=\"ThuperThecret1!\" were passed
to subprocesses with literal quote characters, causing silent auth failures.

Adds quote-stripping logic after value.strip() and adds a unit test covering
bare values, double-quoted, single-quoted, mismatched quotes, empty quotes,
internal quotes, comments, blank lines, missing file, and the regression case."
```

---

### Task 3: Final verification

**Files:** (read-only verification)

- [ ] **Step 1: Run the full test suite (non-browser tests)**

```bash
uv run pytest tests/ --ignore=tests/test_browser -v
```

Expected: All existing tests pass.

- [ ] **Step 2: Run lint**

```bash
uv run ruff check tests/test_browser/test_load_dotenv.py tests/test_browser/conftest.py
```

Expected: No lint errors.

- [ ] **Step 3: Confirm branch status**

```bash
git log --oneline -3
git status
```

Expected: Clean working tree, commit visible in log.
