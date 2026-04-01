.PHONY: db-start db-stop db-status db-logs db-shell db-reset help

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
	@printf "WARNING: This will permanently delete all SQL Server data.\nPress Ctrl-C to abort, or Enter to continue: "; read _confirm
	$(DB_COMPOSE) down
	rm -rf $(HOME)/.queryadvisor/sqlserver
	mkdir -p $(HOME)/.queryadvisor/sqlserver
	$(DB_COMPOSE) up -d

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-12s %s\n", $$1, $$2}'
