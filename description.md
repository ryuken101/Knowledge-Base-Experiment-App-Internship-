# Project Description — Knowledge Base (KB) Backend for the Task Agent

Build a per-user **knowledge base (KB)** that an AI agent uses as persistent memory while it manages a *separate* SurrealDB-backed **task manager** app. Each user's agent gets **one freeform markdown ("Obsidian") file** it reads and writes as its notes, accessed over **MCP**. The KB lives in the **same SurrealDB instance** (`main` ns/db) as the task app and links to the task app's `user` table.

> **Design change from the legacy KbApp brief:** the old prototype modelled the KB as many `Document` records in nested folders, edited through a Flutter two-panel UI. That was dropped in favour of a single markdown file per user. There is therefore **no folder hierarchy, no multiple documents, and no doc-preview/directory UI** — those requirements are intentionally gone. A Flutter editor over the single file remains on the roadmap but is not the primary surface; the agent (over MCP) is.

## Stack

- **Backend (active):** Python + **SurrealDB** SDK (direct calls, no ORM) + **MCP** (`FastMCP`).
- **Agent interface:** MCP tools (stdio server), one tool per KB verb.
- **Frontend (roadmap, not built):** Flutter + go_router + riverpod + dio — a markdown editor over the single KB file.

## Architecture

- `kb_program/` — client-agnostic **execution layer** (library only, no MCP/CLI imports): `KbCLI` with one method per verb, `db.py` client factory (signs in as **root**), `models.py` (`KnowledgeBase` + `KbError`).
- `kb_mcp/` — `FastMCP` server exposing one `@mcp.tool()` per `KbCLI` method; `KbError` is returned as `f"Error: {e}"`, never raised at the agent.
- `schema.surql` / `reset.surql` — complete fresh-install schema (task tables + `knowledge_base`) and a record-wipe script.

## Requirements

### Stage 1 — Single-file KB (current)

**Agent / MCP surface (replaces the old "Front End"):**
- Create-on-read: the agent always has a KB row to read/append to (`get_knowledge_base`).
- Read the whole KB as markdown.
- Replace the whole KB (manual full save) — `set_knowledge_base`.
- Append a note on its own line, preserving existing content — `append_knowledge_base`.
- Clear the KB content while keeping the record — `clear_knowledge_base`.

**Backend:**
- CRUD for the single markdown document, stored in the `knowledge_base` table in SurrealDB.
- **Exactly one KB row per user**, enforced by a `UNIQUE` index on the `user` field.
- `created_at` set once (schema default); `updated_at` bumped explicitly by the backend on every write.
- **Single configurable user** for now (the `user` table is dead structure / no auth): pass `user_id` or set `KB_USER` (default `user:agent`); the user record is seeded on first write so the `record<user>` link is backed by a real row.
- Connection signs in as **root** (bypasses table permissions — the single-user analog of "RLS off").

### Stage 2 — Version history

- New `knowledge_base_version` table, snapshotted on each save.
- Verbs/tools to **list versions** and **restore a previous version**.

### Stage 3 — Multiple users / auth

- Real `user` records and per-user access. The `record<user>` link + unique index already make this **purely additive** — don't add user CRUD/auth without revisiting the single-user assumptions.

### Roadmap (beyond the stages)

- **Flutter frontend** (go_router / riverpod / dio): a markdown editor over the single KB file.
- Fold `kb_program` / `kb_mcp` into the task app so the agent sees **tasks + KB through one MCP server**.
