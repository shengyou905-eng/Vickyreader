-- Only an UNUSED installation can be rolled back. Never erase ownership
-- reservations to roll back application code: old binaries ignore these tables.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
LOCK TABLE subscription_accounts, subscription_ownership, subscriptions,
  entitlement_grants, subscription_events IN ACCESS EXCLUSIVE MODE;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM subscription_accounts)
     OR EXISTS (SELECT 1 FROM subscription_ownership)
     OR EXISTS (SELECT 1 FROM subscriptions)
     OR EXISTS (SELECT 1 FROM entitlement_grants)
     OR EXISTS (SELECT 1 FROM subscription_events) THEN
    RAISE EXCEPTION '008 rollback refused: preserve subscription data and ownership reservations';
  END IF;
END;
$$;
DROP TABLE subscription_events;
DROP TABLE entitlement_grants;
DROP TABLE subscriptions;
DROP TABLE subscription_ownership;
DROP TABLE subscription_accounts;
DROP FUNCTION erase_subscription_account();
DROP FUNCTION protect_subscription_ownership();
DROP FUNCTION protect_subscription_account();
COMMIT;
