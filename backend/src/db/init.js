const fs = require('fs');
const path = require('path');
const { query, closePool } = require('../config/db');

async function initSchema() {
  const schemaPath = path.join(__dirname, 'schema.sql');
  const schema = fs.readFileSync(schemaPath, 'utf8');
  await query(schema);
}

if (require.main === module) {
  initSchema()
    .then(() => {
      console.log('Database schema is ready.');
    })
    .catch((error) => {
      console.error('Failed to initialize database schema.');
      console.error(error);
      process.exitCode = 1;
    })
    .finally(() => closePool());
}

module.exports = {
  initSchema,
};
