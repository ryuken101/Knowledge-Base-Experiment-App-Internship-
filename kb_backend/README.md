# kb_backend

A per-user **knowledge base** for the task-managing agent, backed by **SurrealDB**.

The KB is deliberately rudimentary: **one freeform markdown ("Obsidian") file per
user**. The agent reads and writes it over **MCP** as its persistent notes about how to
manage that user's tasks. It lives in the **same SurrealDB instance** (`main` ns/db) as
the task app and links to the task app's `user` table.

```
kb_backend/
├── schema.surql      # complete fresh-install schema (task tables + knowledge_base)
├── reset.surql       # wipe all records, keep the schema
├── kb_program/       # execution layer (library only): KbCLI + SurrealDB access
├── kb_mcp/           # FastMCP server: one tool per KbCLI method
└── kb_api/           # FastAPI REST server: one endpoint per KbCLI method
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

`KbError` becomes an HTTP `400` with `{"detail": "..."}`, mirroring the MCP client's
`Error: ...` contract.

## Follow-ups (out of scope for now)

- **Version history** — a `knowledge_base_version` table snapshotted on each save.
- **Multiple users / auth** — real `user` records and per-user access; the
  `record<user>` link + unique index already support it.
- **Flutter frontend** (go_router / riverpod / dio) — a markdown editor over the KB.
- Folding `kb_program` / `kb_mcp` into the task app for a single MCP surface.
