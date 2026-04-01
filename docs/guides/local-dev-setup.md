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
| `make db-reset` | **DESTRUCTIVE** — prompts for confirmation, then wipes all data and restarts |

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
export ODBC_DRIVER="ODBC Driver 18 for SQL Server"
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
