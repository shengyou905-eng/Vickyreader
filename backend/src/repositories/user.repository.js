const { query } = require('../config/db');

async function createUser({ email, passwordHash }) {
  const result = await query(
    `INSERT INTO users (email, password_hash)
     VALUES ($1, $2)
     RETURNING id, email, created_at, updated_at`,
    [email, passwordHash],
  );

  return result.rows[0];
}

async function findUserByEmail(email) {
  const result = await query(
    `SELECT id, email, password_hash, created_at, updated_at
     FROM users
     WHERE email = $1`,
    [email],
  );

  return result.rows[0] || null;
}

module.exports = {
  createUser,
  findUserByEmail,
};
