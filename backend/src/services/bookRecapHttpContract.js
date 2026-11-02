const { z } = require('zod');
const api = require('./bookRecapApiContract');
const { resultSchema } = require('./bookRecapContract');

const coverage = z.strictObject({ basis: z.literal('reading_traces'), fullBook: z.literal(false),
  sourceCompleteness: z.literal('server_selected_records'), availableEntries: z.number().int().nonnegative(),
  includedEntries: z.number().int().nonnegative(), includedFollowUps: z.number().int().nonnegative(),
  quarantinedEntries: z.number().int().nonnegative(), selectionApplied: z.boolean() });
const response = z.strictObject({ id: api.uuid, book_id: z.string(), revision: api.revision,
  state: z.enum(['prepared','generating','ready','failed','cancelled']), is_saved: z.boolean(),
  source_fingerprint: z.string().regex(/^[a-f0-9]{64}$/u), coverage,
  sources: z.array(z.strictObject({ entry_id: api.uuid, follow_up_ids: z.array(api.uuid).max(320) })).max(80),
  evidence_summary: z.strictObject({ transmitted: z.number().int().nonnegative(),
    excluded_unverified: z.number().int().nonnegative() }),
  result: resultSchema.nullable(),
  scope_basis: z.literal('selected_cloud_records_only'), local_pending_verified: z.literal(false) });
function present(row, snapshot) {
  const sources = [...new Set(snapshot.evidence.map(e => e.entryId))].sort().map(entryId => ({
    entry_id: entryId, follow_up_ids: [...new Set(snapshot.evidence
      .filter(e => e.entryId === entryId && e.followUpId).map(e => e.followUpId))].sort(),
  }));
  return response.parse({ id: row.id, book_id: row.book_id, revision: row.revision, state: row.state,
    is_saved: row.is_saved, source_fingerprint: row.source_fingerprint, coverage: row.coverage_json,
    sources, evidence_summary: {
      transmitted: snapshot.evidence.filter(e => e.kind !== 'unverified_excerpt').length,
      excluded_unverified: snapshot.evidence.filter(e => e.kind === 'unverified_excerpt').length,
    }, result: row.state === 'ready' ? row.result_json : null,
    scope_basis: 'selected_cloud_records_only', local_pending_verified: false });
}
const empty = z.strictObject({});
const outcome = z.strictObject({ status: z.enum(['running','succeeded','failed','cancelled','interrupted','expired','revoked']), replay: z.boolean() });
module.exports = { ...api, empty, response, outcome, present };
