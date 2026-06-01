-- Fresh-install schema for the knowledge-base backend on SurrealDB.
-- Import once into an instance (namespace + database = main) via the Surrealist
-- query editor (paste -> Run query) or `surreal import`. Safe to re-run: every
-- statement uses IF NOT EXISTS.
--
-- This is a COMPLETE fresh-install schema: it contains the task app's schema
-- verbatim (user, project, task, activity, comment) PLUS the knowledge_base
-- table. Importing it into a brand-new, empty instance therefore produces a
-- fully working environment for testing the agent end-to-end (tasks + KB) with
-- no dependency on the task app having been imported first. It is also safe to
-- run against an instance that already has the task tables.
--
-- We connect as root, so no table PERMISSIONS are needed (root bypasses them) --
-- this is the SurrealDB analog of "RLS off everywhere" under the old Postgres schema.

-- ===========================================================================
-- Task app schema (copied verbatim so the KB's record<user> link resolves on a
-- fresh instance). Keep in sync with the task app's own schema.surql.
-- ===========================================================================

-- Users. Dead structure for now: no records created until user management is
-- reintroduced. task.assignee and the *.author links below reference it.
DEFINE TABLE IF NOT EXISTS user SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS name  ON user TYPE string;
DEFINE FIELD IF NOT EXISTS email ON user TYPE option<string>;

-- Projects are shelved (dead). Kept so they can be reincorporated later;
-- task.project links here but is currently unused. Dates are stored as plain
-- 'YYYY-MM-DD' strings to match the client contract (see task.due_date below).
DEFINE TABLE IF NOT EXISTS project SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS title        ON project TYPE string;
DEFINE FIELD IF NOT EXISTS description  ON project TYPE string DEFAULT '';
DEFINE FIELD IF NOT EXISTS start_date   ON project TYPE string;
DEFINE FIELD IF NOT EXISTS end_date     ON project TYPE string;
DEFINE FIELD IF NOT EXISTS no_of_stages ON project TYPE int ASSERT $value > 0;

-- Tasks. status is free text (default 'To Do'); any string is accepted.
-- due_date is a 'YYYY-MM-DD' string (not a datetime) so it round-trips to clients
-- unchanged with no timezone games. created_at is a real datetime for ordering.
DEFINE TABLE IF NOT EXISTS task SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS title       ON task TYPE string;
DEFINE FIELD IF NOT EXISTS description ON task TYPE option<string>;
DEFINE FIELD IF NOT EXISTS status      ON task TYPE string DEFAULT 'To Do';
DEFINE FIELD IF NOT EXISTS due_date    ON task TYPE option<string>;
DEFINE FIELD IF NOT EXISTS assignee    ON task TYPE option<record<user>>;
DEFINE FIELD IF NOT EXISTS stage_id    ON task TYPE option<string>;
DEFINE FIELD IF NOT EXISTS project     ON task TYPE option<record<project>>;
DEFINE FIELD IF NOT EXISTS created_at  ON task TYPE datetime DEFAULT time::now();

-- Auto-recorded activity history. One row per changed task field (see program.py).
DEFINE TABLE IF NOT EXISTS activity SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS task               ON activity TYPE record<task>;
DEFINE FIELD IF NOT EXISTS type               ON activity TYPE string DEFAULT 'history';
DEFINE FIELD IF NOT EXISTS action             ON activity TYPE string;
DEFINE FIELD IF NOT EXISTS field              ON activity TYPE option<string>;
DEFINE FIELD IF NOT EXISTS old_value          ON activity TYPE option<string>;
DEFINE FIELD IF NOT EXISTS new_value          ON activity TYPE option<string>;
DEFINE FIELD IF NOT EXISTS text               ON activity TYPE option<string>;
DEFINE FIELD IF NOT EXISTS author             ON activity TYPE option<record<user>>;
DEFINE FIELD IF NOT EXISTS legacy_author_name ON activity TYPE option<string>;
DEFINE FIELD IF NOT EXISTS created_at         ON activity TYPE datetime DEFAULT time::now();

-- Free-text comments. Never auto-logged; added only via add_comment.
DEFINE TABLE IF NOT EXISTS comment SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS task               ON comment TYPE record<task>;
DEFINE FIELD IF NOT EXISTS text               ON comment TYPE string;
DEFINE FIELD IF NOT EXISTS author             ON comment TYPE option<record<user>>;
DEFINE FIELD IF NOT EXISTS legacy_author_name ON comment TYPE option<string>;
DEFINE FIELD IF NOT EXISTS created_at         ON comment TYPE datetime DEFAULT time::now();

DEFINE INDEX IF NOT EXISTS activity_task ON activity FIELDS task;
DEFINE INDEX IF NOT EXISTS comment_task  ON comment  FIELDS task;

-- ===========================================================================
-- Knowledge base
-- ===========================================================================

-- Knowledge base: one freeform markdown ("Obsidian") file per user. The agent
-- reads/writes this via the MCP as its persistent notes for managing that user's
-- tasks. Links to the `user` table defined above (currently dead structure).
-- Exactly one row per user, enforced by a UNIQUE index on `user`. content is
-- markdown text; created_at is set once, updated_at is bumped by the backend on
-- every write.
DEFINE TABLE IF NOT EXISTS knowledge_base SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS user       ON knowledge_base TYPE record<user>;
DEFINE FIELD IF NOT EXISTS content    ON knowledge_base TYPE string DEFAULT '';
DEFINE FIELD IF NOT EXISTS created_at ON knowledge_base TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS updated_at ON knowledge_base TYPE datetime DEFAULT time::now();

DEFINE INDEX IF NOT EXISTS knowledge_base_user ON knowledge_base FIELDS user UNIQUE;
