"""
Idempotent seed script for the QueryAdvisorSample development database.

Usage:
    make db-seed
    # or directly:
    uv run python scripts/seed_db.py
"""
from __future__ import annotations

import random  # noqa: F401
import string  # noqa: F401
from datetime import datetime, timedelta  # noqa: F401

from app.config import get_connection

DB_NAME = "QueryAdvisorSample"  # passed to get_connection() in seed_schema() and create_database()


# ---------------------------------------------------------------------------
# Database creation — connects to master
# ---------------------------------------------------------------------------

def _ensure_database(cursor) -> None:
    """Create QueryAdvisorSample if it does not already exist."""
    cursor.execute(
        "IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'QueryAdvisorSample') "
        "CREATE DATABASE [QueryAdvisorSample]"
    )


def create_database() -> None:
    """Connect to master and create the sample database."""
    conn = get_connection("master")
    conn.autocommit = True
    try:
        _ensure_database(conn.cursor())
        print(f"  database '{DB_NAME}' ready")
    finally:
        conn.close()
