const { z } = require('zod');
const api = require('./bookRecapApiContract');
const legacy = require('./bookRecapHttpContract');

const hash = z.string().regex(/^[a-f0-9]{64}$/u);
const evidenceId = z.string().regex(/^e-[a-f0-9]{64}$/u);
const unique = values => new Set(values).size === values.length;
const empty = z.strictObject({});
const historyRequest = z.strictObject({
  limit: z.number().int().min(1).max(50).default(20),
  filter: z.enum(['all', 'saved', 'preview']).default('all'),
  cursor: z.string().min(1).max(2048).optional(),
});
const versionRequest = z.strictObject({ book_id: z.string().min(1).max(256),
  expected_revision: api.revision, expected_source_fingerprint: hash });
const evidenceRequest = versionRequest.extend({ evidence_ids: z.array(evidenceId).min(1).max(24).refine(unique) });
const policy = z.strictObject({ version: z.string().regex(/^[a-zA-Z0-9_.-]{1,64}$/u),
  // No production default. This technical bound is not a product-policy choice.
  windowMs: z.number().int().min(1).max(120000) });
const grant = z.strictObject({ protocol_version: z.literal(1), policy_version: z.string(),
  recap_id: api.uuid, book_id: z.string(), revision: api.revision, source_fingerprint: hash,
  checked_at: z.iso.datetime(), expires_at: z.iso.datetime(), max_age_ms: z.number().int().positive(),
  local_pending_verified: z.literal(false), requires_online_on_open: z.literal(true) });
const catalogItem = z.strictObject({ id: evidenceId, entry_id: api.uuid, follow_up_id: api.uuid.nullable(),
  kind: z.enum(['book_excerpt','highlight','user_note','user_question','historical_ai','ai_prompt']),
  provenance: z.enum(['reader_context','trace','follow_up','ai_prompt']),
});
const evidenceItem = catalogItem.extend({ text: z.string().min(1).max(100000),
  location: z.strictObject({ status: z.literal('fragment_only'), exact: z.literal(false),
    chapter_index: z.string().max(100).nullable(), chapter_title: z.string().max(1000) }) });
const scopeResponse = legacy.response.omit({ result: true }).extend({
  evidence_catalog: z.array(catalogItem).max(320), requires_local_confirmation: z.literal(true),
});
const viewResponse = z.strictObject({ recap: legacy.response, display: grant });
const evidenceResponse = z.strictObject({ evidence: z.array(evidenceItem).max(24), display: grant });
const validationResponse = z.strictObject({ display: grant });
const metadata = z.strictObject({ id: api.uuid, book_id: z.string().nullable(), revision: api.revision,
  state: z.enum(['prepared','generating','ready','stale','invalidated','deleted','failed','cancelled','expired']),
  is_saved: z.boolean(), created_at: z.string(), updated_at: z.iso.datetime(),
  expires_at: z.iso.datetime().nullable(),
  availability: z.enum(['requires_online_verification','unavailable']),
});
const historyResponse = z.strictObject({ items: z.array(metadata).max(50), next_cursor: z.string().nullable(),
  contains_private_body: z.literal(false), snapshot_consistent: z.literal(false) });
module.exports = { empty, historyRequest, versionRequest, evidenceRequest, policy, grant, catalogItem,
  evidenceItem, scopeResponse, viewResponse, evidenceResponse, validationResponse, historyResponse };
