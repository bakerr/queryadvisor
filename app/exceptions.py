from __future__ import annotations


class DatabaseConnectionError(Exception):
    """Raised when a database connection attempt fails.

    Carries only the database name — no connection string fragments,
    credentials, driver info, or server addresses.
    """

    def __init__(self, database: str) -> None:
        self.database = database
        super().__init__(f"Database connection failed for '{database}'")
