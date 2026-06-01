"""KbCLI — execution layer for the per-user markdown knowledge base.

Direct SurrealDB SDK calls, no ORM/repository layer, mirroring the task app's
TaskCLI. The KB is one freeform markdown file per user, stored in the
`knowledge_base` table and linked to the (currently dead) `user` table.

Until user management/auth lands, the backend operates on a single configurable
user: pass `user_id` explicitly, or set the `KB_USER` env var (defaults to
`user:agent`). The referenced user record is seeded on first write so the
`record<user>` link is backed by a real row; multi-user is then purely additive.
"""
from __future__ import annotations

import os
from datetime import datetime

from surrealdb import RecordID

from .db import client
from .models import KbError


class KbCLI:
    """One method per verb: get / set / append / clear the knowledge base."""

    _KB_KEYS = ("user_id", "content", "created_at", "updated_at")

    def __init__(
        self,
        url: str | None = None,
        username: str | None = None,
        password: str | None = None,
        namespace: str | None = None,
        database: str | None = None,
        default_user: str | None = None,
    ) -> None:
        self._client = client(url, username, password, namespace, database)
        self._default_user = default_user or os.getenv("KB_USER", "user:agent")

    # ---- public API ------------------------------------------------------

    def get_knowledge_base(self, user_id: str | None = None) -> dict:
        """Return the user's KB. Creates an empty one on first read so the
        agent always has a row to append to."""
        rid = self._resolve_user(user_id)
        row = self._fetch_row(rid)
        if row is None:
            self._client.create("knowledge_base", {"user": rid, "content": ""})
            row = self._fetch_row(rid)
        return self._normalize(row)

    def set_knowledge_base(self, content: str, user_id: str | None = None) -> dict:
        """Replace the whole KB markdown file (manual save). Bumps updated_at."""
        if content is None:
            raise KbError("content is required")
        rid = self._resolve_user(user_id)
        row = self._fetch_row(rid)
        if row is None:
            self._client.create("knowledge_base", {"user": rid, "content": content})
        else:
            self._client.query(
                "UPDATE $id SET content = $c, updated_at = time::now()",
                {"id": row["id"], "c": content},
            )
        return self._normalize(self._fetch_row(rid))

    def append_knowledge_base(self, text: str, user_id: str | None = None) -> dict:
        """Append a note/observation to the KB on its own line."""
        if not text:
            raise KbError("text is required")
        existing = self.get_knowledge_base(user_id)["content"] or ""
        new_content = text if not existing else existing.rstrip("\n") + "\n" + text
        return self.set_knowledge_base(new_content, user_id)

    def clear_knowledge_base(self, user_id: str | None = None) -> dict:
        """Empty the KB content while keeping the row (and created_at)."""
        return self.set_knowledge_base("", user_id)

    # ---- internals -------------------------------------------------------

    def _resolve_user(self, user_id: str | None) -> RecordID:
        raw = user_id or self._default_user
        if not raw:
            raise KbError("No user specified and KB_USER is not set in the environment")
        rid = self._user_rid(raw)
        self._ensure_user(rid)
        return rid

    def _ensure_user(self, rid: RecordID) -> None:
        """Seed a minimal user record if it doesn't exist, so the KB's
        record<user> link is backed by a real row."""
        if not self._client.select(rid):
            name = str(rid).split(":", 1)[-1]
            self._client.create(rid, {"name": name})

    def _fetch_row(self, rid: RecordID) -> dict | None:
        rows = self._query_rows(
            "SELECT * FROM knowledge_base WHERE user = $u LIMIT 1", {"u": rid}
        )
        return rows[0] if rows else None

    def _query_rows(self, surql: str, vars: dict | None = None) -> list[dict]:
        """Run a query and return a flat list of rows, tolerating both the
        newer SDK shape (rows returned directly) and the older
        {status, result} envelope shape."""
        res = self._client.query(surql, vars or {})
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

    @staticmethod
    def _user_rid(value: str | RecordID) -> RecordID:
        if isinstance(value, RecordID):
            return value
        if not isinstance(value, str) or not value.strip():
            raise KbError(f"Malformed user id: {value!r}")
        value = value.strip()
        if ":" not in value:
            return RecordID("user", value)
        table, _, ident = value.partition(":")
        if not table or not ident:
            raise KbError(f"Malformed user id: {value!r}")
        if table != "user":
            raise KbError(f"Expected a user id (user:...), got {value!r}")
        return RecordID("user", ident)

    def _normalize(self, raw: dict | None) -> dict:
        """Reproduce the client-facing dict contract: RecordID/datetime -> str,
        `user` link -> `user_id`, full key set filled."""
        if not raw:
            return {"user_id": None, "content": "", "created_at": None, "updated_at": None}
        return {
            "user_id": self._to_str(raw.get("user")),
            "content": raw.get("content") or "",
            "created_at": self._to_str(raw.get("created_at")),
            "updated_at": self._to_str(raw.get("updated_at")),
        }

    @staticmethod
    def _to_str(value: object) -> str | None:
        if value is None:
            return None
        if isinstance(value, datetime):
            return value.isoformat()
        return str(value)
