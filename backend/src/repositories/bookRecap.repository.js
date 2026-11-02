const { lockUploadUser } = require('./uploadState.repository');
const { recapError: error } = require('../services/bookRecapApiContract');
const { clearDerived } = require('./bookRecapInvalidation.repository');
const { lockRecapSources } = require('./bookRecapSource.repository');

// Injection avoids loading deployment configuration or opening a default pool.
function createBookRecapRepository(db) {
  async function transaction(userId, action) {
    return db.withTransaction(async tx => {
      const user = await tx('SELECT id FROM users WHERE id=$1 FOR KEY SHARE', [userId]);
      if (!user.rowCount) throw error(401, 'RECAP_ACCOUNT_UNAVAILABLE');
      await lockUploadUser(tx, userId);
      return action(tx);
    });
  }
  async function find(tx, userId, id) {
    await lockRecapSources(tx, userId, id);
    const r = await tx('SELECT * FROM reading_recaps WHERE id=$1 AND user_id=$2 FOR UPDATE', [id, userId]);
    if (!r.rowCount) throw error(404, 'RECAP_NOT_FOUND');
    return r.rows[0];
  }
  function readable(row, now) {
    if (['deleted', 'invalidated', 'expired'].includes(row.state)) throw error(410, 'RECAP_UNAVAILABLE');
    if (!row.is_saved && row.expires_at && row.expires_at <= now) throw error(410, 'RECAP_EXPIRED');
    if (row.state !== 'ready') throw error(409, 'RECAP_NOT_READY');
  }
  async function replay(tx, userId, requestId, operation, id, mac) {
    const r = await tx('SELECT * FROM reading_recap_operations WHERE user_id=$1 AND request_id=$2',
      [userId, requestId]);
    if (!r.rowCount) return null;
    const op = r.rows[0];
    if (['revoked', 'expired', 'interrupted'].includes(op.status)) throw error(410, 'RECAP_REQUEST_RETIRED');
    if (op.operation !== operation || op.recap_id !== id || op.request_mac !== mac) {
      throw error(409, 'RECAP_REQUEST_CONFLICT');
    }
    return op;
  }
  async function record(tx, { userId, requestId, id, operation, mac, keyVersion, revision, deadline, status }) {
    const r = await tx(`INSERT INTO reading_recap_operations
      (user_id,request_id,recap_id,operation,request_mac,mac_key_version,expected_revision,status,
       deadline_at,finished_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,CASE WHEN $8='running' THEN NULL ELSE now() END)
      RETURNING *`, [userId, requestId, id, operation, mac, keyVersion, revision, status, deadline]);
    return r.rows[0];
  }
  async function insertPrepared(tx, userId, id, material, expiresAt) {
    const r = await tx(`INSERT INTO reading_recaps
      (id,user_id,book_id,state,source_fingerprint,selected_sources_json,coverage_json,prompt_version,expires_at)
      VALUES ($1,$2,$3,'prepared',$4,$5,$6,$7,$8) ON CONFLICT (id) DO NOTHING RETURNING *`,
    [id, userId, material.bookId, material.fingerprint, JSON.stringify(material.selection),
      material.coverage, material.promptVersion, expiresAt]);
    if (!r.rowCount) {
      const previous = await find(tx, userId, id);
      if (['deleted', 'invalidated'].includes(previous.state)) throw error(410, 'RECAP_UNAVAILABLE');
      throw error(409, 'RECAP_ID_EXISTS');
    }
    for (const e of material.dependencies) {
      await tx(`INSERT INTO reading_recap_sources
        (recap_id,user_id,book_id,evidence_id,entry_id,follow_up_id,client_entry_id,
         source_field,source_kind,provenance,source_digest,follow_up_set_digest,
         observed_revision,observed_writer_id,locator_json)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)`,
      [id, userId, material.bookId, e.evidenceId, e.entryId, e.followUpId ?? null,
        e.clientEntryId ?? null, e.sourceField, e.kind, e.provenance, e.digest,
        e.followUpSetDigest, e.revision ?? null, e.writerId ?? null, e.locator ?? {}]);
    }
    return r.rows[0];
  }
  async function dependencies(tx, userId, id) {
    return (await tx('SELECT * FROM reading_recap_sources WHERE recap_id=$1 AND user_id=$2 ORDER BY evidence_id',
      [id, userId])).rows;
  }
  async function setGenerating(tx, userId, id) {
    return (await tx(`UPDATE reading_recaps SET state='generating',revision=revision+1,updated_at=now()
      WHERE id=$1 AND user_id=$2 RETURNING *`, [id, userId])).rows[0];
  }
  async function setReady(tx, userId, id, result, expiry) {
    return (await tx(`UPDATE reading_recaps SET state='ready',result_json=$3,expires_at=$4,
      revision=revision+1,updated_at=now() WHERE id=$1 AND user_id=$2 RETURNING *`,
    [id, userId, result, expiry])).rows[0];
  }
  async function finishOperation(tx, userId, requestId, status, resultId = null) {
    await tx(`UPDATE reading_recap_operations SET status=$3,result_id=$4,finished_at=now()
      WHERE user_id=$1 AND request_id=$2`, [userId, requestId, status, resultId]);
  }
  async function operation(tx, userId, requestId) {
    return (await tx('SELECT * FROM reading_recap_operations WHERE user_id=$1 AND request_id=$2 FOR UPDATE',
      [userId, requestId])).rows[0] || null;
  }
  async function metrics(tx, userId, id, m) {
    await tx(`UPDATE reading_recaps SET requested_model=$3,returned_model=$4,input_tokens=$5,
      output_tokens=$6,elapsed_ms=$7,cost_amount=$8,cost_currency=$9,pricing_version=$10
      WHERE id=$1 AND user_id=$2`, [id, userId, m.requestedModel, m.returnedModel,
      m.inputTokens, m.outputTokens, m.elapsedMs, m.costAmount, m.costCurrency, m.pricingVersion]);
  }
  async function save(tx, userId, id) {
    return (await tx(`UPDATE reading_recaps SET is_saved=true,expires_at=NULL,revision=revision+1,
      updated_at=now() WHERE id=$1 AND user_id=$2 RETURNING *`, [id, userId])).rows[0];
  }
  async function createConversation(tx, userId, id, bookId) {
    return (await tx(`INSERT INTO xiaou_conversations(user_id,kind,recap_id,book_id)
      VALUES ($1,'book_recap',$2,$3) ON CONFLICT (recap_id) WHERE recap_id IS NOT NULL
      DO UPDATE SET recap_id=EXCLUDED.recap_id RETURNING id`, [userId, id, bookId])).rows[0].id;
  }
  async function feedback(tx, userId, id, requestId, value) {
    return (await tx(`INSERT INTO reading_recap_feedback(user_id,recap_id,client_request_id,item_id,category,comment)
      VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`,
    [userId, id, requestId, value.item_id ?? null, value.category, value.comment])).rows[0].id;
  }
  async function followUpHistory(tx, userId, row) {
    const conversations = await tx(`SELECT * FROM xiaou_conversations
      WHERE recap_id=$1 FOR UPDATE`, [row.id]);
    const conversation = conversations.rows[0];
    if (conversations.rowCount !== 1 || conversation.user_id !== userId ||
        conversation.kind !== 'book_recap' || conversation.book_id !== row.book_id) {
      throw error(409, 'RECAP_HISTORY_INVALID');
    }
    const size = (await tx(`SELECT count(*)::int n,COALESCE(sum(octet_length(content)),0)::int bytes
      FROM xiaou_messages WHERE conversation_id=$1`, [conversation.id])).rows[0];
    if (size.n > 128 || size.bytes > 524288) throw error(422, 'RECAP_HISTORY_BUDGET');
    const messages = (await tx(`SELECT id,user_id,role,status,content FROM xiaou_messages
      WHERE conversation_id=$1 ORDER BY id`, [conversation.id])).rows;
    const operations = (await tx(`SELECT request_id,generation_id,result_id,request_mac,expected_revision
      FROM reading_recap_operations WHERE user_id=$1 AND recap_id=$2
      AND operation='follow_up' AND status='succeeded' ORDER BY request_id LIMIT 65`, [userId, row.id])).rows;
    return { conversationId: conversation.id, messages, operations };
  }
  async function appendFollowUpPair(tx, userId, id, conversationId, question, answer) {
    await tx(`INSERT INTO xiaou_messages(conversation_id,user_id,role,content,status)
      VALUES ($1,$2,'user',$3,'completed')`, [conversationId, userId, JSON.stringify(question)]);
    const inserted = await tx(`INSERT INTO xiaou_messages(conversation_id,user_id,role,content,status)
      VALUES ($1,$2,'assistant',$3,'completed') RETURNING id`, [conversationId, userId, JSON.stringify(answer)]);
    await tx('UPDATE xiaou_conversations SET updated_at=now() WHERE id=$1 AND user_id=$2', [conversationId, userId]);
    await tx(`UPDATE reading_recaps SET revision=revision+1,updated_at=now()
      WHERE id=$1 AND user_id=$2`, [id, userId]);
    return inserted.rows[0].id;
  }
  async function remove(tx, userId, id) {
    await lockRecapSources(tx, userId, id);
    // Deleting before a late prepare creates an ID fence without any book data.
    await tx(`INSERT INTO reading_recaps(id,user_id,state,deleted_at)
      VALUES ($1,$2,'deleted',now()) ON CONFLICT (id) DO NOTHING`, [id, userId]);
    await find(tx, userId, id);
    await clearDerived(tx, userId, [id], 'deleted');
  }
  return { transaction, find, readable, replay, record, insertPrepared, dependencies,
    setGenerating, setReady, finishOperation, operation, metrics, save, createConversation, feedback, remove,
    followUpHistory, appendFollowUpPair };
}
module.exports = { createBookRecapRepository };
