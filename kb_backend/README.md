# kb_backend

A per-user **knowledge base** for the task-managing agent, backed by **SurrealDB**.

It lives in the **same SurrealDB instance** (`main` ns/db) as the task app and links to
the task app's `user` table. There are two surfaces, sharing one execution layer:

- **Document tree** (`DocumentCLI`, `document` table) — a nested **Notion/Outline-style**
  folder/document tree. Every node is a document; a *folder* is just a document that holds
  children. Each user sees their own **Personal** subtree (owned) plus a shared **Team**
  subtree (`owner = NONE`), both seeded on first use. This is the primary surface the
  Flutter app and the agent now use.
- **Single-file KB** (`KbCLI`, `knowledge_base` table) — the original, deliberately
  rudimentary design: **one freeform markdown ("Obsidian") file per user**. Kept intact for
  backward compatibility.

Single-user for now (no auth): the `owner` field is *additive-ready* structure, not a
security boundary — visibility is filtered in code, to become table `PERMISSIONS` when auth
lands.

```
kb_backend/
├── schema.surql      # complete fresh-install schema (task tables + knowledge_base + document)
├── reset.surql       # wipe all records, keep the schema
├── kb_program/       # execution layer (library only): KbCLI + DocumentCLI + SurrealDB access
│   └── _common.py    # shared helpers (query shapes, RecordID coercion, user seeding)
├── kb_mcp/           # FastMCP server: KB tools + document-tree tools
└── kb_api/           # FastAPI REST server: KB routes + document-tree routes
```

## 1. Import the schema

`schema.surql` is a **complete fresh-install schema** — import it into a brand-new, empty
SurrealDB (`main` namespace + database) and you get a fully working environment for
testing the agent end-to-end (tasks + KB). Paste it into the Surrealist query editor
(→ Run query) or use `surreal import`. Every statement is idempotent (`IF NOT EXISTS`), so
it's also safe to run against an instance that already has the task tables.

`reset.surql` wipes all records while keeping the schema — handy between test runs.

## 2. Configure credentials

Copy `.env.example` to `.env` and fill in `SURREALDB_URL`, `SURREALDB_USER` (root), and
`SURREALDB_PASS`; `SURREALDB_NS`/`SURREALDB_DB` default to `main`. Point at the **same**
instance as the task app. `KB_USER` (default `user:agent`) selects which user owns the KB
until user management exists; the user record is seeded automatically on first write.

`db.py` discovers `.env` by walking up from cwd, then falls back to
`~/.config/taskcli/.env` (so a single `.env` shared with the task app works unchanged).

## 3. Install & run

```bash
pip install -e ".[mcp]"     # execution layer + FastMCP server
python -m kb_mcp            # launch the MCP server (stdio)
```

Library use:

```python
from kb_program import KbCLI

api = KbCLI()
api.set_knowledge_base("# Notes\n- prefers terse status updates")
print(api.get_knowledge_base()["content"])
api.append_knowledge_base("- deadline-driven; surface overdue tasks first")
```

## MCP tools

| Tool | Action |
|------|--------|
| `get_knowledge_base`    | Return the KB markdown (creates an empty KB on first read) |
| `set_knowledge_base`    | Replace the entire KB with new markdown |
| `append_knowledge_base` | Append a note on its own line, preserving existing content |
| `clear_knowledge_base`  | Empty the KB (keeps the record) |
| `delete_knowledge_base_line` | Delete a single line (1-based) from the KB |
| `delete_knowledge_base` | Delete the entire KB file (the whole record) |

Document-tree tools (the agent navigates the same tree the app shows; documents are
addressed by a slash-separated **title path**, e.g. `Personal/Ideas/Roadmap`):

| Tool | Action |
|------|--------|
| `list_documents`   | Show the folder/document tree as indented text |
| `read_document`    | Return a document's markdown content (by path) |
| `write_document`   | Replace a document's content (by path) |
| `create_document`  | Create a document/folder under a parent path (empty = top level) |
| `rename_document`  | Rename the document at a path |
| `move_document`    | Reparent a document to another path at an index |
| `delete_document`  | Delete a document and its whole subtree |

`KbError` is returned as `Error: ...` rather than raised, so the agent never sees a
traceback.

## REST API

A FastAPI client over the same `KbCLI`, for non-MCP callers. Single-user (operates on
`KB_USER`); touches only the `knowledge_base` table.

```bash
pip install -e ".[api]"     # execution layer + FastAPI + uvicorn
python -m kb_api            # serves on 127.0.0.1:8000 (KB_API_HOST/KB_API_PORT to override)
```

Interactive Swagger UI at `http://127.0.0.1:8000/docs`. Every endpoint returns the
normalized KB object `{user_id, content, created_at, updated_at}`.

| Method & path | Action |
|---------------|--------|
| `GET /knowledge-base`          | Return the KB (creates an empty KB on first read) |
| `PUT /knowledge-base`          | Replace the entire KB — body `{"content": "..."}` |
| `PATCH /knowledge-base/append` | Append a note on its own line — body `{"text": "..."}` |
| `DELETE /knowledge-base`       | Empty the KB content (keeps the row and `created_at`) |
| `DELETE /knowledge-base/lines/{n}` | Delete a single line (1-based), keeping the rest |
| `DELETE /knowledge-base/file`  | Delete the entire KB file — the whole row (a later GET recreates an empty one) |

Document-tree routes (single-user; operate on `KB_USER`). Document ids contain a colon
(`document:abc`) and are passed inline in the path. `GET /documents` omits `content`;
`GET /documents/{id}` includes it.

| Method & path | Action |
|---------------|--------|
| `GET /documents`              | List the tree as a flat array (metadata only), ordered by position |
| `POST /documents`             | Create — body `{"title": "...", "parent_id": "...|null", "is_folder": false}` |
| `GET /documents/{id}`         | Return one document including its markdown content |
| `PUT /documents/{id}`         | Update — body `{"content": "...", "title": "..."}` (either/both) |
| `POST /documents/{id}/move`   | Reparent — body `{"new_parent_id": "...|null", "index": 0}` |
| `DELETE /documents/{id}`      | Delete the document and its whole subtree |

`KbError` becomes an HTTP `400` with `{"detail": "..."}`, mirroring the MCP client's
`Error: ...` contract.

## Follow-ups (out of scope for now)

- **Real multi-user / auth** — per-owner Personal sections and a genuinely shared/access-
  controlled Team area; the `owner` field + `record<user>` links already model it, and
  visibility moves from in-code filtering to table `PERMISSIONS`.
- **Version history** — a `*_version` table snapshotted on each save.
- **Drag-move polish, search, multi-select** in the Flutter tree.
- Folding `kb_program` / `kb_mcp` into the task app for a single MCP surface.
