-- Read-only. Run on the intended deployment database before migration 004.
-- Output contains schema and counts, never notes, credentials or tokens.
BEGIN READ ONLY;
SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = current_schema()
  AND table_name IN ('user_entries', 'sync_changes', 'sync_user_cursors')
  AND column_name IN ('id', 'user_id', 'metadata_json', 'created_at',
    'updated_at', 'client_entry_id', 'user_sequence', 'last_sequence')
ORDER BY table_name, ordinal_position;

SELECT count(*) AS entries,
  count(*) FILTER (WHERE to_jsonb(e)->>'client_entry_id' IS NOT NULL) AS bound_entries,
  count(*) FILTER (WHERE NULLIF(btrim(metadata_json->>'local_id'), '') IS NULL) AS missing_local_ids
FROM user_entries e;

SELECT count(*) AS ambiguous_historical_identity_groups
FROM (
  SELECT user_id, metadata_json->>'local_id'
  FROM user_entries
  WHERE NULLIF(btrim(metadata_json->>'local_id'), '') IS NOT NULL
  GROUP BY user_id, metadata_json->>'local_id' HAVING count(*) > 1
) ambiguous;

-- Must be zero. Nonzero means stop; never auto-delete or reassign these rows.
SELECT count(*) AS duplicate_bound_identity_groups
FROM (
  SELECT user_id, to_jsonb(e)->>'client_entry_id'
  FROM user_entries e
  WHERE to_jsonb(e)->>'client_entry_id' IS NOT NULL
  GROUP BY user_id, to_jsonb(e)->>'client_entry_id' HAVING count(*) > 1
) duplicates;

SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = current_schema() AND tablename = 'user_entries'
  AND indexname = 'idx_user_entries_user_client_entry';
COMMIT;
