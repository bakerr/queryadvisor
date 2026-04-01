# Local SQL Server 2022 Dev Container Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set up a Podman-managed SQL Server 2022 dev container with persistent data, SA password via `.env`, a Makefile for lifecycle ops, and `app/config.py` support for both SQL and Windows/Kerberos auth.

**Architecture:** `compose.yaml` defines the SQL Server service and mounts `~/.queryadvisor/sqlserver` into the container. A `Makefile` wraps `podman-compose` with named targets. `app/config.py` gains a `build_connection_string()` helper that branches on `SQL_AUTH_METHOD` — `sql` for SA password auth, anything else for `Trusted_Connection=yes` (the prod default). Tests cover the connection string builder in isolation (no pyodbc import needed).

**Tech Stack:** Podman Compose, SQL Server 2022 (`mcr.microsoft.com/mssql/server:2022-latest`), Python `os.getenv`, GNU Make

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `app/config.py` | Extract `build_connection_string()` pure fn; add SQL auth branch |
| Create | `tests/test_config.py` | Unit tests for `build_connection_string()` — no pyodbc import |
| Create | `compose.yaml` | Podman Compose service for SQL Server 2022 |
| Create | `.env.example` | Reference env vars with placeholder values |
| Verify | `.gitignore` | `.env` already present — confirm, do not duplicate |
| Create | `Makefile` | `db-start`, `db-stop`, `db-status`, `db-logs`, `db-shell`, `db-reset` |
| Create | `docs/guides/local-dev-setup.md` | Dev setup walkthrough |

---

## Task 1: Refactor `app/config.py` — extract `build_connection_string()` and add SQL auth (TDD)

**Files:**
- Modify: `app/config.py`
- Create: `tests/test_config.py`

The existing `get_connection()` builds the conn string inline, making it impossible to unit-test without pyodbc. We extract it into a pure function and add the SQL auth branch.

- [ ] **Step 1.1: Write the failing tests**

Create `tests/test_config.py`:

```python
import os
import pytest
from unittest.mock import patch
from app.config import build_connection_string


def test_windows_auth_is_default():
    """No SQL_AUTH_METHOD → Trusted_Connection used."""
    env = {
        "SQL_SERVER_HOST": "localhost",
        "ODBC_DRIVER": "ODBC Driver 18 for SQL Server",
    }
    with patch.dict(os.environ, env, clear=True):
        conn_str = build_connection_string("testdb")
    assert "Trusted_Connection=yes" in conn_str
    assert "DATABASE=testdb" in conn_str
    assert "SERVER=localhost" in conn_str
    assert "PWD=" not in conn_str


def test_windows_auth_explicit():
    """SQL_AUTH_METHOD=windows → Trusted_Connection used."""
    env = {
        "SQL_AUTH_METHOD": "windows",
        "SQL_SERVER_HOST": "winhost",
        "ODBC_DRIVER": "ODBC Driver 18 for SQL Server",
    }
    with patch.dict(os.environ, env, clear=True):
        conn_str = build_connection_string("mydb")
    assert "Trusted_Connection=yes" in conn_str
    assert "SERVER=winhost" in conn_str
    assert "PWD=" not in conn_str


def test_sql_auth_connection_string():
    """SQL_AUTH_METHOD=sql → SA password, TrustServerCertificate."""
    env = {
        "SQL_AUTH_METHOD": "sql",
        "SQL_SERVER_HOST": "localhost",
        "MSSQL_SA_PASSWORD": "TestPass123!",
        "ODBC_DRIVER": "ODBC Driver 18 for SQL Server",
    }
    with patch.dict(os.environ, env, clear=True):
        conn_str = build_connection_string("mydb")
    assert "Trusted_Connection" not in conn_str
    assert "UID=sa" in conn_str
    assert "PWD=TestPass123!" in conn_str
    assert "TrustServerCertificate=yes" in conn_str
    assert "DATABASE=mydb" in conn_str
    assert "SERVER=localhost" in conn_str


def test_sql_auth_raises_without_password():
    """SQL_AUTH_METHOD=sql without MSSQL_SA_PASSWORD → ValueError."""
    env = {"SQL_AUTH_METHOD": "sql"}
    with patch.dict(os.environ, env, clear=True):
        with pytest.raises(ValueError, match="MSSQL_SA_PASSWORD"):
            build_connection_string("mydb")


def test_custom_driver_is_used():
    """ODBC_DRIVER env var propagates into the connection string."""
    env = {
        "ODBC_DRIVER": "ODBC Driver 17 for SQL Server",
        "SQL_SERVER_HOST": "localhost",
    }
    with patch.dict(os.environ, env, clear=True):
        conn_str = build_connection_string("mydb")
    assert "ODBC Driver 17 for SQL Server" in conn_str
```

