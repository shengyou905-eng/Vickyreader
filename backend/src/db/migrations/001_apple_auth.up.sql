-- Sign in with Apple — schema migration (idempotent).
--
-- Apply with:
--   psql "$DATABASE_URL" -f backend/src/db/migrations/001_apple_auth.up.sql
--
-- All statements are idempotent: safe to re-run without side effects.

-- 1. Allow Apple-only accounts (no local password).
--    Existing email/password rows keep their password_hash untouched.
ALTER TABLE users
  ALTER COLUMN password_hash DROP NOT NULL;

-- 2. Sliding-window rate-limit counter (shared by auth endpoints).
CREATE TABLE IF NOT EXISTS auth_rate_limits (
  action TEXT NOT NULL,
  key_hash TEXT NOT NULL,
  window_started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  request_count INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (action, key_hash)
);

-- 3. One-time Sign in with Apple login challenges (CSRF/state protection).
CREATE TABLE IF NOT EXISTS apple_auth_challenges (
  state_hash TEXT PRIMARY KEY,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ
);

-- 4. Apple identity <-> user mapping.
CREATE TABLE IF NOT EXISTS apple_identities (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  apple_sub TEXT NOT NULL UNIQUE,
  apple_email TEXT NOT NULL DEFAULT '',
  refresh_token_encrypted TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_apple_identities_sub
  ON apple_identities(apple_sub);
