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
  chapter_title TEXT,

  original_text TEXT,
  user_input TEXT,
  ai_explanation TEXT,
  auto_tags TEXT[] NOT NULL DEFAULT '{}',
  auto_summary TEXT,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE user_entries
  ADD COLUMN IF NOT EXISTS chapter_title TEXT;

CREATE INDEX IF NOT EXISTS idx_user_entries_user_id
  ON user_entries(user_id);

CREATE INDEX IF NOT EXISTS idx_user_entries_user_created
  ON user_entries(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_entries_user_source
  ON user_entries(user_id, source);

CREATE INDEX IF NOT EXISTS idx_user_entries_tags
  ON user_entries USING GIN(auto_tags);

CREATE TABLE IF NOT EXISTS reading_progresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id TEXT NOT NULL,
  progress DOUBLE PRECISION NOT NULL DEFAULT 0,
  chapter_index TEXT NOT NULL DEFAULT '0',
  scroll_offset DOUBLE PRECISION NOT NULL DEFAULT 0,
  cfi TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, book_id)
);

CREATE INDEX IF NOT EXISTS idx_reading_progresses_user_book
  ON reading_progresses(user_id, book_id);
