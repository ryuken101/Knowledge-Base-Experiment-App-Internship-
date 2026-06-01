# Setup — knowledge base backend

Get the REST server (`kb_api`) talking to a SurrealDB instance. Run all commands from
`kb_backend/`.

> ⚠️ **SurrealDB and the API must use different ports.** SurrealDB defaults to `8000` and
> the API (`kb_api`) also defaults to `8000`. If `SURREALDB_URL` and the API point at the
> same `host:port`, the API ends up connecting to *itself* — the WebSocket handshake to
> `/rpc` is rejected with **HTTP 403**. Below we keep **SurrealDB on 8000** and run the
> **API on 8001**.

## 1. Install SurrealDB

Pick one:

```bash
# Windows (PowerShell)
iwr https://install.surrealdb.com -useb | iex

# macOS / Linux
curl -sSf https://install.surrealdb.com | sh

# or Docker (no install)
docker run --rm -p 8000:8000 surrealdb/surrealdb:latest \
  start --user root --pass root
```

## 2. Start SurrealDB (on port 8000)

Skip if you used the Docker command above (it already starts one).

```bash
# In-memory (data lost on restart — fine for testing):
surreal start --user root --pass root memory

# Or persist to a file:
surreal start --user root --pass root rocksdb:kb.db
```

This binds to `127.0.0.1:8000` by default. Add `--bind 0.0.0.0:8000` to expose it.

## 3. Import the schema (once)

```bash
surreal import --endpoint http://127.0.0.1:8000 \
  --username root --password root --namespace main --database main \
  schema.surql
```

(Older SurrealDB uses `--conn/--user/--pass/--ns/--db`.) Or paste `schema.surql` into the
Surrealist query editor → Run query. It's idempotent (`IF NOT EXISTS`), safe to re-run.

## 4. Configure credentials

```bash
cp .env.example .env        # PowerShell: Copy-Item .env.example .env
```

Edit `.env` so it matches the SurrealDB you started, and set the API to a **different
port**:

```ini
SURREALDB_URL=ws://127.0.0.1:8000/rpc
SURREALDB_USER=root
SURREALDB_PASS=root
SURREALDB_NS=main
SURREALDB_DB=main
KB_USER=user:agent
KB_API_HOST=127.0.0.1
KB_API_PORT=8001
```

## 5. Install and run the API

```bash
pip install -e ".[api]"     # execution layer + FastAPI + uvicorn
python -m kb_api            # serves on http://127.0.0.1:8001
```

Swagger UI: **http://127.0.0.1:8001/docs**

## 6. Smoke test

```bash
curl http://127.0.0.1:8001/knowledge-base
curl -X PUT  http://127.0.0.1:8001/knowledge-base   -H "Content-Type: application/json" -d '{"content":"# Notes"}'
curl -X PATCH http://127.0.0.1:8001/knowledge-base/append -H "Content-Type: application/json" -d '{"text":"- a line"}'
```

## Endpoints

| Method & path | Action |
|---------------|--------|
| `GET /knowledge-base`              | Return the KB (creates an empty KB on first read) |
| `PUT /knowledge-base`              | Replace the entire KB — body `{"content": "..."}` |
| `PATCH /knowledge-base/append`     | Append a note on its own line — body `{"text": "..."}` |
| `DELETE /knowledge-base`           | Empty the KB content (keeps the row and `created_at`) |
| `DELETE /knowledge-base/lines/{n}` | Delete a single line (1-based), keeping the rest |
| `DELETE /knowledge-base/file`      | Delete the entire KB file — the whole row |

Every endpoint returns `{user_id, content, created_at, updated_at}` (the `/file` delete
returns `{user_id, deleted}`). A `KbError` is surfaced as HTTP `400 {"detail": "..."}`.

## Troubleshooting

- **`InvalidStatus: server rejected WebSocket connection: HTTP 403`** during `signin` —
  `SURREALDB_URL` is pointing at something that isn't SurrealDB (commonly the API itself,
  if both are on `8000`). Confirm with `curl -i http://<host>:<port>/health`: a real
  SurrealDB answers, a `server: uvicorn` / `{"detail":"Not Found"}` response means you hit
  the FastAPI app. Use distinct ports (steps 2 + 4).
- **Connection refused** — no SurrealDB is running at `SURREALDB_URL` (start it, step 2).
- **Auth error after a successful handshake** — wrong `SURREALDB_USER`/`PASS` (must match
  what `surreal start` was given).
