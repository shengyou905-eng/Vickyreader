const freeNoteRepository = require('../repositories/freeNote.repository');
const { scheduleUserInsightRefresh } = require('../services/insightRefresh.service');
const httpError = require('../utils/httpError');

async function upsertFreeNote(req, res, next) {
  try {
    const id = String(req.body.id || '').trim();
    const content = String(req.body.content || '').trim();
    if (!id) throw httpError(400, 'id is required');
    if (!content) throw httpError(400, 'content is required');

    const note = await freeNoteRepository.upsertFreeNote(req.user.id, req.body);
    scheduleUserInsightRefresh(req.user.id);
    return res.status(200).json({ note });
  } catch (error) {
    return next(error);
  }
}

async function listFreeNotes(req, res, next) {
  try {
    const notes = await freeNoteRepository.listFreeNotes(req.user.id, req.query);
    return res.json({ notes });
  } catch (error) {
    return next(error);
  }
}

async function deleteFreeNote(req, res, next) {
  try {
    const deleted = await freeNoteRepository.deleteFreeNote(
      req.user.id,
      req.params.id,
    );
    if (!deleted) throw httpError(404, 'Free note not found');
    scheduleUserInsightRefresh(req.user.id);
    return res.status(204).send();
  } catch (error) {
    return next(error);
  }
}

async function authorizeForXiaou(req, res, next) {
  try {
    const authorized = await freeNoteRepository.authorizeForXiaou(
      req.user.id,
      req.params.id,
    );
    if (!authorized) throw httpError(404, 'Free note not found');
    scheduleUserInsightRefresh(req.user.id);
    return res.json({ xiaou_authorized: true });
  } catch (error) {
    return next(error);
  }
}

async function revokeXiaouAuthorization(req, res, next) {
  try {
    await freeNoteRepository.revokeXiaouAuthorization(
      req.user.id,
      req.params.id,
    );
    scheduleUserInsightRefresh(req.user.id);
    return res.status(204).send();
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  upsertFreeNote,
  listFreeNotes,
  deleteFreeNote,
  authorizeForXiaou,
  revokeXiaouAuthorization,
};
