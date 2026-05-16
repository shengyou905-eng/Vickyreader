const { Pool } = require('pg');
const { databaseUrl } = require('./env');

const pool = new Pool({
  connectionString: databaseUrl,
});

async function query(text, params) {
  return pool.query(text, params);
}

async function closePool() {
  await pool.end();
}

module.exports = {
  pool,
  query,
  closePool,
};
