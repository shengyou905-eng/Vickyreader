BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS reading_progress_upload_states (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id TEXT NOT NULL,
  writer_id UUID,
  latest_revision BIGINT NOT NULL DEFAULT 0 CHECK (latest_revision >= 0),
  deleted BOOLEAN NOT NULL DEFAULT false,
  request_hash TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, book_id)
);

-- Baseline only: no canonical timestamps or synthetic ledger events change.
INSERT INTO reading_progress_upload_states (user_id, book_id)
SELECT user_id, book_id FROM reading_progresses
ON CONFLICT (user_id, book_id) DO NOTHING;

COMMIT;