- [ ] **Step 1.2: Run tests to verify they fail**

```bash
cd /Users/lowell/projects/work/queryadvisor
python -m pytest tests/test_config.py -v
```

Expected: `ImportError: cannot import name 'build_connection_string' from 'app.config'`

- [ ] **Step 1.3: Implement `build_connection_string()` and update `get_connection()`**

Replace the entire contents of `app/config.py` with:

```python
import os


def build_connection_string(database: str) -> str:
    server = os.getenv("SQL_SERVER_HOST", "localhost")
    driver = os.getenv("ODBC_DRIVER", "ODBC Driver 18 for SQL Server")
    auth_method = os.getenv("SQL_AUTH_METHOD", "windows")

    if auth_method == "sql":
        password = os.getenv("MSSQL_SA_PASSWORD")
        if not password:
            raise ValueError("MSSQL_SA_PASSWORD must be set when SQL_AUTH_METHOD=sql")
        return (
            f"DRIVER={{{driver}}};"
            f"SERVER={server};"
            f"DATABASE={database};"
            "UID=sa;"
            f"PWD={password};"
            "TrustServerCertificate=yes;"
        )

    return (
        f"DRIVER={{{driver}}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        "Trusted_Connection=yes;"
    )


def get_connection(database: str):
    import pyodbc  # noqa: PLC0415 — lazy import; pyodbc is a production dep only

    return pyodbc.connect(build_connection_string(database), timeout=10)
```

- [ ] **Step 1.4: Run tests to verify they pass**

```bash
python -m pytest tests/test_config.py -v
```

Expected output:
```
tests/test_config.py::test_windows_auth_is_default PASSED
tests/test_config.py::test_windows_auth_explicit PASSED
tests/test_config.py::test_sql_auth_connection_string PASSED
tests/test_config.py::test_sql_auth_raises_without_password PASSED
tests/test_config.py::test_custom_driver_is_used PASSED
5 passed
```

- [ ] **Step 1.5: Run the full test suite to confirm no regressions**

```bash
python -m pytest --tb=short -q
```

Expected: all previously passing tests still pass.

- [ ] **Step 1.6: Commit**

```bash
git add app/config.py tests/test_config.py
git commit -m "feat: add SQL auth support to config.py; extract build_connection_string"
```

---

## Task 2: Create `compose.yaml` and `.env.example`; verify `.gitignore`

**Files:**
- Create: `compose.yaml`
- Create: `.env.example`
- Verify: `.gitignore` (`.env` is already listed — no edit needed if confirmed)

- [ ] **Step 2.1: Verify `.gitignore` already excludes `.env`**

```bash
grep -n "^\.env$" .gitignore
```

Expected: a line number and `.env`. If the output is empty, add `.env` on its own line to `.gitignore` and note the addition. (As of the last read, `.env` is present — this is a confirmation step only.)

- [ ] **Step 2.2: Create `.env.example`**

Create the file `/.env.example`:

