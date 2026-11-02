-- Additive/repeatable; PostgreSQL 13+. Apply after 007. No history backfill.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
-- Phase 1 storage only. No public purchase/notification API is enabled.
CREATE TABLE IF NOT EXISTS subscription_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  environment TEXT NOT NULL CHECK (environment IN ('Sandbox', 'Production')),
  app_account_token UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, environment),
  UNIQUE (id, environment)
);

-- This is the only record retained after account deletion. A NULL account_id
-- permanently reserves the chain, without a user UUID, email or account token.
CREATE TABLE IF NOT EXISTS subscription_ownership (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider TEXT NOT NULL CHECK (provider = 'apple_app_store'),
  environment TEXT NOT NULL CHECK (environment IN ('Sandbox', 'Production')),
  original_transaction_id TEXT NOT NULL CHECK (
    original_transaction_id ~ '^[0-9]{1,128}$'
  ),
  account_id UUID,
  retired_at TIMESTAMPTZ,
  CHECK ((account_id IS NULL) = (retired_at IS NOT NULL)),
  UNIQUE (provider, environment, original_transaction_id),
  UNIQUE (id, account_id, environment),
  UNIQUE (id, environment),
  FOREIGN KEY (account_id, environment)
    REFERENCES subscription_accounts(id, environment)
);
CREATE INDEX IF NOT EXISTS idx_subscription_ownership_account
  ON subscription_ownership(account_id) WHERE account_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ownership_id UUID NOT NULL UNIQUE,
  account_id UUID NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('Sandbox', 'Production')),
  product_id TEXT NOT NULL CHECK (length(product_id) BETWEEN 1 AND 255),
  latest_transaction_id TEXT NOT NULL CHECK (latest_transaction_id ~ '^[0-9]{1,128}$'),
  status TEXT NOT NULL CHECK (status IN ('active', 'grace_period', 'billing_retry', 'expired', 'revoked')),
  purchased_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL CHECK (expires_at > purchased_at),
  grace_period_expires_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  auto_renew_status BOOLEAN NOT NULL,
  signed_at TIMESTAMPTZ NOT NULL,
  snapshot_hash TEXT NOT NULL CHECK (snapshot_hash ~ '^[a-f0-9]{64}$'),
  last_verified_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((status = 'revoked') = (revoked_at IS NOT NULL)),
  CHECK (grace_period_expires_at IS NULL OR grace_period_expires_at > expires_at),
  CHECK (status <> 'grace_period' OR grace_period_expires_at IS NOT NULL),
  UNIQUE (id, account_id, environment),
  UNIQUE (environment, latest_transaction_id),
  FOREIGN KEY (ownership_id, account_id, environment)
    REFERENCES subscription_ownership(id, account_id, environment),
  FOREIGN KEY (account_id, environment)
    REFERENCES subscription_accounts(id, environment) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_subscriptions_reconcile ON subscriptions(environment, last_verified_at);
CREATE INDEX IF NOT EXISTS idx_subscriptions_account ON subscriptions(account_id, environment);

-- Business code reads entitlement, never individual Apple product IDs.
CREATE TABLE IF NOT EXISTS entitlement_grants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('Sandbox', 'Production')),
  entitlement TEXT NOT NULL CHECK (entitlement = 'pro'),
  source TEXT NOT NULL CHECK (source = 'apple_app_store'),
  subscription_id UUID NOT NULL UNIQUE,
  enabled BOOLEAN NOT NULL,
  valid_from TIMESTAMPTZ NOT NULL,
  valid_until TIMESTAMPTZ NOT NULL CHECK (valid_until > valid_from),
  revoked_at TIMESTAMPTZ,
  verified_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  FOREIGN KEY (subscription_id, account_id, environment)
    REFERENCES subscriptions(id, account_id, environment) ON DELETE CASCADE,
  FOREIGN KEY (account_id, environment)
    REFERENCES subscription_accounts(id, environment) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_entitlement_grants_effective
  ON entitlement_grants(account_id, environment, entitlement, valid_until)
  WHERE enabled AND revoked_at IS NULL;

