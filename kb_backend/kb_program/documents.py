"""DocumentCLI — execution layer for the nested document tree.

A unified, self-referencing tree (Notion/Outline-style): every node is a
`document` row; a "folder" is just a document that holds children (the
`is_folder` flag is a UI/type hint, not a structural constraint). `parent` is the
self-reference (None = top-level); `owner` scopes a node to a user (Personal) or
leaves it shared (None = the Team area).

Single-user for now (no auth): `owner` is additive-ready structure, not a
security boundary, so visibility is filtered in Python rather than via table
PERMISSIONS. Like KbCLI, the backend operates on one configurable user (pass
`user_id`, or set `KB_USER`, default `user:agent`). The user record is seeded on
first use, and a "Personal" (owned) + shared "Team" root folder are created on
read so there is always somewhere to put things (create-on-read, mirroring
KbCLI.get_knowledge_base).

Trees are small and per-user, so every operation fetches the flat, owner-scoped
row set once and assembles/walks it in Python — no recursive SurrealQL.
RecordIDs are always passed via query `vars`, never string-interpolated.
"""
from __future__ import annotations

import os

from surrealdb import RecordID

from ._common import coerce_rid, ensure_user, query_rows, to_str
from .db import client
from .models import KbError


class DocumentCLI:
    """CRUD + move/reorder over the document tree, scoped to one user's view
    (their Personal subtree plus the shared Team subtree)."""

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

    def list_documents(self, user_id: str | None = None) -> list[dict]:
        """Return the user's visible tree as a flat list (metadata only, no
        content), ordered by position. The client assembles the tree from
        `parent_id`. Seeds Personal/Team roots on first call."""
        user_rid = self._resolve_user(user_id)
        self._ensure_sections(user_rid)
        rows = self._visible_rows(user_rid)
        return [self._normalize(r, include_content=False) for r in rows]

    def read_document(self, doc_id: str, user_id: str | None = None) -> dict:
        """Return a single document including its markdown content."""
        user_rid = self._resolve_user(user_id)
        doc_rid = coerce_rid(doc_id, "document")
        row = self._select_one(doc_rid)
        if not row or not self._is_visible(row, user_rid):
            raise KbError(f"Document not found: {doc_id}")
        return self._normalize(row, include_content=True)

    def search_documents(
        self, query: str, user_id: str | None = None, limit: int = 20
    ) -> list[dict]:
        """Case-insensitive substring search over the user's visible documents by
        title and content. Each hit is a metadata dict (as `list_documents`) plus
        a `snippet` — an excerpt around the first content match, or None when the
        term only matched the title. Title matches rank above content-only ones.

        Tier-1 (in-Python) search: it reuses `_visible_rows`, so it's owner-scoped
        and needs no index. Swap the body for SurrealDB full-text search later
        without changing this signature or the callers."""
        q = (query or "").strip()
        if not q:
            return []
        needle = q.lower()
        user_rid = self._resolve_user(user_id)
        self._ensure_sections(user_rid)
        rows = self._visible_rows(user_rid)

        hits: list[dict] = []
        for r in rows:
            title = r.get("title") or ""
            content = r.get("content") or ""
            in_title = needle in title.lower()
            in_content = needle in content.lower()
            if not (in_title or in_content):
                continue
            out = self._normalize(r, include_content=False)
            out["snippet"] = self._snippet(content, q) if in_content else None
            # Title hits sort before content-only hits; then alphabetical.
            out["_rank"] = 0 if in_title else 1
            hits.append(out)

        hits.sort(key=lambda h: (h["_rank"], (h["title"] or "").lower()))
        for h in hits:
            h.pop("_rank", None)
        return hits[:limit]

    @staticmethod
    def _snippet(content: str, query: str, *, window: int = 60) -> str | None:
        """A single-line excerpt of `content` around the first case-insensitive
        match of `query`, padded by ~`window` chars each side and elided with `…`
        when truncated. Returns None if the query isn't in the content."""
        idx = content.lower().find(query.lower())
        if idx < 0:
            return None
        start = max(0, idx - window)
        end = min(len(content), idx + len(query) + window)
        excerpt = " ".join(content[start:end].split())
        if start > 0:
            excerpt = "… " + excerpt
        if end < len(content):
            excerpt = excerpt + " …"
        return excerpt

    def create_document(
        self,
        title: str | None = None,
        parent_id: str | None = None,
        is_folder: bool = False,
        user_id: str | None = None,
    ) -> dict:
        """Create a node under `parent_id` (or top-level if None). Owner is
        inherited from the parent's branch (so creating under Team yields a
        shared node), or the user for a new top-level Personal node. Position is
        appended after existing siblings."""
        user_rid = self._resolve_user(user_id)
        self._ensure_sections(user_rid)
        rows = self._visible_rows(user_rid)

        if parent_id:
            parent_rid = coerce_rid(parent_id, "document")
            parent = self._select_one(parent_rid)
            if not parent or not self._is_visible(parent, user_rid):
                raise KbError(f"Parent not found: {parent_id}")
            owner = parent.get("owner")  # RecordID (Personal) or None (Team)
            parent_field: RecordID | None = parent_rid
            parent_key = to_str(parent_rid)
        else:
            owner = user_rid
            parent_field = None
            parent_key = None

        data: dict = {
            "title": (title or "Untitled").strip() or "Untitled",
            "is_folder": bool(is_folder),
            "position": self._next_position(parent_key, rows),
        }
        if parent_field is not None:
            data["parent"] = parent_field
        if owner is not None:
            data["owner"] = owner if isinstance(owner, RecordID) else coerce_rid(owner, "user")

        created = self._client.create("document", data)
        row = created[0] if isinstance(created, list) else created
        return self._normalize(row, include_content=True)

    def update_document(
        self,
        doc_id: str,
        *,
        content: str | None = None,
        title: str | None = None,
        user_id: str | None = None,
    ) -> dict:
        """Set content and/or title on a document, bumping updated_at."""
        user_rid = self._resolve_user(user_id)
        doc_rid = coerce_rid(doc_id, "document")
        row = self._select_one(doc_rid)
        if not row or not self._is_visible(row, user_rid):
            raise KbError(f"Document not found: {doc_id}")

        sets = ["updated_at = time::now()"]
        vars: dict = {"id": doc_rid}
        if content is not None:
            sets.append("content = $c")
            vars["c"] = content
        if title is not None:
            t = title.strip()
            if not t:
                raise KbError("title cannot be empty")
            sets.append("title = $t")
            vars["t"] = t
        if len(sets) == 1:
            raise KbError("nothing to update (provide content and/or title)")

        self._client.query(f"UPDATE $id SET {', '.join(sets)}", vars)
        return self._normalize(self._select_one(doc_rid), include_content=True)

    def move_document(
        self,
        doc_id: str,
        new_parent_id: str | None = None,
        index: int = 0,
        user_id: str | None = None,
    ) -> dict:
        """Reparent a node to `new_parent_id` (or top-level if None) and place it
        at `index` among the destination's children. Rejects moving a node into
        itself or its own descendant. The moved subtree's owner is set to the
        destination branch's owner so the Personal/Team split stays consistent."""
        user_rid = self._resolve_user(user_id)
        doc_rid = coerce_rid(doc_id, "document")
        rows = self._visible_rows(user_rid)
        doc_key = to_str(doc_rid)
        if self._find(rows, doc_key) is None:
            raise KbError(f"Document not found: {doc_id}")

        if new_parent_id:
            parent_rid = coerce_rid(new_parent_id, "document")
            parent_key = to_str(parent_rid)
            parent = self._find(rows, parent_key)
            if parent is None:
                raise KbError(f"Parent not found: {new_parent_id}")
            if parent_key == doc_key or parent_key in self._descendants(doc_key, rows):
                raise KbError("cannot move a document into itself or its own descendant")
            new_owner = parent.get("owner")  # RecordID or None
            self._client.query(
                "UPDATE $id SET parent = $p, updated_at = time::now()",
                {"id": doc_rid, "p": parent_rid},
            )
        else:
            parent_key = None
            new_owner = user_rid
            self._client.query(
                "UPDATE $id SET parent = NONE, updated_at = time::now()", {"id": doc_rid}
            )

        self._set_owner_cascade(doc_key, new_owner, rows)
        self._reorder(parent_key, doc_key, index, user_rid)
        return self._normalize(self._select_one(doc_rid), include_content=True)

    def delete_document(self, doc_id: str, user_id: str | None = None) -> dict:
        """Delete a node and its entire subtree. Returns the deleted ids."""
        user_rid = self._resolve_user(user_id)
        doc_rid = coerce_rid(doc_id, "document")
        rows = self._visible_rows(user_rid)
        doc_key = to_str(doc_rid)
        if self._find(rows, doc_key) is None:
            raise KbError(f"Document not found: {doc_id}")
        ids = {doc_key} | self._descendants(doc_key, rows)
        for k in ids:
            self._client.delete(coerce_rid(k, "document"))
        return {"deleted": sorted(ids), "count": len(ids)}

    # ---- path addressing (for the MCP agent surface) --------------------

    def resolve_path(self, path: str, user_id: str | None = None) -> str:
        """Resolve a slash-separated title path (e.g. `Personal/Ideas/Roadmap`)
        to a document id, matching titles case-insensitively. Raises KbError if
        any segment is missing."""
        user_rid = self._resolve_user(user_id)
        self._ensure_sections(user_rid)
        rows = self._visible_rows(user_rid)
        parts = [p for p in (path or "").strip("/").split("/") if p.strip()]
        if not parts:
            raise KbError("empty path")
        parent_key = None
        current: dict | None = None
        for part in parts:
            match = None
            for r in self._children(parent_key, rows):
                if (r.get("title") or "").strip().lower() == part.strip().lower():
                    match = r
                    break
            if match is None:
                raise KbError(f"Path not found: {path!r} (no '{part}')")
            current = match
            parent_key = to_str(match.get("id"))
        return to_str(current.get("id"))  # type: ignore[union-attr]

    def render_tree(self, user_id: str | None = None) -> str:
        """Render the visible tree as indented text for the agent."""
        user_rid = self._resolve_user(user_id)
        self._ensure_sections(user_rid)
        rows = self._visible_rows(user_rid)
        lines: list[str] = []

        def walk(parent_key: str | None, depth: int) -> None:
            for r in self._children(parent_key, rows):
                icon = "[folder]" if r.get("is_folder") else "[doc]   "
                lines.append(f"{'  ' * depth}{icon} {r.get('title')}")
                walk(to_str(r.get("id")), depth + 1)

        walk(None, 0)
        return "\n".join(lines) if lines else "(empty)"

    # ---- internals -------------------------------------------------------

    def _resolve_user(self, user_id: str | None) -> RecordID:
        raw = user_id or self._default_user
        if not raw:
            raise KbError("No user specified and KB_USER is not set in the environment")
        rid = coerce_rid(raw, "user")
        ensure_user(self._client, rid)
        return rid

    def _ensure_sections(self, user_rid: RecordID) -> None:
        """Create-on-read the Personal (owned) and Team (shared) root folders if
        the user has no top-level node in that scope yet."""
        rows = query_rows(self._client, "SELECT id, owner, parent FROM document")
        has_personal = any(
            to_str(r.get("parent")) is None and to_str(r.get("owner")) == str(user_rid)
            for r in rows
        )
        has_team = any(
            to_str(r.get("parent")) is None and to_str(r.get("owner")) is None for r in rows
        )
        if not has_personal:
            self._client.create(
                "document",
                {"title": "Personal", "owner": user_rid, "is_folder": True, "position": 0},
            )
        if not has_team:
            self._client.create(
                "document", {"title": "Team", "is_folder": True, "position": 1}
            )

    def _visible_rows(self, user_rid: RecordID) -> list[dict]:
        """All documents the user can see: their own (owner == user) plus shared
        (owner is None). Filtered in Python — owner is not yet a security
        boundary; move this to a WHERE clause / PERMISSIONS when auth lands."""
        rows = query_rows(self._client, "SELECT * FROM document ORDER BY position")
        return [r for r in rows if self._is_visible(r, user_rid)]

    def _is_visible(self, raw: dict, user_rid: RecordID) -> bool:
        owner = to_str(raw.get("owner"))
        return owner is None or owner == str(user_rid)

    def _children(self, parent_key: str | None, rows: list[dict]) -> list[dict]:
        kids = [r for r in rows if to_str(r.get("parent")) == parent_key]
        kids.sort(key=lambda r: ((r.get("position") or 0), str(r.get("id"))))
        return kids

    def _descendants(self, root_key: str, rows: list[dict]) -> set[str]:
        """Ids strictly below root_key (excludes root_key itself)."""
        result: set[str] = set()
        stack = [root_key]
        while stack:
            pid = stack.pop()
            for r in rows:
                rid = to_str(r.get("id"))
                if to_str(r.get("parent")) == pid and rid not in result and rid != root_key:
                    result.add(rid)
                    stack.append(rid)
        return result

    def _next_position(self, parent_key: str | None, rows: list[dict]) -> int:
        kids = self._children(parent_key, rows)
        return (max((k.get("position") or 0) for k in kids) + 1) if kids else 0

    def _reorder(
        self, parent_key: str | None, doc_key: str, index: int, user_rid: RecordID
    ) -> None:
        """Renumber the destination's children to 0..n with doc_key at `index`."""
        rows = self._visible_rows(user_rid)  # refetch: parent already updated
        siblings = [to_str(r.get("id")) for r in self._children(parent_key, rows)]
        if doc_key in siblings:
            siblings.remove(doc_key)
        index = max(0, min(index, len(siblings)))
        siblings.insert(index, doc_key)
        for pos, sid in enumerate(siblings):
            self._client.query(
                "UPDATE $id SET position = $p", {"id": coerce_rid(sid, "document"), "p": pos}
            )

    def _set_owner_cascade(self, root_key: str, new_owner, rows: list[dict]) -> None:
        ids = {root_key} | self._descendants(root_key, rows)
        for k in ids:
            rid = coerce_rid(k, "document")
            if new_owner is None:
                self._client.query("UPDATE $id SET owner = NONE", {"id": rid})
            else:
                ow = new_owner if isinstance(new_owner, RecordID) else coerce_rid(new_owner, "user")
                self._client.query("UPDATE $id SET owner = $o", {"id": rid, "o": ow})

    def _select_one(self, rid: RecordID) -> dict | None:
        res = self._client.select(rid)
        if isinstance(res, list):
            return res[0] if res else None
        return res

    @staticmethod
    def _find(rows: list[dict], id_str: str) -> dict | None:
        for r in rows:
            if to_str(r.get("id")) == id_str:
                return r
        return None

    def _normalize(self, raw: dict | None, *, include_content: bool) -> dict:
        """Client-facing dict: RecordID/datetime -> str, `parent`/`owner` links
        renamed to `parent_id`/`owner_id`. Content included only on read."""
        if not raw:
            raise KbError("document row is empty")
        out = {
            "id": to_str(raw.get("id")),
            "title": raw.get("title") or "Untitled",
            "parent_id": to_str(raw.get("parent")),
            "owner_id": to_str(raw.get("owner")),
            "is_folder": bool(raw.get("is_folder")),
            "position": raw.get("position") or 0,
            "created_at": to_str(raw.get("created_at")),
            "updated_at": to_str(raw.get("updated_at")),
        }
        if include_content:
            out["content"] = raw.get("content") or ""
        return out
