const mingtaiRepository = require('../repositories/mingtai.repository');
const httpError = require('../utils/httpError');

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function normalizeEntryIds(body) {
  const raw = Array.isArray(body.entry_ids)
    ? body.entry_ids
    : body.entry_id
      ? [body.entry_id]
      : [];

  return [...new Set(raw.map((id) => String(id).trim()).filter(Boolean))];
}

async function publish(req, res, next) {
  try {
    const entryIds = normalizeEntryIds(req.body);
    if (entryIds.length === 0) {
      throw httpError(400, 'entry_ids is required');
    }

    const invalidId = entryIds.find((id) => !uuidPattern.test(id));
    if (invalidId) {
      throw httpError(400, `Invalid entry id: ${invalidId}`);
    }

    const annotations = await mingtaiRepository.publishEntries(req.user.id, entryIds);
    if (annotations.length === 0) {
      throw httpError(404, 'No owned entries found to publish');
    }

    return res.status(201).json({
      annotations,
      count: annotations.length,
    });
  } catch (error) {
    return next(error);
  }
}

async function feed(req, res, next) {
  try {
    const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 100);
    const annotations = await mingtaiRepository.listFeed({ limit });
    return res.json({ annotations });
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  publish,
  feed,
};
