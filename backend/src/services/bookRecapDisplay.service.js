const { createHmac, timingSafeEqual } = require('node:crypto');
const { z } = require('zod');
const api = require('./bookRecapApiContract');
const dto = require('./bookRecapDisplayContract');
const legacy = require('./bookRecapHttpContract');
const { principalSchema } = require('./bookRecapExecutor');
const { createBookRecapSourceResolver } = require('./bookRecapSourceResolver');
const { validateSnapshot, validateResult } = require('./bookRecapContract');
const { PROMPT_VERSION } = require('./bookRecapGeneration');
const { historyPage } = require('../repositories/bookRecapDisplay.repository');

const stamp = z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/u);
const cursorSchema = z.strictObject({ version: z.literal(1), binding: z.string(),
  filter: z.enum(['all','saved','preview']), limit: z.number().int().min(1).max(50),
  ceiling: stamp, after: z.strictObject({ created_at: stamp, id: api.uuid }), expires: z.number().int() });

function createBookRecapDisplayService({ repository: repo, authorize, origin, cursorKey,
  cursorLifetimeMs, displayPolicy, clock = () => new Date() }) {
  if (!repo || typeof authorize !== 'function' || !Buffer.isBuffer(cursorKey) || cursorKey.length < 32 ||
      !Number.isSafeInteger(cursorLifetimeMs) || cursorLifetimeMs < 1 || cursorLifetimeMs > 86400000) {
    throw Error('Explicit display dependencies and cursor lifetime required');
  }
  const resolver = createBookRecapSourceResolver({ origin });
  const configured = displayPolicy === undefined ? null : dto.policy.parse(displayPolicy);
  const mac = value => createHmac('sha256', cursorKey).update('recap-display-v1\0').update(value).digest('base64url');
  const binding = userId => mac(JSON.stringify([origin, userId]));
  function decodeCursor(value, principal, body) {
    try {
      const [payload, signature, extra] = value.split('.');
      const expected = mac(payload);
      if (extra || !signature || signature.length !== expected.length ||
          !timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) throw Error();
      const c = cursorSchema.parse(JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')));
      if (c.binding !== binding(principal.userId) || c.limit !== body.limit || c.filter !== body.filter ||
          c.expires <= clock().getTime()) throw Error();
      return c;
    } catch { throw api.recapError(400, 'RECAP_CURSOR_INVALID'); }
  }
  const encodeCursor = value => { const p = Buffer.from(JSON.stringify(cursorSchema.parse(value))).toString('base64url'); return p + '.' + mac(p); };
  async function history(identity, input) {
    const p = principalSchema.parse(identity), body = dto.historyRequest.parse(input);
    const cursor = body.cursor ? decodeCursor(body.cursor, p, body) : null;
    return repo.transaction(p.userId, async tx => {
      await authorize(tx, p.userId, p);
      const page = await historyPage(tx, p.userId, { ...body, after: cursor?.after, ceiling: cursor?.ceiling });
      const items = page.rows.map(row => {
        const expired = !row.is_saved && row.expires_at && row.expires_at <= clock();
        const state = expired && !['deleted','invalidated','stale'].includes(row.state) ? 'expired' : row.state;
        return { id: row.id, book_id: row.book_id, revision: row.revision, state, is_saved: row.is_saved,
          created_at: row.created_at, updated_at: row.updated_at.toISOString(), expires_at: row.expires_at?.toISOString() ?? null,
          availability: state === 'ready' ? 'requires_online_verification' : 'unavailable' };
      });
      const last = page.rows.at(-1);
      const next = page.more ? encodeCursor({ version: 1, binding: binding(p.userId), filter: body.filter,
        limit: body.limit, ceiling: page.ceiling, after: { created_at: last.created_at, id: last.id },
        expires: cursor?.expires ?? clock().getTime() + cursorLifetimeMs }) : null;
      await authorize(tx, p.userId, p);
      return dto.historyResponse.parse({ items, next_cursor: next, contains_private_body: false, snapshot_consistent: false });
    });
  }
  function catalog(snapshot) {
    return snapshot.evidence.filter(e => e.kind !== 'unverified_excerpt').map(e => dto.catalogItem.parse({
      id: e.id, entry_id: e.entryId, follow_up_id: e.followUpId, kind: e.kind, provenance: e.provenance,
    }));
  }
  async function checked(tx, p, id, version) {
    await authorize(tx, p.userId, p);
    // Same lock order as mutations: user -> original sources -> recap.
    const row = await repo.find(tx, p.userId, id);
    if (row.state === 'stale') throw api.recapError(409, 'RECAP_SOURCE_CHANGED');
    repo.readable(row, clock());
    if (row.schema_version !== 1 || row.prompt_version !== PROMPT_VERSION) throw api.recapError(409, 'RECAP_VERSION_UNSUPPORTED');
    if (version && (row.book_id !== version.book_id || row.revision !== version.expected_revision ||
        row.source_fingerprint !== version.expected_source_fingerprint)) throw api.recapError(412, 'RECAP_REVISION_CONFLICT');
    const deps = await repo.dependencies(tx, p.userId, id);
    const scope = { userId: p.userId, origin, bookId: row.book_id };
    const snapshot = validateSnapshot(await resolver.revalidate(tx, p.userId, row, deps), scope);
    validateResult(row.result_json, snapshot, scope, { completed: true, finishReason: 'stop' });
    return { row, snapshot };
  }
  async function scope(identity, idValue, input = {}) {
    const p = principalSchema.parse(identity), id = api.uuid.parse(idValue); dto.empty.parse(input);
    return repo.transaction(p.userId, async tx => {
      const { row, snapshot } = await checked(tx, p, id);
      const { result: _body, ...header } = legacy.present(row, snapshot);
      const response = dto.scopeResponse.parse({ ...header, evidence_catalog: catalog(snapshot), requires_local_confirmation: true });
      await authorize(tx, p.userId, p);
      return response;
    });
  }
  async function display(identity, idValue, input, action) {
    if (!configured) throw api.recapError(503, 'RECAP_DISPLAY_POLICY_REQUIRED');
    const p = principalSchema.parse(identity), id = api.uuid.parse(idValue);
    const body = (action === 'evidence' ? dto.evidenceRequest : dto.versionRequest).parse(input);
    // Lock waits and server processing consume the window; they never extend it.
    const started = clock().getTime();
    const response = await repo.transaction(p.userId, async tx => {
      const { row, snapshot } = await checked(tx, p, id, body);
      const deadline = Math.min(started + configured.windowMs,
        p.expiresAt === undefined ? Infinity : p.expiresAt * 1000,
        !row.is_saved && row.expires_at ? row.expires_at.getTime() : Infinity);
      const now = clock().getTime();
      if (deadline <= now) throw api.recapError(409, 'RECAP_DISPLAY_EXPIRED');
      const permit = dto.grant.parse({ protocol_version: 1, policy_version: configured.version,
        recap_id: id, book_id: row.book_id, revision: row.revision, source_fingerprint: snapshot.fingerprint,
        checked_at: new Date(now).toISOString(), expires_at: new Date(deadline).toISOString(),
        max_age_ms: deadline - now, local_pending_verified: false, requires_online_on_open: true });
      let output;
      if (action === 'view') output = dto.viewResponse.parse({ recap: legacy.present(row, snapshot), display: permit });
      else if (action === 'validate') output = dto.validationResponse.parse({ display: permit });
      else {
        const allowed = new Map(catalog(snapshot).map(e => [e.id, e]));
        if (body.evidence_ids.some(key => !allowed.has(key))) throw api.recapError(404, 'RECAP_EVIDENCE_NOT_FOUND');
        const evidence = body.evidence_ids.map(key => {
          const e = snapshot.evidence.find(v => v.id === key);
          return { ...allowed.get(key), text: e.text, location: { status: 'fragment_only', exact: false,
            chapter_index: e.anchor?.chapterIndex ?? null, chapter_title: e.anchor?.chapterTitle ?? '' } };
        });
        output = dto.evidenceResponse.parse({ evidence, display: permit });
        if (Buffer.byteLength(JSON.stringify(output), 'utf8') > 256 * 1024) throw api.recapError(413, 'RECAP_DISPLAY_BUDGET');
      }
      await authorize(tx, p.userId, p);
      return output;
    });
    if (Date.parse(response.display.expires_at) <= clock().getTime()) throw api.recapError(409, 'RECAP_DISPLAY_EXPIRED');
    return response;
  }
  return Object.freeze({ history, scope, view: (p,id,b) => display(p,id,b,'view'),
    evidence: (p,id,b) => display(p,id,b,'evidence'), validate: (p,id,b) => display(p,id,b,'validate') });
}
module.exports = { createBookRecapDisplayService };