-- Whitelisted metadata only: no raw JWS, receipt, token, email, user content
-- or unbounded error/payload columns. A failed attempt commits its audit only.
CREATE TABLE IF NOT EXISTS subscription_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  environment TEXT NOT NULL CHECK (environment IN ('Sandbox', 'Production')),
  event_kind TEXT NOT NULL CHECK (event_kind IN ('verification', 'notification')),
  request_hash TEXT NOT NULL CHECK (request_hash ~ '^[a-f0-9]{64}$'),
  notification_uuid UUID,
  notification_type TEXT CHECK (notification_type ~ '^[A-Z_]{1,80}$'),
  subtype TEXT CHECK (subtype ~ '^[A-Z_]{1,80}$'),
  ownership_id UUID,
  account_id UUID,
  result TEXT NOT NULL CHECK (result IN (
    'applied', 'replay', 'stale', 'version_conflict', 'ownership_conflict',
    'account_token_mismatch', 'account_deleted', 'awaiting_binding'
  )),
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ,
  CHECK ((event_kind = 'notification') = (notification_uuid IS NOT NULL)),
  UNIQUE (environment, notification_uuid),
  FOREIGN KEY (ownership_id, environment)
    REFERENCES subscription_ownership(id, environment),
  FOREIGN KEY (account_id, environment)
    REFERENCES subscription_accounts(id, environment) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_subscription_events_owner ON subscription_events(ownership_id);
CREATE INDEX IF NOT EXISTS idx_subscription_events_account ON subscription_events(account_id);
CREATE INDEX IF NOT EXISTS idx_subscription_events_pending
  ON subscription_events(environment, received_at) WHERE processed_at IS NULL;

CREATE OR REPLACE FUNCTION protect_subscription_account() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'subscription account identity is immutable' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS subscription_account_immutable ON subscription_accounts;
CREATE TRIGGER subscription_account_immutable BEFORE UPDATE ON subscription_accounts
  FOR EACH ROW EXECUTE FUNCTION protect_subscription_account();

CREATE OR REPLACE FUNCTION protect_subscription_ownership() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'subscription ownership reservations cannot be deleted' USING ERRCODE = '23514';
  END IF;
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.provider IS DISTINCT FROM OLD.provider
     OR NEW.environment IS DISTINCT FROM OLD.environment
     OR NEW.original_transaction_id IS DISTINCT FROM OLD.original_transaction_id
     OR (NEW.account_id IS DISTINCT FROM OLD.account_id AND NOT (
       OLD.account_id IS NOT NULL AND NEW.account_id IS NULL AND NEW.retired_at IS NOT NULL
     ))
     OR (OLD.retired_at IS NOT NULL AND NEW.retired_at IS DISTINCT FROM OLD.retired_at)
     OR (NEW.account_id IS NOT NULL AND NEW.retired_at IS NOT NULL) THEN
    RAISE EXCEPTION 'subscription ownership is immutable; transfer is forbidden' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS subscription_ownership_immutable ON subscription_ownership;
CREATE TRIGGER subscription_ownership_immutable BEFORE UPDATE OR DELETE ON subscription_ownership
  FOR EACH ROW EXECUTE FUNCTION protect_subscription_ownership();

-- FK cascade from users invokes this even for existing DELETE FROM users code.
-- Details and audits are erased before retiring the immutable chain reservation.
CREATE OR REPLACE FUNCTION erase_subscription_account() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM subscription_events WHERE account_id = OLD.id OR ownership_id IN (
    SELECT id FROM subscription_ownership WHERE account_id = OLD.id
  );
  DELETE FROM subscriptions WHERE account_id = OLD.id;
  UPDATE subscription_ownership SET account_id = NULL, retired_at = now()
    WHERE account_id = OLD.id;
  RETURN OLD;
END;
$$;
DROP TRIGGER IF EXISTS subscription_account_erasure ON subscription_accounts;
CREATE TRIGGER subscription_account_erasure BEFORE DELETE ON subscription_accounts
  FOR EACH ROW EXECUTE FUNCTION erase_subscription_account();
COMMIT;
