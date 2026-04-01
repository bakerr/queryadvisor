import os


def get_connection(database: str):
    import pyodbc  # noqa: PLC0415 — lazy import; pyodbc is a production dep only

    server = os.getenv("SQL_SERVER_HOST", "localhost")
    driver = os.getenv("ODBC_DRIVER", "ODBC Driver 18 for SQL Server")
    conn_str = (
        f"DRIVER={{{driver}}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        "Trusted_Connection=yes;"
    )
    return pyodbc.connect(conn_str, timeout=10)
