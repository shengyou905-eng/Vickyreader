const { query } = require('../config/db');

async function createUser({ email, passwordHash }) {
  const result = await query(
    `INSERT INTO users (email, password_hash)
     VALUES ($1, $2)
     RETURNING id, email, role, account_status, token_version,
       ai_consent_version, created_at, updated_at`,
    [email, passwordHash],
  );

  return result.rows[0];
}

async function findUserByEmail(email) {
  const result = await query(
    `SELECT id, email, password_hash, role, account_status, ban_reason,
       token_version, ai_consent_version, ai_consent_at,
       created_at, updated_at
     FROM users
     WHERE email = $1`,
    [email],
  );

  return result.rows[0] || null;
}

async function findAuthUserById(id) {
  const result = await query(
    `SELECT id, email, role, account_status, ban_reason, token_version,
       ai_consent_version, ai_consent_at, created_at, updated_at
     FROM users
     WHERE id = $1`,
    [id],
  );
  return result.rows[0] || null;
}

async function revokeAllTokens(id) {
  const result = await query(
    `UPDATE users
     SET token_version = token_version + 1, updated_at = now()
     WHERE id = $1
     RETURNING token_version`,
    [id],
  );
  return result.rows[0] || null;
}

async function setAiConsent(id, version) {
  const result = await query(
    `UPDATE users
     SET ai_consent_version = $2,
       ai_consent_at = CASE WHEN $2 > 0 THEN now() ELSE NULL END,
       updated_at = now()
     WHERE id = $1
     RETURNING ai_consent_version, ai_consent_at`,
    [id, version],
  );
  return result.rows[0] || null;
}

async function deleteUser(id) {
  const result = await query(
    'DELETE FROM users WHERE id = $1 RETURNING id, email',
    [id],
  );
  return result.rows[0] || null;
}

async function getAccountDeletionData(id) {
  const result = await query(
    `SELECT u.id, u.email, COALESCE(up.avatar_url, '') AS avatar_url
     FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id
     WHERE u.id = $1`,
    [id],
  );
  return result.rows[0] || null;
}

module.exports = {
  createUser,
  findUserByEmail,
  findAuthUserById,
  revokeAllTokens,
  setAiConsent,
  deleteUser,
  getAccountDeletionData,
};
