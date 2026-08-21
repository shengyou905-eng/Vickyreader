CREATE TABLE IF NOT EXISTS user_library_books (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  author TEXT NOT NULL DEFAULT '',
  format TEXT NOT NULL DEFAULT '',
  added_at TIMESTAMPTZ,
  last_opened_at TIMESTAMPTZ,
  synced_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, book_id)
);

CREATE INDEX IF NOT EXISTS idx_user_library_books_user_opened
  ON user_library_books(user_id, last_opened_at DESC NULLS LAST, added_at DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_user_library_books_user_title
  ON user_library_books(user_id, lower(title));

CREATE TABLE IF NOT EXISTS mcp_access_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash BYTEA NOT NULL UNIQUE,
  token_prefix TEXT NOT NULL,
  label TEXT NOT NULL DEFAULT 'MCP access',
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  last_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mcp_access_tokens_user_active
  ON mcp_access_tokens(user_id, created_at DESC)
  WHERE revoked_at IS NULL;