```bash
# Copy this file to .env and fill in your values.
# .env is gitignored — never commit it.

# SA password for the local SQL Server container.
# Min 8 chars, must include uppercase, lowercase, digit, and special char.
MSSQL_SA_PASSWORD=

# Hostname of the SQL Server instance (default: localhost for the dev container)
SQL_SERVER_HOST=localhost

# Auth method: "sql" for SA password auth, "windows" for Kerberos/Trusted_Connection
SQL_AUTH_METHOD=sql
```

- [ ] **Step 2.3: Create `compose.yaml`**

Create `compose.yaml` at the project root:

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

Notes:
- `${HOME}` is expanded by the shell at `podman-compose` invocation time.
- `$$MSSQL_SA_PASSWORD` inside `CMD-SHELL` is the YAML-escaped form of `$MSSQL_SA_PASSWORD` — the double-dollar escapes the compose variable substitution so it reaches the shell as a single `$`.
- The healthcheck uses `-C` (trust server certificate) because the container uses a self-signed cert.

- [ ] **Step 2.4: Validate compose.yaml parses correctly**

```bash
podman-compose -f compose.yaml config
```

Expected: YAML output with the resolved service config (no errors). If `podman-compose` is not installed, install it: `pip install podman-compose`.

- [ ] **Step 2.5: Commit**

```bash
git add compose.yaml .env.example
git commit -m "feat: add compose.yaml for SQL Server 2022 and .env.example"
```

---

## Task 3: Create `Makefile` with container lifecycle targets

**Files:**
- Create: `Makefile`

The Makefile loads `.env` so variables like `MSSQL_SA_PASSWORD` are available for `db-shell` without requiring the user to export them manually.

- [ ] **Step 3.1: Create `Makefile`**

Create `Makefile` at the project root:

```makefile
.PHONY: db-start db-stop db-status db-logs db-shell db-reset

# Load .env if it exists (provides MSSQL_SA_PASSWORD etc.)
-include .env
export

DB_COMPOSE := podman-compose -f compose.yaml

db-start: ## Start the SQL Server container (creates data dir if needed)
	mkdir -p $(HOME)/.queryadvisor/sqlserver
	$(DB_COMPOSE) up -d

db-stop: ## Stop the SQL Server container
	$(DB_COMPOSE) down

db-status: ## Show running container status
	podman ps --filter "name=sqlserver" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

db-logs: ## Tail SQL Server container logs
	$(DB_COMPOSE) logs -f sqlserver

db-shell: ## Open a sqlcmd session against the running container
	$(DB_COMPOSE) exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
		-S localhost -U sa -P "$(MSSQL_SA_PASSWORD)" -C

db-reset: ## DESTRUCTIVE: stop container and wipe all data in ~/.queryadvisor/sqlserver
	$(DB_COMPOSE) down
	rm -rf $(HOME)/.queryadvisor/sqlserver
	mkdir -p $(HOME)/.queryadvisor/sqlserver
	$(DB_COMPOSE) up -d

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-12s %s\n", $$1, $$2}'
```

- [ ] **Step 3.2: Verify Makefile parses without errors**

```bash
make --dry-run db-start
```

Expected output (dry run, no actual execution):
```
mkdir -p /Users/<you>/.queryadvisor/sqlserver
podman-compose -f compose.yaml up -d
```

If `make` reports a syntax error, fix it before proceeding.

- [ ] **Step 3.3: Commit**

```bash
git add Makefile
git commit -m "feat: add Makefile with db-start/stop/status/logs/shell/reset targets"
```

---

## Task 4: Add dev setup guide

**Files:**
- Create: `docs/guides/local-dev-setup.md`

- [ ] **Step 4.1: Create `docs/guides/local-dev-setup.md`**

