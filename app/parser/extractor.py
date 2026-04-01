from __future__ import annotations

import sqlglot
from sqlglot import exp

from app.models import JoinDef, Predicate, QueryProfile, TableRef

_COMPARISON_TYPES = (exp.EQ, exp.GT, exp.LT, exp.GTE, exp.LTE, exp.NEQ, exp.Like)


def extract_query_profiles(sql: str) -> list[QueryProfile]:
    """Parse a T-SQL script and return one QueryProfile per SELECT statement."""
    from app.parser.temp_tables import TempTableTracker
    tracker = TempTableTracker()
    statements = sqlglot.parse(sql, dialect="tsql")
    profiles = []
    for stmt in statements:
        if stmt is None:
            continue
        is_temp_stmt = tracker.process_statement(stmt)
        # Only extract a profile from SELECT statements that are NOT SELECT INTO #temp
        if isinstance(stmt, exp.Select) and not is_temp_stmt:
            profile = _extract_single_select(stmt)
            profile.temp_table_schemas = dict(tracker.schemas)
            profiles.append(profile)
    return profiles


def _extract_single_select(tree: exp.Expression) -> QueryProfile:
    return QueryProfile(
        tables=_extract_tables(tree),
        joins=_extract_joins(tree),
        where_predicates=_extract_where_predicates(tree),
        selected_columns=_extract_selected_columns(tree),
        has_distinct=bool(tree.args.get("distinct")),
        has_order_by=bool(tree.args.get("order")),
        has_top_or_offset=bool(tree.args.get("top")) or bool(tree.args.get("limit")),
    )


def _extract_tables(tree: exp.Expression) -> list[TableRef]:
    tables, seen = [], set()
    for table in tree.find_all(exp.Table):
        name = table.name
        if not name or name in seen:
            continue
        seen.add(name)
        is_temp = name.startswith("#") or bool(
            table.this.args.get("temporary") if isinstance(table.this, exp.Expression) else False
        )
        tables.append(TableRef(
            name=name,
            schema_name=table.db or "dbo",
            alias=table.alias or None,
            is_temp=is_temp,
        ))
    return tables


def _extract_selected_columns(tree: exp.Expression) -> list[str]:
    select = tree if isinstance(tree, exp.Select) else tree.find(exp.Select)
    if not select:
        return []
    for expr in select.expressions:
        if isinstance(expr, exp.Star):
            return ["*"]
    return [
        expr.alias or (expr.name if isinstance(expr, exp.Column) else str(expr))
        for expr in select.expressions
    ]


def _extract_where_predicates(tree: exp.Expression) -> list[Predicate]:
    where = tree.find(exp.Where)
    if not where:
        return []
    return _predicates_from_expr(where)


def _predicates_from_expr(expr: exp.Expression) -> list[Predicate]:
    predicates = []
    for cond in expr.find_all(*_COMPARISON_TYPES):
        left = cond.left if hasattr(cond, "left") else None
        right = cond.right if hasattr(cond, "right") else None
        if left is None:
            continue
        col_name = _column_name(left)
        if col_name:
            value_str = str(right) if right else ""
            # Strip surrounding single-quotes from string literals
            if value_str.startswith("'") and value_str.endswith("'") and len(value_str) >= 2:
                value_str = value_str[1:-1]
            predicates.append(Predicate(
                column=col_name,
                table_alias=_table_alias(left),
                operator=type(cond).__name__.upper(),
                value_expr=value_str,
                has_function_wrap=isinstance(left, exp.Func),
            ))
    return predicates


def _column_name(expr: exp.Expression) -> str | None:
    if isinstance(expr, exp.Column):
        return expr.name
    col = expr.find(exp.Column)
    return col.name if col else None


def _table_alias(expr: exp.Expression) -> str | None:
    col = expr.find(exp.Column)
    return col.table if col else None


def _extract_joins(tree: exp.Expression) -> list[JoinDef]:
    joins = []
    from_clause = tree.find(exp.From)
    from_table = from_clause.find(exp.Table) if from_clause else None
    from_name = from_table.name if from_table else ""
    for join in tree.find_all(exp.Join):
        join_table = join.find(exp.Table)
        if not join_table:
            continue
        on_clause = join.args.get("on")
        predicates = _predicates_from_expr(on_clause) if on_clause else []
        join_type = " ".join(filter(None, [join.side, join.kind])) or "INNER"
        joins.append(JoinDef(
            join_type=join_type,
            left_table=from_name,
            right_table=join_table.name,
            predicates=predicates,
        ))
    return joins
