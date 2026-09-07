BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS user_entry_upload_states (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_entry_id TEXT NOT NULL,
  writer_id UUID,
  latest_revision BIGINT NOT NULL DEFAULT 0 CHECK (latest_revision >= 0),
  deleted BOOLEAN NOT NULL DEFAULT false,
  book_id TEXT,
  request_hash TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, client_entry_id)
);
CREATE INDEX IF NOT EXISTS idx_entry_upload_states_book
  ON user_entry_upload_states(user_id, book_id);

CREATE TABLE IF NOT EXISTS permanently_deleted_books (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id TEXT NOT NULL,
  deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, book_id)
);

-- Preserve canonical IDs and timestamps; do not invent historical ledger events.
INSERT INTO user_entry_upload_states (user_id, client_entry_id, book_id)
SELECT user_id, client_entry_id, book_id FROM user_entries
WHERE client_entry_id IS NOT NULL
ON CONFLICT (user_id, client_entry_id) DO NOTHING;
COMMIT;
