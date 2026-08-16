const { query, withTransaction } = require('../config/db');

async function consumeRateLimit({ action, keyHash, windowSeconds, limit }) {
  const result = await query(
    `INSERT INTO auth_rate_limits (
       action, key_hash, window_started_at, request_count
     ) VALUES ($1, $2, now(), 1)
     ON CONFLICT (action, key_hash) DO UPDATE SET
       request_count = CASE
         WHEN auth_rate_limits.window_started_at <=
           now() - ($3::int * interval '1 second') THEN 1
         ELSE auth_rate_limits.request_count + 1
       END,
       window_started_at = CASE
         WHEN auth_rate_limits.window_started_at <=
           now() - ($3::int * interval '1 second') THEN now()
         ELSE auth_rate_limits.window_started_at
       END
     RETURNING request_count <= $4::int AS allowed`,
    [action, keyHash, windowSeconds, limit],
  );
  return result.rows[0]?.allowed === true;
}

async function createPasswordReset({ tokenHash, userId, expiresAt }) {
  return withTransaction(async (tx) => {
    await tx(
      `UPDATE password_reset_tokens
       SET used_at = COALESCE(used_at, now())
       WHERE user_id = $1 AND used_at IS NULL`,
      [userId],
    );
    await tx(
      `INSERT INTO password_reset_tokens (
         token_hash, user_id, expires_at, used_at
       ) VALUES ($1, $2, $3, NULL)`,
      [tokenHash, userId, expiresAt],
    );
  });
}

async function resetPassword({ tokenHash, passwordHash }) {
  return withTransaction(async (tx) => {
    const tokenResult = await tx(
      `SELECT token_hash, user_id
       FROM password_reset_tokens
       WHERE token_hash = $1
         AND used_at IS NULL
         AND expires_at > now()
       FOR UPDATE`,
      [tokenHash],
    );
    const token = tokenResult.rows[0];
    if (!token) return null;

    await tx(
      `UPDATE password_reset_tokens
       SET used_at = now()
       WHERE user_id = $1 AND used_at IS NULL`,
      [token.user_id],
    );
    const userResult = await tx(
      `UPDATE users
       SET password_hash = $2,
         token_version = token_version + 1,
         updated_at = now()
       WHERE id = $1
       RETURNING id, email, token_version`,
      [token.user_id, passwordHash],
    );
    return userResult.rows[0] || null;
  });
}

async function createAppleChallenge({ stateHash, expiresAt }) {
  await query(
    `INSERT INTO apple_auth_challenges (state_hash, expires_at, used_at)
     VALUES ($1, $2, NULL)`,
    [stateHash, expiresAt],
  );
}

async function consumeAppleChallenge(stateHash) {
  const result = await query(
    `UPDATE apple_auth_challenges
     SET used_at = now()
     WHERE state_hash = $1
       AND used_at IS NULL
       AND expires_at > now()
     RETURNING state_hash`,
    [stateHash],
  );
  return result.rowCount === 1;
}

async function findAppleIdentityBySub(appleSub) {
  const result = await query(
    `SELECT ai.user_id, ai.apple_sub, ai.apple_email,
       ai.refresh_token_encrypted,
       u.id, u.email, u.password_hash, u.role, u.account_status,
       u.ban_reason, u.token_version, u.created_at, u.updated_at
     FROM apple_identities ai
     JOIN users u ON u.id = ai.user_id
     WHERE ai.apple_sub = $1`,
    [appleSub],
  );
  return result.rows[0] || null;
}

async function findAppleIdentityByUserId(userId) {
  const result = await query(
    `SELECT user_id, apple_sub, apple_email, refresh_token_encrypted
     FROM apple_identities
     WHERE user_id = $1`,
    [userId],
  );
  return result.rows[0] || null;
}

async function createAppleUser({
  email,
  appleSub,
  appleEmail,
  encryptedRefreshToken,
  nickname,
}) {
  return withTransaction(async (tx) => {
    const existingEmail = await tx('SELECT id FROM users WHERE email = $1', [
      email,
    ]);
    if (existingEmail.rowCount > 0) return { conflict: 'email' };

    const existingApple = await tx(
      'SELECT user_id FROM apple_identities WHERE apple_sub = $1',
      [appleSub],
    );
    if (existingApple.rowCount > 0) return { conflict: 'apple_sub' };

    const userResult = await tx(
      `INSERT INTO users (email, password_hash)
       VALUES ($1, NULL)
       RETURNING id, email, role, account_status, token_version,
         created_at, updated_at`,
      [email],
    );
    const user = userResult.rows[0];
    await tx(
      `INSERT INTO apple_identities (
         user_id, apple_sub, apple_email, refresh_token_encrypted
       ) VALUES ($1, $2, $3, $4)`,
      [user.id, appleSub, appleEmail, encryptedRefreshToken],
    );
    if (nickname) {
      await tx(
        `INSERT INTO user_profiles (user_id, nickname)
         VALUES ($1, $2)
         ON CONFLICT (user_id) DO NOTHING`,
        [user.id, nickname],
      );
    }
    return { user };
  });
}

async function bindAppleIdentity({
  userId,
  appleSub,
  appleEmail,
  encryptedRefreshToken,
}) {
  return withTransaction(async (tx) => {
    const subResult = await tx(
      'SELECT user_id FROM apple_identities WHERE apple_sub = $1',
      [appleSub],
    );
    if (subResult.rows[0] && subResult.rows[0].user_id !== userId) {
      return { conflict: 'apple_sub' };
    }
    const userResult = await tx(
      'SELECT apple_sub FROM apple_identities WHERE user_id = $1',
      [userId],
    );
    if (userResult.rows[0] && userResult.rows[0].apple_sub !== appleSub) {
      return { conflict: 'user' };
    }

    await tx(
      `INSERT INTO apple_identities (
         user_id, apple_sub, apple_email, refresh_token_encrypted
       ) VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id) DO UPDATE SET
         apple_email = CASE
           WHEN apple_identities.apple_email = '' THEN EXCLUDED.apple_email
           ELSE apple_identities.apple_email
         END,
         refresh_token_encrypted = CASE
           WHEN EXCLUDED.refresh_token_encrypted = ''
             THEN apple_identities.refresh_token_encrypted
           ELSE EXCLUDED.refresh_token_encrypted
         END,
         updated_at = now()`,
      [userId, appleSub, appleEmail, encryptedRefreshToken],
    );
    return { linked: true };
  });
}

module.exports = {
  consumeRateLimit,
  createPasswordReset,
  resetPassword,
  createAppleChallenge,
  consumeAppleChallenge,
  findAppleIdentityBySub,
  findAppleIdentityByUserId,
  createAppleUser,
  bindAppleIdentity,
};
