from __future__ import annotations

from sqlglot import exp

from app.models import ColumnDef


class TempTableTracker:
    """Tracks #temp table schemas across a multi-statement T-SQL script."""

    def __init__(self) -> None:
        self.schemas: dict[str, list[ColumnDef]] = {}

    def process_statement(self, stmt: exp.Expression) -> bool:
        """Process one statement. Returns True if a temp table was registered."""
        if self._is_create_temp(stmt):
            name, cols = self._extract_create(stmt)
            self.schemas[name] = cols
            return True
        if self._is_select_into_temp(stmt):
            name, cols = self._extract_select_into(stmt)
            self.schemas[name] = cols
            return True
        return False

    def _is_create_temp(self, stmt: exp.Expression) -> bool:
        if not isinstance(stmt, exp.Create):
            return False
        table = stmt.find(exp.Table)
        return table is not None and table.name.startswith("#")

    def _is_select_into_temp(self, stmt: exp.Expression) -> bool:
        if not isinstance(stmt, exp.Select):
            return False
        into = stmt.args.get("into")
        if not into:
            return False
        # sqlglot parses #tmp as table name "tmp" with Into.temporary=True
        if isinstance(into, exp.Into) and into.args.get("temporary"):
            return True
        table = into.find(exp.Table) if isinstance(into, exp.Expression) else None
        if table is None and isinstance(into, exp.Into):
            table = into.this
        name = getattr(table, "name", None) or str(into)
        return isinstance(name, str) and name.startswith("#")

    def _extract_create(self, stmt: exp.Create) -> tuple[str, list[ColumnDef]]:
        table = stmt.find(exp.Table)
        name = table.name
        # Normalize key to always include # prefix
        if not name.startswith("#"):
            name = "#" + name
        cols = []
        schema_def = stmt.find(exp.Schema)
        if schema_def:
            for col_def in schema_def.find_all(exp.ColumnDef):
                dtype = col_def.args.get("kind")
                cols.append(ColumnDef(
                    column_name=col_def.name,
                    data_type=str(dtype) if dtype else "unknown",
                ))
        return name, cols

    def _extract_select_into(self, stmt: exp.Select) -> tuple[str, list[ColumnDef]]:
        into = stmt.args.get("into")
        table = None
        if isinstance(into, exp.Into):
            table = into.this
        name = table.name if table else str(into)
        # Normalize key to always include # prefix
        if not name.startswith("#"):
            name = "#" + name
        cols = [
            ColumnDef(column_name=str(expr.alias or expr), data_type="unknown")
            for expr in stmt.expressions
            if not isinstance(expr, exp.Star)
        ]
        return name, cols
