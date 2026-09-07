-- Phase 1A: append-only change ledger for future read-only integrations.
--
-- Apply with:
--   psql "$DATABASE_URL" -f backend/src/db/migrations/003_sync_changes_ledger.up.sql
--
-- Existing business rows are intentionally not emitted as synthetic
-- "created" events. A future initial sync must read a repeatable-read
-- snapshot and the same snapshot's per-user last_sequence watermark, then
-- continue with sync_changes.user_sequence greater than that watermark.

ALTER TABLE user_entries
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

UPDATE user_entries
SET updated_at = created_at
WHERE updated_at IS NULL;

ALTER TABLE user_entries
  ALTER COLUMN updated_at SET DEFAULT now();

ALTER TABLE user_entries
  ALTER COLUMN updated_at SET NOT NULL;

CREATE TABLE IF NOT EXISTS sync_user_cursors (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  last_sequence BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS sync_changes (
  sequence BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_sequence BIGINT,
  entity_type TEXT NOT NULL CHECK (
    entity_type IN ('trace', 'reading_progress', 'book')
  ),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (
    operation IN ('created', 'updated', 'deleted')
  ),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE sync_changes
  ADD COLUMN IF NOT EXISTS user_sequence BIGINT;

-- This backfill only supports an interrupted/local pre-release application of
-- Phase 1A. Production has not received this migration, so no released cursor
-- can depend on the unsafe global sequence ordering.
WITH ranked_changes AS (
  SELECT sequence,
         ROW_NUMBER() OVER (
           PARTITION BY user_id
           ORDER BY sequence
         )::BIGINT AS user_sequence
  FROM sync_changes
  WHERE user_sequence IS NULL
)
UPDATE sync_changes AS changes
SET user_sequence = ranked_changes.user_sequence
FROM ranked_changes
WHERE changes.sequence = ranked_changes.sequence;

INSERT INTO sync_user_cursors (user_id, last_sequence)
SELECT user_id, MAX(user_sequence)
FROM sync_changes
GROUP BY user_id
ON CONFLICT (user_id) DO UPDATE
SET last_sequence = GREATEST(
  sync_user_cursors.last_sequence,
  EXCLUDED.last_sequence
);

ALTER TABLE sync_changes
  ALTER COLUMN user_sequence SET NOT NULL;

DROP INDEX IF EXISTS idx_sync_changes_user_sequence;
DROP INDEX IF EXISTS idx_sync_changes_user_sequence_unique;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_changes_user_sequence
  ON sync_changes(user_id, user_sequence);
