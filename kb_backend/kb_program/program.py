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

from surrealdb import RecordID

from ._common import coerce_rid, ensure_user, query_rows, to_str
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

    def delete_line(self, line_number: int, user_id: str | None = None) -> dict:
        """Remove a single line (1-based) from the KB markdown, keeping the rest.
        Bumps updated_at. Raises KbError if the line number is out of range."""
        if line_number is None:
            raise KbError("line_number is required")
        content = self.get_knowledge_base(user_id)["content"] or ""
        if content == "":
            raise KbError("knowledge base is empty; no lines to delete")
        lines = content.split("\n")
        if line_number < 1 or line_number > len(lines):
            raise KbError(f"line {line_number} out of range (1..{len(lines)})")
        del lines[line_number - 1]
        return self.set_knowledge_base("\n".join(lines), user_id)

    def delete_knowledge_base(self, user_id: str | None = None) -> dict:
        """Delete the whole KB row (the entire markdown file), not just its
        content. A later get_knowledge_base will recreate an empty one
        (create-on-read). Returns the deleted user id; idempotent if absent."""
        rid = self._resolve_user(user_id)
        row = self._fetch_row(rid)
        existed = row is not None
        if existed:
            self._client.delete(row["id"])
        return {"user_id": str(rid), "deleted": existed}

    # ---- internals -------------------------------------------------------

    def _resolve_user(self, user_id: str | None) -> RecordID:
        raw = user_id or self._default_user
        if not raw:
            raise KbError("No user specified and KB_USER is not set in the environment")
        rid = coerce_rid(raw, "user")
        ensure_user(self._client, rid)
        return rid

    def _fetch_row(self, rid: RecordID) -> dict | None:
        rows = query_rows(
            self._client, "SELECT * FROM knowledge_base WHERE user = $u LIMIT 1", {"u": rid}
        )
        return rows[0] if rows else None

    def _normalize(self, raw: dict | None) -> dict:
        """Reproduce the client-facing dict contract: RecordID/datetime -> str,
        `user` link -> `user_id`, full key set filled."""
        if not raw:
            return {"user_id": None, "content": "", "created_at": None, "updated_at": None}
        return {
            "user_id": to_str(raw.get("user")),
            "content": raw.get("content") or "",
            "created_at": to_str(raw.get("created_at")),
            "updated_at": to_str(raw.get("updated_at")),
        }
