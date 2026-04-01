# Hide SA Password from Process Table — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate `MSSQL_SA_PASSWORD` from CLI arguments visible in `ps aux` by using `SQLCMDPASSWORD` env var in the Makefile and compose.yaml healthcheck, and scope the bare Makefile `export`.

**Architecture:** Two config files change — `Makefile` and `compose.yaml`. A new `tests/test_infra.py` enforces the constraint via static analysis of those files so regressions are caught immediately.

**Tech Stack:** Make, Docker Compose (podman-compose), sqlcmd, pytest

---

### Task 1: Write failing infra tests

**Files:**
- Create: `tests/test_infra.py`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_infra.py` with the following content:

```python
"""
Static analysis tests for infra files.
Ensures credentials are never passed as CLI arguments.
"""
from pathlib import Path

ROOT = Path(__file__).parent.parent


def test_makefile_dbshell_no_dash_p():
    """db-shell must not pass -P to sqlcmd (visible in ps aux)."""
    makefile = (ROOT / "Makefile").read_text()
    # Find the db-shell recipe lines
    in_recipe = False
    for line in makefile.splitlines():
        if line.startswith("db-shell:"):
            in_recipe = True
            continue
        if in_recipe:
            if line and not line[0].isspace():
                break  # next target, done
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/lowell/projects/work/queryadvisor
.venv/bin/pytest tests/test_infra.py -v
```

Expected: 3–4 failures:
```
FAILED tests/test_infra.py::test_makefile_dbshell_no_dash_p
FAILED tests/test_infra.py::test_makefile_no_bare_export
FAILED tests/test_infra.py::test_compose_healthcheck_no_dash_p
FAILED tests/test_infra.py::test_compose_sqlcmdpassword_env_set
```

- [ ] **Step 3: Commit the failing tests**

```bash
git add tests/test_infra.py
git commit -m "test: add infra tests asserting no -P credential exposure"
```

---

### Task 2: Fix Makefile

**Files:**
- Modify: `Makefile` (lines 5, 23–24)

Current state:
```makefile
-include .env
export

DB_COMPOSE := podman-compose -f compose.yaml
...
db-shell: ## Open a sqlcmd session against the running container
	$(DB_COMPOSE) exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
		-S localhost -U sa -P "$(MSSQL_SA_PASSWORD)" -C
```

- [ ] **Step 1: Replace bare `export` with scoped export**

Edit `Makefile` line 5: replace `export` with:
```makefile
export MSSQL_SA_PASSWORD SQL_SERVER_HOST SQL_AUTH_METHOD ODBC_DRIVER
```

The complete top of the file should look like:
```makefile
.PHONY: db-start db-stop db-status db-logs db-shell db-reset help

# Load .env if it exists (provides MSSQL_SA_PASSWORD etc.)
-include .env
export MSSQL_SA_PASSWORD SQL_SERVER_HOST SQL_AUTH_METHOD ODBC_DRIVER

DB_COMPOSE := podman-compose -f compose.yaml
```

- [ ] **Step 2: Replace `-P` in db-shell with SQLCMDPASSWORD**

Edit the `db-shell` target to:
```makefile
db-shell: ## Open a sqlcmd session against the running container
	SQLCMDPASSWORD="$(MSSQL_SA_PASSWORD)" \
	$(DB_COMPOSE) exec -e SQLCMDPASSWORD sqlserver \
		/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C
```

- [ ] **Step 3: Run the infra tests — expect 2 passing, 2 still failing**

```bash
.venv/bin/pytest tests/test_infra.py -v
```

Expected:
```
PASSED tests/test_infra.py::test_makefile_dbshell_no_dash_p
PASSED tests/test_infra.py::test_makefile_no_bare_export
FAILED tests/test_infra.py::test_compose_healthcheck_no_dash_p
FAILED tests/test_infra.py::test_compose_sqlcmdpassword_env_set
```

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "fix: scope Makefile export and use SQLCMDPASSWORD in db-shell"
```

---

### Task 3: Fix compose.yaml healthcheck

**Files:**
- Modify: `compose.yaml`

Current state:
```yaml
services:
  sqlserver:
    image: mcr.microsoft.com/mssql/server:2022-latest
    environment:
      ACCEPT_EULA: "Y"
      MSSQL_SA_PASSWORD: "${MSSQL_SA_PASSWORD}"
    ports:
      - "1433:1433"
    volumes:
      - "${HOME}/.queryadvisor/sqlserver:/var/opt/mssql"
    healthcheck:
      test:
        - CMD-SHELL
        - >
          /opt/mssql-tools18/bin/sqlcmd
          -S localhost -U sa -P "$$MSSQL_SA_PASSWORD" -C -Q "SELECT 1"
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s
```

- [ ] **Step 1: Add SQLCMDPASSWORD to container environment and remove -P from healthcheck**

Replace the entire `compose.yaml` with:
```yaml
services:
  sqlserver:
    image: mcr.microsoft.com/mssql/server:2022-latest
    environment:
      ACCEPT_EULA: "Y"
      MSSQL_SA_PASSWORD: "${MSSQL_SA_PASSWORD}"
      SQLCMDPASSWORD: "${MSSQL_SA_PASSWORD}"
    ports:
      - "1433:1433"
    volumes:
      - "${HOME}/.queryadvisor/sqlserver:/var/opt/mssql"
    healthcheck:
      test:
        - CMD-SHELL
        - >
          /opt/mssql-tools18/bin/sqlcmd
          -S localhost -U sa -C -Q "SELECT 1"
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s
```

- [ ] **Step 2: Run all infra tests — expect all 4 passing**

```bash
.venv/bin/pytest tests/test_infra.py -v
```

Expected:
```
PASSED tests/test_infra.py::test_makefile_dbshell_no_dash_p
PASSED tests/test_infra.py::test_makefile_no_bare_export
PASSED tests/test_infra.py::test_compose_healthcheck_no_dash_p
PASSED tests/test_infra.py::test_compose_sqlcmdpassword_env_set
```

- [ ] **Step 3: Run full test suite to confirm no regressions**

```bash
.venv/bin/pytest -v
```

Expected: all tests pass (infra + existing suite).

- [ ] **Step 4: Commit**

```bash
git add compose.yaml
git commit -m "fix: use SQLCMDPASSWORD env var in healthcheck; remove -P flag"
```

---

### Self-Review

**Spec coverage:**
- ✅ Requirement 1 (no -P in ps aux): Task 2 Step 2
- ✅ Requirement 2 (scoped export): Task 2 Step 1
- ✅ Requirement 3 (compose.yaml healthcheck): Task 3 Step 1
- ✅ All three sub-tasks from issue covered
- ✅ All five acceptance criteria testable via `tests/test_infra.py`

**Placeholder scan:** None found.

**Type consistency:** N/A — no shared types across tasks (config-only changes).
