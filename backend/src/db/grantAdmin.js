const { query, closePool } = require('../config/db');

async function main() {
  const email = String(process.argv[2] || '').trim().toLowerCase();
  if (!email || !email.includes('@')) {
    throw new Error('Usage: npm run admin:grant -- user@example.com');
  }
  const result = await query(
    `UPDATE users SET role = 'admin', updated_at = now()
     WHERE email = $1 RETURNING id, email, role`,
    [email],
  );
  if (!result.rows[0]) throw new Error('User not found');
  console.log(`Admin granted: ${result.rows[0].email}`);
}

main()
  .catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  })
  .finally(() => closePool());
