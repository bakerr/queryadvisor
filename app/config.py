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
