-- Phase 1B: stable client identity for idempotent user-entry uploads.
-- Existing rows are backfilled only when their metadata local_id is unique
-- for that user. Ambiguous historical duplicates remain unbound.

BEGIN;
SET LOCAL lock_timeout = '5s';
-- Serialize the backfill and index creation against legacy writers.
LOCK TABLE user_entries IN SHARE ROW EXCLUSIVE MODE;

ALTER TABLE user_entries
  ADD COLUMN IF NOT EXISTS client_entry_id TEXT;

WITH unique_local_ids AS (
  SELECT user_id,
         metadata_json ->> 'local_id' AS local_id
  FROM user_entries
  WHERE NULLIF(BTRIM(metadata_json ->> 'local_id'), '') IS NOT NULL
  GROUP BY user_id, metadata_json ->> 'local_id'
  HAVING COUNT(*) = 1
)
UPDATE user_entries AS entries
SET client_entry_id = unique_local_ids.local_id
FROM unique_local_ids
WHERE entries.user_id = unique_local_ids.user_id
  AND entries.metadata_json ->> 'local_id' = unique_local_ids.local_id
  AND entries.client_entry_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM user_entries AS bound
    WHERE bound.user_id = entries.user_id
      AND bound.client_entry_id = unique_local_ids.local_id
  );

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_entries_user_client_entry
  ON user_entries(user_id, client_entry_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_index
    WHERE indexrelid = 'idx_user_entries_user_client_entry'::regclass
      AND indrelid = 'user_entries'::regclass
      AND indisunique AND indisvalid AND indpred IS NULL AND indexprs IS NULL
      AND indnkeyatts = 2
      AND pg_get_indexdef(indexrelid, 1, true) = 'user_id'
      AND pg_get_indexdef(indexrelid, 2, true) = 'client_entry_id'
  ) THEN
    RAISE EXCEPTION '004: conflicting client-entry index; inspect before retrying';
  END IF;
END $$;

COMMIT;
