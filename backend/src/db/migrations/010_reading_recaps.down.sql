-- Empty-feature rollback only. User data/tombstones must never be discarded.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '30s';
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM reading_recaps)
     OR EXISTS (SELECT 1 FROM xiaou_conversations WHERE recap_id IS NOT NULL OR kind = 'book_recap')
  THEN
    RAISE EXCEPTION '010 rollback refused: recap data or deletion fences exist';
  END IF;
END $$;
DROP INDEX idx_xiaou_conversation_recap;
ALTER TABLE xiaou_conversations DROP CONSTRAINT xiaou_recap_kind_ck;
ALTER TABLE xiaou_conversations DROP CONSTRAINT xiaou_recap_owner_fk;
ALTER TABLE xiaou_conversations DROP COLUMN recap_id;
DROP TABLE reading_recap_operations;
DROP TABLE reading_recap_feedback;
DROP TABLE reading_recap_sources;
DROP TABLE reading_recaps;
COMMIT;
