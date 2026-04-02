# tests/test_browser/test_load_dotenv.py
"""Unit tests for _load_dotenv() in tests/test_browser/conftest.py."""
import pytest

import tests.test_browser.conftest as conftest_module


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


def test_missing_env_file_returns_empty():
    # No .env written — tmp_path/.env does not exist
    assert conftest_module._load_dotenv() == {}


def test_password_with_double_quotes(tmp_path):
    """Regression test: the exact scenario from issue #33."""
    (tmp_path / ".env").write_text('MSSQL_SA_PASSWORD="ThuperThecret1!"\n')
    assert conftest_module._load_dotenv() == {"MSSQL_SA_PASSWORD": "ThuperThecret1!"}


def test_value_with_equals_sign(tmp_path):
    """partition('=') captures only the first '=', so values like DSNs are preserved."""
    (tmp_path / ".env").write_text("KEY=a=b\n")
    assert conftest_module._load_dotenv() == {"KEY": "a=b"}


def test_inline_comment_is_part_of_value(tmp_path):
    """Inline comments are NOT stripped — the full string after '=' is the value."""
    (tmp_path / ".env").write_text("KEY=value # comment\n")
    assert conftest_module._load_dotenv() == {"KEY": "value # comment"}
