-- Additive, repeatable migration. Apply after 001-006, before enabling routes.
-- No historical ledger backfill and no changes to reading business tables.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
CREATE TABLE IF NOT EXISTS obsidian_authorization_codes (
  code_hash TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_version INTEGER NOT NULL,
  client_id TEXT NOT NULL CHECK (client_id = 'zhidu-sync'),
  redirect_uri TEXT NOT NULL,
  code_challenge TEXT NOT NULL,
  scope TEXT NOT NULL CHECK (scope = 'obsidian.sync.read'),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_obsidian_codes_expiry ON obsidian_authorization_codes(expires_at);

CREATE TABLE IF NOT EXISTS obsidian_grants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  scope TEXT NOT NULL CHECK (scope = 'obsidian.sync.read'),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_obsidian_grants_user ON obsidian_grants(user_id);

-- Short-lived export cache, not a second ledger. Only whitelisted DTOs enter it.
CREATE TABLE IF NOT EXISTS obsidian_sync_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grant_id UUID NOT NULL REFERENCES obsidian_grants(id) ON DELETE CASCADE,
  phase TEXT NOT NULL CHECK (phase IN ('snapshot', 'incremental')),
  after_sequence BIGINT CHECK (after_sequence >= 0),
  watermark BIGINT NOT NULL CHECK (watermark >= 0),
  completed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '30 minutes',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_obsidian_snapshots_grant ON obsidian_sync_snapshots(grant_id);
CREATE INDEX IF NOT EXISTS idx_obsidian_snapshots_expiry ON obsidian_sync_snapshots(expires_at);

CREATE TABLE IF NOT EXISTS obsidian_sync_snapshot_items (
  snapshot_id UUID NOT NULL REFERENCES obsidian_sync_snapshots(id) ON DELETE CASCADE,
  ordinal BIGINT NOT NULL,
  change JSONB NOT NULL,
  PRIMARY KEY (snapshot_id, ordinal)
);
COMMIT;
