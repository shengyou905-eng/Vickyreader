const repository = require('../repositories/subscription.repository');

async function getEntitlements(userId, environment) {
  // Do not catch database/network errors and reinterpret them as FREE.
  const grants = await repository.findEffectiveGrants(userId, environment);
  const pro = grants.find((grant) => grant.entitlement === 'pro');
  return {
    environment,
    tier: pro ? 'PRO' : 'FREE',
    pro: pro ? {
      active: true,
      source: pro.source,
      productId: pro.product_id,
      expiresAt: pro.valid_until.toISOString(),
      autoRenew: pro.auto_renew_status,
      verifiedAt: pro.verified_at.toISOString(),
    } : { active: false },
  };
}

module.exports = { getEntitlements };
