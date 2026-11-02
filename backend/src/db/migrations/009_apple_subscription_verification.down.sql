BEGIN;
SET LOCAL lock_timeout = '5s';
-- Never discard verification fences or retry/audit history after activation.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM subscriptions) OR EXISTS (SELECT 1 FROM subscription_events) THEN
    RAISE EXCEPTION '009 rollback refused: subscription verification data exists';
  END IF;
END $$;
DROP INDEX IF EXISTS idx_subscription_events_chain;
ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS subscription_component_versions;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS transaction_signed_at;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS renewal_signed_at;
ALTER TABLE subscription_events DROP COLUMN IF EXISTS original_transaction_id;
ALTER TABLE subscription_events DROP COLUMN IF EXISTS signed_at;
ALTER TABLE subscription_events DROP COLUMN IF EXISTS transaction_id;
ALTER TABLE subscription_events DROP COLUMN IF EXISTS transaction_purchased_at;
ALTER TABLE subscription_events DROP COLUMN IF EXISTS transaction_signed_at;
ALTER TABLE subscription_events DROP COLUMN IF EXISTS renewal_signed_at;
ALTER TABLE subscription_events DROP COLUMN IF EXISTS attempts;
ALTER TABLE subscription_events DROP COLUMN IF EXISTS last_error_code;
ALTER TABLE subscription_events DROP CONSTRAINT subscription_events_event_kind_check;
ALTER TABLE subscription_events ADD CONSTRAINT subscription_events_event_kind_check
  CHECK (event_kind IN ('verification', 'notification'));
ALTER TABLE subscription_events DROP CONSTRAINT subscription_events_result_check;
ALTER TABLE subscription_events ADD CONSTRAINT subscription_events_result_check CHECK (result IN (
  'applied', 'replay', 'stale', 'version_conflict', 'ownership_conflict',
  'account_token_mismatch', 'account_deleted', 'awaiting_binding'
));
CREATE OR REPLACE FUNCTION erase_subscription_account() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM subscription_events WHERE account_id = OLD.id OR ownership_id IN (
    SELECT id FROM subscription_ownership WHERE account_id = OLD.id
  );
  DELETE FROM subscriptions WHERE account_id = OLD.id;
  UPDATE subscription_ownership SET account_id = NULL, retired_at = now() WHERE account_id = OLD.id;
  RETURN OLD;
END;
$$;
COMMIT;
