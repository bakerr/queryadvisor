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


# ---------------------------------------------------------------------------
# dbo schema DDL — clean e-commerce schema
# ---------------------------------------------------------------------------

_DDL_CATEGORIES = """
IF OBJECT_ID('dbo.Categories', 'U') IS NULL
CREATE TABLE dbo.Categories (
    CategoryID  int           NOT NULL IDENTITY(1,1),
    Name        nvarchar(100) NOT NULL,
    CONSTRAINT PK_Categories PRIMARY KEY CLUSTERED (CategoryID)
)"""

_DDL_CUSTOMERS = """
IF OBJECT_ID('dbo.Customers', 'U') IS NULL
CREATE TABLE dbo.Customers (
    CustomerID  int           NOT NULL IDENTITY(1,1),
    Email       varchar(255)  NOT NULL,
    Name        nvarchar(200) NOT NULL,
    CreatedAt   datetime2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Customers PRIMARY KEY CLUSTERED (CustomerID)
)"""

_DDL_CUSTOMERS_IDX_EMAIL = """
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Customers_Email' AND object_id = OBJECT_ID('dbo.Customers')
)
CREATE UNIQUE INDEX IX_Customers_Email ON dbo.Customers (Email)"""

_DDL_PRODUCTS = """
IF OBJECT_ID('dbo.Products', 'U') IS NULL
CREATE TABLE dbo.Products (
    ProductID   int            NOT NULL IDENTITY(1,1),
    CategoryID  int            NOT NULL,
    Name        nvarchar(200)  NOT NULL,
    Price       decimal(10,2)  NOT NULL,
    Stock       int            NOT NULL DEFAULT 0,
    CONSTRAINT PK_Products PRIMARY KEY CLUSTERED (ProductID),
    CONSTRAINT FK_Products_Categories FOREIGN KEY (CategoryID)
        REFERENCES dbo.Categories (CategoryID)
)"""

_DDL_PRODUCTS_IDX_CATEGORY = """
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Products_CategoryID' AND object_id = OBJECT_ID('dbo.Products')
)
CREATE INDEX IX_Products_CategoryID ON dbo.Products (CategoryID)"""

_DDL_ORDERS = """
IF OBJECT_ID('dbo.Orders', 'U') IS NULL
CREATE TABLE dbo.Orders (
    OrderID     int          NOT NULL IDENTITY(1,1),
    CustomerID  int          NOT NULL,
    OrderDate   datetime2    NOT NULL DEFAULT SYSUTCDATETIME(),
    Status      varchar(20)  NOT NULL DEFAULT 'pending',
    CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderID),
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID)
        REFERENCES dbo.Customers (CustomerID)
)"""

_DDL_ORDERS_IDX_CUSTOMER = """
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Orders_CustomerID' AND object_id = OBJECT_ID('dbo.Orders')
)
CREATE INDEX IX_Orders_CustomerID ON dbo.Orders (CustomerID)"""

_DDL_ORDERS_IDX_DATE = """
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Orders_OrderDate' AND object_id = OBJECT_ID('dbo.Orders')
)
CREATE INDEX IX_Orders_OrderDate ON dbo.Orders (OrderDate)"""

_DDL_ORDER_ITEMS = """
IF OBJECT_ID('dbo.OrderItems', 'U') IS NULL
CREATE TABLE dbo.OrderItems (
    OrderItemID int            NOT NULL IDENTITY(1,1),
    OrderID     int            NOT NULL,
    ProductID   int            NOT NULL,
    Quantity    int            NOT NULL DEFAULT 1,
    UnitPrice   decimal(10,2)  NOT NULL,
    CONSTRAINT PK_OrderItems PRIMARY KEY CLUSTERED (OrderItemID),
    CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (OrderID)
        REFERENCES dbo.Orders (OrderID),
    CONSTRAINT FK_OrderItems_Products FOREIGN KEY (ProductID)
        REFERENCES dbo.Products (ProductID)
)"""

_DDL_ORDER_ITEMS_IDX_ORDER = """
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_OrderItems_OrderID' AND object_id = OBJECT_ID('dbo.OrderItems')
)
CREATE INDEX IX_OrderItems_OrderID ON dbo.OrderItems (OrderID)"""

_DDL_ORDER_ITEMS_IDX_PRODUCT = """
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_OrderItems_ProductID' AND object_id = OBJECT_ID('dbo.OrderItems')
)
CREATE INDEX IX_OrderItems_ProductID ON dbo.OrderItems (ProductID)"""

_DBO_DDL = [
    _DDL_CATEGORIES,
    _DDL_CUSTOMERS,
    _DDL_CUSTOMERS_IDX_EMAIL,
    _DDL_PRODUCTS,
    _DDL_PRODUCTS_IDX_CATEGORY,
    _DDL_ORDERS,
    _DDL_ORDERS_IDX_CUSTOMER,
    _DDL_ORDERS_IDX_DATE,
    _DDL_ORDER_ITEMS,
    _DDL_ORDER_ITEMS_IDX_ORDER,
    _DDL_ORDER_ITEMS_IDX_PRODUCT,
]


def _create_dbo_tables(cursor) -> None:
    """Execute all dbo schema DDL statements."""
    for stmt in _DBO_DDL:
        cursor.execute(stmt)
