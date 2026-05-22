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

CREATE TABLE IF NOT EXISTS public_books (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  publisher_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source_book_id TEXT NOT NULL,
  title TEXT NOT NULL,
  author TEXT,
  cover_url TEXT,
  description TEXT,
  copyright_status TEXT NOT NULL CHECK (
    copyright_status IN ('public_domain', 'original', 'authorized')
  ),
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  borrow_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(publisher_user_id, source_book_id)
);

CREATE INDEX IF NOT EXISTS idx_public_books_created
  ON public_books(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_public_books_copyright
  ON public_books(copyright_status);

CREATE TABLE IF NOT EXISTS public_annotations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id UUID NOT NULL UNIQUE REFERENCES user_entries(id) ON DELETE CASCADE,
  public_book_id UUID REFERENCES public_books(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  source TEXT NOT NULL CHECK (
    source IN ('highlight', 'thought', 'ai_explanation', 'manual')
  ),

  book_id TEXT,
  book_title TEXT,
  book_author TEXT,
  book_cover TEXT,
  chapter_index TEXT,
  chapter_title TEXT,

  original_text TEXT,
  annotation_text TEXT,
  auto_tags TEXT[] NOT NULL DEFAULT '{}',
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public_annotations
  ADD COLUMN IF NOT EXISTS book_author TEXT;

ALTER TABLE public_annotations
  ADD COLUMN IF NOT EXISTS public_book_id UUID REFERENCES public_books(id) ON DELETE CASCADE;

ALTER TABLE public_annotations
  ADD COLUMN IF NOT EXISTS book_cover TEXT;

ALTER TABLE public_annotations
  ADD COLUMN IF NOT EXISTS chapter_title TEXT;

CREATE INDEX IF NOT EXISTS idx_public_annotations_created
  ON public_annotations(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_public_annotations_book
  ON public_annotations(book_id);

CREATE INDEX IF NOT EXISTS idx_public_annotations_public_book
  ON public_annotations(public_book_id);

CREATE INDEX IF NOT EXISTS idx_public_annotations_entry
  ON public_annotations(entry_id);

CREATE TABLE IF NOT EXISTS resonances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  annotation_id UUID NOT NULL REFERENCES public_annotations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_resonances_annotation
  ON resonances(annotation_id, created_at DESC);
