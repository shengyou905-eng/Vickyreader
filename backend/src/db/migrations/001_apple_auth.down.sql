-- Sign in with Apple — rollback migration.
--
-- Apply with:
--   psql "$DATABASE_URL" -f backend/src/db/migrations/001_apple_auth.down.sql
--
-- WARNING: The final `SET NOT NULL` below only succeeds if there are no
-- Apple-only accounts remaining (i.e. no rows in `users` with a NULL
-- password_hash). Delete or convert Apple-only accounts before rolling back,
-- otherwise this statement will fail and the schema stays partially migrated.

DROP TABLE IF EXISTS apple_identities;
DROP TABLE IF EXISTS apple_auth_challenges;
DROP TABLE IF EXISTS auth_rate_limits;

ALTER TABLE users
  ALTER COLUMN password_hash SET NOT NULL;