```markdown
# Local Development Setup

This guide sets up a local SQL Server 2022 instance for development using Podman.

## Prerequisites

- [Podman](https://podman.io/getting-started/installation) installed and running
- `podman-compose` installed: `pip install podman-compose`
- GNU Make

## First-Time Setup

1. **Copy the env template and set your SA password:**

   ```bash
   cp .env.example .env
   ```

   Edit `.env` and set a strong SA password (min 8 chars, must include uppercase,
   lowercase, digit, and special character — SQL Server enforces this):

   ```
   MSSQL_SA_PASSWORD=YourStr0ng!Pass
   SQL_SERVER_HOST=localhost
   SQL_AUTH_METHOD=sql
   ```

2. **Start the container:**

   ```bash
   make db-start
   ```

   The data directory `~/.queryadvisor/sqlserver` is created automatically.
   SQL Server takes ~30 seconds to become ready on first start.

3. **Verify it's running:**

   ```bash
   make db-status
   ```

4. **Open a sqlcmd session:**

   ```bash
   make db-shell
   ```

## Daily Usage

| Command | Effect |
|---------|--------|
| `make db-start` | Start SQL Server container |
| `make db-stop` | Stop container (data persists) |
| `make db-status` | Show container health |
| `make db-logs` | Tail SQL Server logs |
| `make db-shell` | Open sqlcmd session |
| `make db-reset` | **DESTRUCTIVE** — wipe all data and restart |

## Data Persistence

Data is stored in `~/.queryadvisor/sqlserver` on the host, outside the repo.
A `make db-stop && make db-start` cycle preserves all databases.

## Running the App Against the Local Container

With the container running, start the app with SQL auth:

```bash
source .env && uvicorn app.main:app --reload
```

Or export the env vars in your shell session:

```bash
export SQL_AUTH_METHOD=sql
export MSSQL_SA_PASSWORD=YourStr0ng!Pass
uvicorn app.main:app --reload
```

## Troubleshooting

**Container fails to start / unhealthy:** SA password may not meet SQL Server
complexity requirements. Check `make db-logs` for the error. Use a password with
uppercase, lowercase, digit, and special character.

**Permission error on volume mount (Linux):** The SQL Server container runs as
UID 10001 (mssql). Set ownership on the host data dir:

```bash
podman unshare chown -R 10001:10001 ~/.queryadvisor/sqlserver
```

This is not needed on macOS.

**`${HOME}` not expanded in compose.yaml:** Ensure you run `podman-compose`
from a shell (not from a tool that doesn't expand env vars). `make db-start`
handles this correctly.
```

- [ ] **Step 4.2: Commit**

```bash
git add docs/guides/local-dev-setup.md
git commit -m "docs: add local dev setup guide for SQL Server Podman container"
```

---

## Self-Review

**Spec coverage check:**

| Requirement | Covered by |
|-------------|-----------|
| SQL Server 2022 in Podman container | Task 2 — `compose.yaml` |
| Data persisted to `~/.queryadvisor/sqlserver/` | Task 2 — volume mount |
| SA password via `.env` (gitignored) | Task 2 — `.env.example`; `.gitignore` already has `.env` |
| `app/config.py` SQL auth alongside Kerberos | Task 1 — `build_connection_string()` |
| Auth method via env var | Task 1 — `SQL_AUTH_METHOD` |
| `Makefile` with all lifecycle targets | Task 3 |
| `compose.yaml` (Podman Compose) | Task 2 |
| Dev setup instructions in `docs/` | Task 4 |
| `make db-start` / `db-stop` | Task 3 |
| Data survives restart cycle | Task 2 (bind mount) + Task 4 (docs) |
| `.env` gitignored; `.env.example` committed | Task 2 |
| Both auth methods work in `config.py` | Task 1 — tests cover both paths |
| `make db-shell` opens sqlcmd | Task 3 |
| SA password never in committed files | Task 2 (`.env.example` has empty value) |

**Placeholder scan:** None found — all steps contain actual code/commands.

**Type consistency:** `build_connection_string(database: str) -> str` is defined in Task 1 and imported in `tests/test_config.py` consistently throughout.
