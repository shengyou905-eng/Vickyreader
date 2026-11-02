const { query, withTransaction } = require('../config/db');
const httpError = require('../utils/httpError');
const { digest, challenge, SCOPE, CODE_TTL_SECONDS, TOKEN_TTL_SECONDS } = require('../services/obsidianProtocol.service');

async function createCode(userId, sessionVersion, code, input) {
  await query(`INSERT INTO obsidian_authorization_codes
    (code_hash, user_id, session_version, client_id, redirect_uri, code_challenge, scope, expires_at)
    VALUES ($1,$2,$3,$4,$5,$6,$7,now() + $8 * interval '1 second')`,
  [digest(code), userId, sessionVersion, input.client_id, input.redirect_uri,
    input.code_challenge, SCOPE, CODE_TTL_SECONDS]);
}

async function exchangeCode(input, rawToken) {
  return withTransaction(async tx => {
    // Consumption and token issuance commit together; only one exchange wins.
    const result = await tx(`UPDATE obsidian_authorization_codes c SET used_at=now()
      FROM users u WHERE c.code_hash=$1 AND c.user_id=u.id
        AND c.used_at IS NULL AND c.expires_at>now()
        AND c.client_id=$2 AND c.redirect_uri=$3 AND c.code_challenge=$4
        AND u.account_status='active' AND u.token_version=c.session_version
      RETURNING c.user_id`, [digest(input.code), input.client_id, input.redirect_uri, challenge(input.code_verifier)]);
    if (!result.rowCount) throw httpError(400, 'invalid_grant');
    const grant = await tx(`INSERT INTO obsidian_grants (user_id, token_hash, scope, expires_at)
      VALUES ($1,$2,$3,now() + $4 * interval '1 second') RETURNING id, expires_at`,
    [result.rows[0].user_id, digest(rawToken), SCOPE, TOKEN_TTL_SECONDS]);
    return grant.rows[0];
  });
}

async function authenticate(rawToken) {
  const result = await query(`SELECT g.id, g.user_id, g.scope, g.expires_at
    FROM obsidian_grants g JOIN users u ON u.id=g.user_id
    WHERE g.token_hash=$1 AND g.scope=$2 AND g.revoked_at IS NULL
      AND g.expires_at>now() AND u.account_status='active'`, [digest(rawToken), SCOPE]);
  return result.rows[0] || null;
}

async function revoke(rawToken) {
  await withTransaction(async tx => {
    const grant = await tx(`UPDATE obsidian_grants SET revoked_at=COALESCE(revoked_at, now())
      WHERE token_hash=$1 RETURNING id`, [digest(rawToken)]);
    if (grant.rowCount) await tx('DELETE FROM obsidian_sync_snapshots WHERE grant_id=$1', [grant.rows[0].id]);
  });
}

module.exports = { createCode, exchangeCode, authenticate, revoke };
