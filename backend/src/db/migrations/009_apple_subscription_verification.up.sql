-- Apply after 008. Additive, repeatable; no business data backfill.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS transaction_signed_at TIMESTAMPTZ;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS renewal_signed_at TIMESTAMPTZ;
ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS subscription_component_versions;
ALTER TABLE subscriptions ADD CONSTRAINT subscription_component_versions CHECK (
  (transaction_signed_at IS NULL) = (renewal_signed_at IS NULL)
);
ALTER TABLE subscription_events ADD COLUMN IF NOT EXISTS original_transaction_id TEXT
  CHECK (original_transaction_id ~ '^[0-9]{1,128}$');
ALTER TABLE subscription_events ADD COLUMN IF NOT EXISTS signed_at TIMESTAMPTZ;
ALTER TABLE subscription_events ADD COLUMN IF NOT EXISTS transaction_id TEXT
  CHECK (transaction_id ~ '^[0-9]{1,128}$');
ALTER TABLE subscription_events ADD COLUMN IF NOT EXISTS transaction_purchased_at TIMESTAMPTZ;
ALTER TABLE subscription_events ADD COLUMN IF NOT EXISTS transaction_signed_at TIMESTAMPTZ;
ALTER TABLE subscription_events ADD COLUMN IF NOT EXISTS renewal_signed_at TIMESTAMPTZ;
ALTER TABLE subscription_events ADD COLUMN IF NOT EXISTS attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0);
ALTER TABLE subscription_events ADD COLUMN IF NOT EXISTS last_error_code TEXT
  CHECK (last_error_code ~ '^[A-Z_]{1,80}$');
ALTER TABLE subscription_events DROP CONSTRAINT IF EXISTS subscription_events_event_kind_check;
ALTER TABLE subscription_events ADD CONSTRAINT subscription_events_event_kind_check
  CHECK (event_kind IN ('verification', 'notification', 'reconciliation'));
ALTER TABLE subscription_events DROP CONSTRAINT IF EXISTS subscription_events_result_check;
ALTER TABLE subscription_events ADD CONSTRAINT subscription_events_result_check CHECK (result IN (
  'applied', 'replay', 'stale', 'version_conflict', 'ownership_conflict',
  'account_token_mismatch', 'account_deleted', 'awaiting_binding', 'retry_pending', 'ignored', 'test'
));
CREATE INDEX IF NOT EXISTS idx_subscription_events_chain
  ON subscription_events(environment, original_transaction_id) WHERE processed_at IS NULL;

-- Also erase orphan audits recorded before this account claimed its chain.
CREATE OR REPLACE FUNCTION erase_subscription_account() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  -- Same user -> chain lock order as verification and notification registration.
  PERFORM pg_advisory_xact_lock(hashtextextended(environment || ':' || original_transaction_id,0))
    FROM subscription_ownership WHERE account_id = OLD.id ORDER BY original_transaction_id;
  DELETE FROM subscription_events WHERE account_id = OLD.id OR ownership_id IN (
    SELECT id FROM subscription_ownership WHERE account_id = OLD.id
  ) OR (environment, original_transaction_id) IN (
    SELECT environment, original_transaction_id FROM subscription_ownership WHERE account_id = OLD.id
  );
  DELETE FROM subscriptions WHERE account_id = OLD.id;
  UPDATE subscription_ownership SET account_id = NULL, retired_at = now() WHERE account_id = OLD.id;
  RETURN OLD;
END;
$$;
COMMIT;
