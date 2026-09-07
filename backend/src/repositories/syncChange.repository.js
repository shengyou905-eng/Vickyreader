const entityTypes = new Set(['trace', 'reading_progress', 'book']);
const operations = new Set(['created', 'updated', 'deleted']);

async function appendSyncChange(txQuery, {
  userId,
  entityType,
  entityId,
  operation,
}) {
  if (typeof txQuery !== 'function') {
    throw new TypeError('A transaction query function is required');
  }
  if (!userId || !entityId) {
    throw new TypeError('userId and entityId are required');
  }
  if (!entityTypes.has(entityType)) {
    throw new TypeError(`Unsupported sync entity type: ${entityType}`);
  }
  if (!operations.has(operation)) {
    throw new TypeError(`Unsupported sync operation: ${operation}`);
  }

  const result = await txQuery(
    `WITH next_cursor AS (
       INSERT INTO sync_user_cursors (user_id, last_sequence)
       VALUES ($1, 1)
       ON CONFLICT (user_id) DO UPDATE
       SET last_sequence = sync_user_cursors.last_sequence + 1
       RETURNING last_sequence
     )
     INSERT INTO sync_changes (
       user_id, user_sequence, entity_type, entity_id, operation
     )
     SELECT $1, last_sequence, $2, $3, $4
     FROM next_cursor
     RETURNING sequence, user_sequence, changed_at`,
    [userId, entityType, String(entityId), operation],
  );

  return result.rows[0];
}

module.exports = {
  appendSyncChange,
  entityTypes,
  operations,
};
