const BUNDLE_ID = 'com.youxugarden.zhireader';
const SUBSCRIPTION_GROUP = 'Zhidu Pro';
// Product IDs are the explicitly selected ASC identifiers, not the Bundle ID.
const PRODUCTS = Object.freeze({
  'com.youxugarden.zhreader.pro.monthly': Object.freeze({ entitlement: 'pro', period: 'month' }),
  'com.youxugarden.zhreader.pro.yearly': Object.freeze({ entitlement: 'pro', period: 'year' }),
});
const ENVIRONMENTS = Object.freeze(['Sandbox', 'Production']);

function requireEnvironment(environment) {
  if (!ENVIRONMENTS.includes(environment)) throw new TypeError('Explicit Apple environment required');
  return environment;
}

module.exports = { BUNDLE_ID, SUBSCRIPTION_GROUP, PRODUCTS, ENVIRONMENTS, requireEnvironment };
