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

from app.config import get_connection  # noqa: F401

DB_NAME = "QueryAdvisorSample"  # passed to get_connection() in seed_schema() and create_database()
