CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'user' CHECK (
    role IN ('user', 'admin')
  );

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS account_status TEXT NOT NULL DEFAULT 'active' CHECK (
    account_status IN ('active', 'banned')
  );

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS ban_reason TEXT NOT NULL DEFAULT '';

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 0;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS ai_consent_version INTEGER NOT NULL DEFAULT 0;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS ai_consent_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS user_profiles (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  nickname TEXT NOT NULL DEFAULT '',
  avatar_url TEXT NOT NULL DEFAULT '',
  bio TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS nickname TEXT NOT NULL DEFAULT '';

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS avatar_url TEXT NOT NULL DEFAULT '';

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS bio TEXT NOT NULL DEFAULT '';

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

CREATE TABLE IF NOT EXISTS free_notes (
  id TEXT NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, id)
);

ALTER TABLE free_notes
  ADD COLUMN IF NOT EXISTS title TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_free_notes_user_updated
  ON free_notes(user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS xiaou_free_note_grants (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  free_note_id TEXT NOT NULL,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, free_note_id),
  FOREIGN KEY (user_id, free_note_id)
    REFERENCES free_notes(user_id, id)
    ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_xiaou_free_note_grants_user
  ON xiaou_free_note_grants(user_id, granted_at DESC);

CREATE TABLE IF NOT EXISTS user_insights (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  recent_focus JSONB NOT NULL DEFAULT '{}'::jsonb,
  weekly_summary TEXT NOT NULL DEFAULT '',
  long_term_topics JSONB NOT NULL DEFAULT '[]'::jsonb,
  high_value_questions JSONB NOT NULL DEFAULT '[]'::jsonb,
  recent_entries JSONB NOT NULL DEFAULT '[]'::jsonb,
  deep_reflection TEXT NOT NULL DEFAULT '',
  source_entry_count INTEGER NOT NULL DEFAULT 0,
  authorized_note_count INTEGER NOT NULL DEFAULT 0,
  refreshed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_insights_refreshed
  ON user_insights(refreshed_at DESC);

ALTER TABLE user_insights
  ADD COLUMN IF NOT EXISTS recent_entries JSONB NOT NULL DEFAULT '[]'::jsonb;

CREATE TABLE IF NOT EXISTS public_books (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  publisher_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  uploader_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  source_book_id TEXT NOT NULL,
  title TEXT NOT NULL,
  author TEXT,
  cover_url TEXT,
  file_url TEXT,
  original_file_url TEXT,
  storage_path TEXT,
  file_type TEXT,
  file_size BIGINT NOT NULL DEFAULT 0,
  description TEXT,
  authoritative_description TEXT,
  authoritative_description_source TEXT,
  authoritative_description_url TEXT,
  one_line_summary TEXT,
  one_line_summary_source TEXT,
  encounter_summary TEXT,
  expanded_guide TEXT,
  why_worth_reading TEXT,
  reading_themes JSONB NOT NULL DEFAULT '[]'::jsonb,
  summary_updated_at TIMESTAMPTZ,
  copyright_status TEXT NOT NULL CHECK (
    copyright_status IN ('public_domain', 'original', 'authorized')
  ),
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  borrow_count INTEGER NOT NULL DEFAULT 0,
  read_count INTEGER NOT NULL DEFAULT 0,
  chapter_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(publisher_user_id, source_book_id)
);

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS file_url TEXT;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS original_file_url TEXT;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS storage_path TEXT;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS file_type TEXT;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS file_size BIGINT NOT NULL DEFAULT 0;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS chapter_count INTEGER NOT NULL DEFAULT 0;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS authoritative_description TEXT;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS authoritative_description_source TEXT;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS authoritative_description_url TEXT;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS one_line_summary TEXT;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS one_line_summary_source TEXT;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS encounter_summary TEXT;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS expanded_guide TEXT;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS why_worth_reading TEXT;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS reading_themes JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS summary_updated_at TIMESTAMPTZ;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS uploader_user_id UUID REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE public_books
  ADD COLUMN IF NOT EXISTS read_count INTEGER NOT NULL DEFAULT 0;

UPDATE public_books
SET uploader_user_id = publisher_user_id
WHERE uploader_user_id IS NULL;

UPDATE public_books
SET original_file_url = file_url
WHERE original_file_url IS NULL AND file_url IS NOT NULL;

UPDATE public_books
SET read_count = borrow_count
WHERE read_count = 0 AND borrow_count > 0;

CREATE INDEX IF NOT EXISTS idx_public_books_created
  ON public_books(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_public_books_copyright
  ON public_books(copyright_status);

CREATE TABLE IF NOT EXISTS book_chapters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  public_book_id UUID NOT NULL REFERENCES public_books(id) ON DELETE CASCADE,
  book_id UUID REFERENCES public_books(id) ON DELETE CASCADE,
  chapter_index INTEGER NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  chapter_title TEXT,
  content TEXT NOT NULL DEFAULT '',
  content_html TEXT,
  plain_text TEXT NOT NULL DEFAULT '',
  content_text TEXT,
  word_count INTEGER NOT NULL DEFAULT 0,
  href TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(public_book_id, chapter_index)
);

CREATE INDEX IF NOT EXISTS idx_book_chapters_public_book
  ON book_chapters(public_book_id, chapter_index);

ALTER TABLE book_chapters
  ADD COLUMN IF NOT EXISTS book_id UUID REFERENCES public_books(id) ON DELETE CASCADE;

ALTER TABLE book_chapters
  ADD COLUMN IF NOT EXISTS chapter_title TEXT;

ALTER TABLE book_chapters
  ADD COLUMN IF NOT EXISTS content_html TEXT;

ALTER TABLE book_chapters
  ADD COLUMN IF NOT EXISTS content_text TEXT;

ALTER TABLE book_chapters
  ADD COLUMN IF NOT EXISTS word_count INTEGER NOT NULL DEFAULT 0;

UPDATE book_chapters
SET book_id = public_book_id
WHERE book_id IS NULL;

UPDATE book_chapters
SET chapter_title = title
WHERE chapter_title IS NULL;

UPDATE book_chapters
SET content_html = content
WHERE content_html IS NULL;

UPDATE book_chapters
SET content_text = plain_text
WHERE content_text IS NULL;

CREATE TABLE IF NOT EXISTS books (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_book_id TEXT NOT NULL,
  title TEXT NOT NULL,
  author TEXT,
  cover_url TEXT,
  description TEXT,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(source_book_id, title)
);

CREATE TABLE IF NOT EXISTS book_publications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  public_book_id UUID REFERENCES public_books(id) ON DELETE CASCADE,
  publisher_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source_book_id TEXT NOT NULL,
  copyright_status TEXT NOT NULL CHECK (
    copyright_status IN ('public_domain', 'original', 'authorized')
  ),
  reading_count INTEGER NOT NULL DEFAULT 0,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(publisher_user_id, source_book_id)
);

CREATE INDEX IF NOT EXISTS idx_book_publications_public_book
  ON book_publications(public_book_id);

CREATE INDEX IF NOT EXISTS idx_book_publications_created
  ON book_publications(created_at DESC);

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

ALTER TABLE public_annotations
  ADD COLUMN IF NOT EXISTS position_json JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public_annotations
  ALTER COLUMN entry_id DROP NOT NULL;

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

CREATE TABLE IF NOT EXISTS book_discussions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  public_book_id UUID NOT NULL REFERENCES public_books(id) ON DELETE CASCADE,
  annotation_id UUID REFERENCES public_annotations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  discussion_type TEXT NOT NULL DEFAULT 'resonance' CHECK (
    discussion_type IN ('thought', 'ai_explanation', 'resonance')
  ),
  anchor_text TEXT,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_book_discussions_public_book
  ON book_discussions(public_book_id, created_at DESC);

CREATE TABLE IF NOT EXISTS book_resonance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  public_book_id UUID REFERENCES public_books(id) ON DELETE CASCADE,
  annotation_id UUID REFERENCES public_annotations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_book_resonance_annotation
  ON book_resonance(annotation_id, created_at DESC);

CREATE TABLE IF NOT EXISTS annotation_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  annotation_id UUID NOT NULL REFERENCES public_annotations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_annotation_comments_annotation
  ON annotation_comments(annotation_id, created_at DESC);

CREATE TABLE IF NOT EXISTS annotation_resonances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  annotation_id UUID NOT NULL REFERENCES public_annotations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(annotation_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_annotation_resonances_annotation
  ON annotation_resonances(annotation_id, created_at DESC);

CREATE TABLE IF NOT EXISTS book_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  public_book_id UUID NOT NULL REFERENCES public_books(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_request_id TEXT,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE book_reviews
  ADD COLUMN IF NOT EXISTS client_request_id TEXT;

CREATE INDEX IF NOT EXISTS idx_book_reviews_book_created
  ON book_reviews(public_book_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_book_reviews_user_created
  ON book_reviews(user_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_book_reviews_client_request
  ON book_reviews(user_id, client_request_id)
  WHERE client_request_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS book_review_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id UUID NOT NULL REFERENCES book_reviews(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_book_review_comments_review
  ON book_review_comments(review_id, created_at ASC);

CREATE TABLE IF NOT EXISTS book_review_resonances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id UUID NOT NULL REFERENCES book_reviews(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(review_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_book_review_resonances_review
  ON book_review_resonances(review_id, created_at DESC);

CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (
    event_type IN (
      'annotation_comment',
      'annotation_resonance',
      'review_comment',
      'review_resonance'
    )
  ),
  target_type TEXT NOT NULL CHECK (target_type IN ('annotation', 'review')),
  target_id UUID NOT NULL,
  public_book_id UUID REFERENCES public_books(id) ON DELETE CASCADE,
  preview TEXT NOT NULL DEFAULT '',
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_recipient_created
  ON notifications(recipient_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_recipient_unread
  ON notifications(recipient_user_id, created_at DESC)
  WHERE read_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_unique_resonance
  ON notifications(recipient_user_id, actor_user_id, event_type, target_id)
  WHERE event_type IN ('annotation_resonance', 'review_resonance');

CREATE TABLE IF NOT EXISTS community_book_works (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  normalized_key TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  original_author TEXT NOT NULL DEFAULT '佚名',
  original_language TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS community_books (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_id UUID REFERENCES community_book_works(id) ON DELETE SET NULL,
  normalized_key TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  author TEXT NOT NULL DEFAULT '佚名',
  translator TEXT NOT NULL DEFAULT '',
  publisher TEXT NOT NULL DEFAULT '',
  publication_year TEXT NOT NULL DEFAULT '',
  language TEXT NOT NULL DEFAULT '',
  edition_label TEXT NOT NULL DEFAULT '',
  cover_url TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  isbn TEXT NOT NULL DEFAULT '',
  created_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE community_books
  ADD COLUMN IF NOT EXISTS work_id UUID REFERENCES community_book_works(id) ON DELETE SET NULL;

ALTER TABLE community_books
  ADD COLUMN IF NOT EXISTS translator TEXT NOT NULL DEFAULT '';

ALTER TABLE community_books
  ADD COLUMN IF NOT EXISTS publisher TEXT NOT NULL DEFAULT '';

ALTER TABLE community_books
  ADD COLUMN IF NOT EXISTS publication_year TEXT NOT NULL DEFAULT '';

ALTER TABLE community_books
  ADD COLUMN IF NOT EXISTS language TEXT NOT NULL DEFAULT '';

ALTER TABLE community_books
  ADD COLUMN IF NOT EXISTS edition_label TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_community_books_updated
  ON community_books(updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_community_books_title_author
  ON community_books(title, author);

CREATE TABLE IF NOT EXISTS community_readable_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id UUID NOT NULL REFERENCES community_books(id) ON DELETE CASCADE,
  rights_status TEXT NOT NULL CHECK (
    rights_status IN ('public_domain', 'original', 'authorized')
  ),
  file_url TEXT NOT NULL,
  storage_path TEXT NOT NULL DEFAULT '',
  authorization_note TEXT NOT NULL DEFAULT '',
  active BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_community_readable_assets_book
  ON community_readable_assets(book_id, active);

CREATE TABLE IF NOT EXISTS community_book_states (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id UUID NOT NULL REFERENCES community_books(id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK (status IN ('want_to_read', 'reading', 'finished')),
  visibility TEXT NOT NULL DEFAULT 'private' CHECK (
    visibility IN ('public', 'private')
  ),
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, book_id)
);

ALTER TABLE community_book_states
  ALTER COLUMN visibility SET DEFAULT 'private';

CREATE TABLE IF NOT EXISTS community_privacy_settings (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  show_reading_status BOOLEAN NOT NULL DEFAULT false,
  show_reading_progress BOOLEAN NOT NULL DEFAULT false,
  allow_follows BOOLEAN NOT NULL DEFAULT true,
  appear_in_same_book BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_community_book_states_book
  ON community_book_states(book_id, status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_community_book_states_user
  ON community_book_states(user_id, status, updated_at DESC);

CREATE TABLE IF NOT EXISTS community_follows (
  follower_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  followed_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_user_id, followed_user_id),
  CHECK (follower_user_id <> followed_user_id)
);

CREATE INDEX IF NOT EXISTS idx_community_follows_followed
  ON community_follows(followed_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS community_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id UUID NOT NULL REFERENCES community_books(id) ON DELETE CASCADE,
  post_type TEXT NOT NULL DEFAULT 'thought' CHECK (
    post_type IN ('reading_update', 'thought', 'question', 'excerpt', 'review')
  ),
  content TEXT NOT NULL,
  quoted_text TEXT NOT NULL DEFAULT '',
  chapter_label TEXT NOT NULL DEFAULT '',
  moderation_status TEXT NOT NULL DEFAULT 'published' CHECK (
    moderation_status IN ('published', 'hidden', 'removed')
  ),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE community_posts
  DROP CONSTRAINT IF EXISTS community_posts_post_type_check;

ALTER TABLE community_posts
  ADD CONSTRAINT community_posts_post_type_check CHECK (
    post_type IN ('reading_update', 'thought', 'question', 'excerpt', 'review')
  );

ALTER TABLE community_posts
  ADD COLUMN IF NOT EXISTS moderation_status TEXT NOT NULL DEFAULT 'published' CHECK (
    moderation_status IN ('published', 'hidden', 'removed')
  );

CREATE INDEX IF NOT EXISTS idx_community_posts_created
  ON community_posts(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_community_posts_book
  ON community_posts(book_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_community_posts_user
  ON community_posts(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS community_post_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  moderation_status TEXT NOT NULL DEFAULT 'published' CHECK (
    moderation_status IN ('published', 'hidden', 'removed')
  ),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE community_post_comments
  ADD COLUMN IF NOT EXISTS moderation_status TEXT NOT NULL DEFAULT 'published' CHECK (
    moderation_status IN ('published', 'hidden', 'removed')
  );

CREATE INDEX IF NOT EXISTS idx_community_post_comments_post
  ON community_post_comments(post_id, created_at ASC);

CREATE TABLE IF NOT EXISTS community_post_resonances (
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS community_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (
    event_type IN ('follow', 'post_comment', 'post_resonance')
  ),
  post_id UUID REFERENCES community_posts(id) ON DELETE CASCADE,
  book_id UUID REFERENCES community_books(id) ON DELETE CASCADE,
  preview TEXT NOT NULL DEFAULT '',
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_community_notifications_recipient
  ON community_notifications(recipient_user_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_community_notifications_unique_event
  ON community_notifications(recipient_user_id, actor_user_id, event_type, post_id)
  WHERE event_type IN ('post_resonance');

CREATE TABLE IF NOT EXISTS community_blocks (
  blocker_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_user_id, blocked_user_id),
  CHECK (blocker_user_id <> blocked_user_id)
);

CREATE INDEX IF NOT EXISTS idx_community_blocks_blocked
  ON community_blocks(blocked_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS community_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type TEXT NOT NULL CHECK (
    target_type IN ('post', 'comment', 'user')
  ),
  target_id UUID NOT NULL,
  reason TEXT NOT NULL CHECK (
    reason IN ('spam', 'harassment', 'hate', 'sexual', 'violence', 'copyright', 'privacy', 'other')
  ),
  details TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (
    status IN ('pending', 'reviewing', 'actioned', 'dismissed')
  ),
  reviewed_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  resolution_note TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(reporter_user_id, target_type, target_id)
);

CREATE INDEX IF NOT EXISTS idx_community_reports_status
  ON community_reports(status, created_at DESC);

CREATE TABLE IF NOT EXISTS community_guideline_acceptances (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  guideline_version INTEGER NOT NULL,
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, guideline_version)
);

CREATE TABLE IF NOT EXISTS community_moderation_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  action_type TEXT NOT NULL CHECK (
    action_type IN ('hide_post', 'remove_post', 'hide_comment', 'remove_comment', 'ban_user', 'unban_user')
  ),
  target_type TEXT NOT NULL CHECK (
    target_type IN ('post', 'comment', 'user')
  ),
  target_id UUID NOT NULL,
  reason TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS reading_personality_profiles (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  personality_type TEXT,
  signals_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
