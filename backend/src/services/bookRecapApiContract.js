const { z } = require('zod');
const uuid = z.uuid().transform(s => s.toLowerCase());
const revision = z.string().regex(/^[1-9][0-9]{0,18}$/u)
  .refine(s => BigInt(s) <= 9223372036854775807n);
const digest = z.string().regex(/^[a-f0-9]{64}$/u);
const source = z.strictObject({
  entry_id: uuid.optional(),
  client_entry_id: z.string().min(1).max(256).optional(),
  expected_digest: digest.optional(),
  follow_up_ids: z.array(uuid).max(320).refine(v => new Set(v).size === v.length).optional(),
}).refine(s => Boolean(s.entry_id) !== Boolean(s.client_entry_id));
const prepare = z.strictObject({
  recap_id: uuid, request_id: uuid,
  book_id: z.string().min(1).max(200).refine(s => s.trim() === s),
  selected_sources: z.array(source).min(1).max(80).refine(rows =>
    new Set(rows.map(s => s.entry_id ? 'r:' + s.entry_id : 'c:' + s.client_entry_id)).size === rows.length)
    .refine(rows => Buffer.byteLength(JSON.stringify(rows), 'utf8') <= 65536),
});
const save = z.strictObject({ request_id: uuid, expected_revision: revision });
const generate = save.extend({ source_fingerprint: digest, consent_scope_fingerprint: digest });
const followUp = save.extend({
  item_id: z.string().min(1).max(256).optional(),
  question: z.string().trim().min(1).max(4000),
});
const feedback = save.extend({
  item_id: z.string().min(1).max(256).optional(),
  category: z.enum(['inaccurate', 'low_value', 'wrong_relation']),
  comment: z.string().max(1000).default(''),
});
function recapError(statusCode, code) {
  return Object.assign(new Error(code), { statusCode, error_code: code });
}
module.exports = { uuid, revision, prepare, save, generate, followUp, feedback, recapError };
