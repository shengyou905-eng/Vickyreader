const { recapError } = require('./bookRecapApiContract');

// Pass AI_CONSENT_VERSION from the existing auth controller at composition time.
// No dotenv/default connection pool is loaded by this internal module.
function createBookRecapAuthorization(requiredConsentVersion) {
  if (!Number.isSafeInteger(requiredConsentVersion) || requiredConsentVersion < 1) throw Error('Consent version required');
  return async function authorize(tx, userId, principal) {
    if (principal?.expiresAt !== undefined && principal.expiresAt * 1000 <= Date.now()) {
      throw recapError(401, 'RECAP_AUTH_REQUIRED');
    }
    const row = (await tx(`SELECT account_status,token_version,ai_consent_version
      FROM users WHERE id=$1`, [userId])).rows[0];
    if (!row || principal?.userId !== userId || row.account_status !== 'active' ||
        Number(row.token_version) !== principal.tokenVersion ||
        !Number.isSafeInteger(principal.tokenVersion)) throw recapError(401, 'RECAP_AUTH_REQUIRED');
    if (Number(row.ai_consent_version) < requiredConsentVersion) throw recapError(428, 'AI_CONSENT_REQUIRED');
  };
}
module.exports = { createBookRecapAuthorization };
