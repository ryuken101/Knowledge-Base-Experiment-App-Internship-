-- Wipe all records while keeping the schema. Run via the Surrealist query editor
-- (paste -> Run query) or `surreal import` against the main namespace/database.
-- Handy for re-running tests on the same instance without re-importing schema.surql.
--
-- Order is harmless here: record links are loose references, so there is no FK
-- cascade to honor (unlike the old Postgres schema). Children first anyway, for
-- readability.

DELETE knowledge_base;
DELETE comment;
DELETE activity;
DELETE task;
DELETE project;
DELETE user;
