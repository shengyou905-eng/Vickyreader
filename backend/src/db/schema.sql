CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  source TEXT NOT NULL CHECK (
    source IN ('highlight', 'thought', 'ai_explanation', 'manual')
  ),

  book_id TEXT,
  book_title TEXT,
  chapter_index TEXT,

  original_text TEXT,
  user_input TEXT,
  ai_explanation TEXT,
  auto_tags TEXT[] NOT NULL DEFAULT '{}',
  auto_summary TEXT,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_entries_user_id
  ON user_entries(user_id);

CREATE INDEX IF NOT EXISTS idx_user_entries_user_created
  ON user_entries(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_entries_user_source
  ON user_entries(user_id, source);

CREATE INDEX IF NOT EXISTS idx_user_entries_tags
  ON user_entries USING GIN(auto_tags);
