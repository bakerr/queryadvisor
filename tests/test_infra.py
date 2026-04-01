"""
Static analysis tests for infra files.
Ensures credentials are never passed as CLI arguments.
"""
from pathlib import Path

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
