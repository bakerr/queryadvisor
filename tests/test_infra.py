"""
Static analysis tests for infra files.
Ensures credentials are never passed as CLI arguments.
"""
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent


def test_makefile_dbshell_no_dash_p():
    """db-shell must not pass -P to sqlcmd (visible in ps aux)."""
    makefile = (ROOT / "Makefile").read_text()
    in_recipe = False
    for line in makefile.splitlines():
        if line.startswith("db-shell:"):
            in_recipe = True
            continue
        if in_recipe:
            if line and not line[0].isspace():
                break
            assert '-P "$(MSSQL_SA_PASSWORD)"' not in line, (
                "db-shell passes password as -P argument — visible in ps aux"
            )


def test_makefile_no_bare_export():
    """Bare `export` exports all Make variables; must be scoped."""
    makefile = (ROOT / "Makefile").read_text()
    for line in makefile.splitlines():
        stripped = line.strip()
        assert stripped != "export", (
            "Bare `export` found in Makefile — use `export VAR1 VAR2 ...` instead"
        )


def test_compose_healthcheck_no_dash_p():
    """Healthcheck command must not pass -P to sqlcmd."""
    compose = (ROOT / "compose.yaml").read_text()
    assert '-P "$$MSSQL_SA_PASSWORD"' not in compose, (
        "compose.yaml healthcheck passes password as -P argument"
    )


def test_compose_sqlcmdpassword_env_set():
    """SQLCMDPASSWORD must be declared in the container environment."""
    compose = (ROOT / "compose.yaml").read_text()
    assert "SQLCMDPASSWORD" in compose, (
        "compose.yaml must set SQLCMDPASSWORD in container environment "
        "so healthcheck can authenticate without -P"
    )


def test_seed_script_uses_get_connection():
    """seed_db.py must import from app.config, not hardcode credentials."""
    script = (ROOT / "scripts" / "seed_db.py").read_text()
    assert "from app.config import get_connection" in script, (
        "seed_db.py must use app.config.get_connection, not build its own connection"
    )
    assert "PWD=" not in script, "seed_db.py must not contain hardcoded credentials"
    assert "MSSQL_SA_PASSWORD" not in script, (
        "seed_db.py must not read MSSQL_SA_PASSWORD directly — delegate to get_connection"
    )


def test_makefile_has_db_seed_target():
    """Makefile must have a db-seed target."""
    makefile = (ROOT / "Makefile").read_text()
    assert "db-seed:" in makefile, "Makefile must have a db-seed target"


def test_db_seed_calls_uv_run():
    """db-seed Makefile target must invoke seed_db.py via uv run."""
    makefile = (ROOT / "Makefile").read_text()
    in_recipe = False
    for line in makefile.splitlines():
        if line.startswith("db-seed:"):
            in_recipe = True
            continue
        if in_recipe:
            if line and not line[0].isspace():
                break
            if "uv run" in line and "seed_db" in line:
                return
    pytest.fail("db-seed target does not invoke 'uv run ... seed_db.py'")
