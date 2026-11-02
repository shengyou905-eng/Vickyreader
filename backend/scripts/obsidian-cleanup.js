// Explicit maintenance command; never deletes business data or the ledger.
const { cleanupExpired } = require('../src/repositories/obsidianSync.repository');
const { closePool } = require('../src/config/db');
cleanupExpired()
  .then(() => console.log('Expired Obsidian export snapshots and codes removed.'))
  .catch(() => { console.error('Obsidian cleanup failed.'); process.exitCode = 1; })
  .finally(closePool);
