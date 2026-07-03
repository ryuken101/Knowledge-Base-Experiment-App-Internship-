"""Shared SurrealDB helpers used by both KbCLI and DocumentCLI.

Client-agnostic (no MCP/CLI imports). These are the small pieces both
execution-layer classes need: response-shape tolerance, RecordID coercion,
datetime/RecordID stringification, and user seeding. Factored out so the
single-file KB and the document tree share one implementation.
"""
from __future__ import annotations

from datetime import datetime

from surrealdb import RecordID

from .models import KbError


def query_rows(client, surql: str, vars: dict | None = None) -> list[dict]:
    """Run a query and return a flat list of rows, tolerating both the newer SDK
    shape (rows returned directly) and the older {status, result} envelope."""
    res = client.query(surql, vars or {})
    if not isinstance(res, list):
        return [res] if res is not None else []
    if res and isinstance(res[0], dict) and "status" in res[0] and "result" in res[0]:
        rows: list[dict] = []
        for stmt in res:
            result = stmt.get("result")
            if isinstance(result, list):
                rows.extend(result)
            elif result is not None:
                rows.append(result)
        return rows
    return res


def coerce_rid(value: str | RecordID, table: str) -> RecordID:
    """Coerce a string (`'abc'` or `'table:abc'`) or RecordID into a RecordID on
    `table`. Raises KbError on a malformed id or a table mismatch. Pass the
    result into queries via `vars`, never string-interpolated into SurrealQL."""
    if isinstance(value, RecordID):
        actual = str(value).partition(":")[0]
        if actual != table:
            raise KbError(f"Expected a {table} id ({table}:...), got {value!r}")
        return value
    if not isinstance(value, str) or not value.strip():
        raise KbError(f"Malformed {table} id: {value!r}")
    value = value.strip()
    if ":" not in value:
        return RecordID(table, value)
    tbl, _, ident = value.partition(":")
    if not tbl or not ident:
        raise KbError(f"Malformed {table} id: {value!r}")
    if tbl != table:
        raise KbError(f"Expected a {table} id ({table}:...), got {value!r}")
    return RecordID(table, ident)


def to_str(value: object) -> str | None:
    """RecordID/datetime -> str for the client-facing dict contract."""
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


def ensure_user(client, rid: RecordID) -> None:
    """Seed a minimal user record if it doesn't exist, so a record<user> link is
    backed by a real row."""
    if not client.select(rid):
        name = str(rid).split(":", 1)[-1]
        client.create(rid, {"name": name})
