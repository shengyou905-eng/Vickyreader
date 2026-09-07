const entryRepository = require('../repositories/entry.repository');
const { scheduleUserInsightRefresh } = require('../services/insightRefresh.service');
const httpError = require('../utils/httpError');
const { validateVersion } = require('../repositories/uploadState.repository');

const allowedSources = new Set([
  'highlight',
  'thought',
  'ai_explanation',
  'ai_question',
  'manual',
]);

async function createEntry(req, res, next) {
  try {
    if (!allowedSources.has(req.body.source)) {
      throw httpError(400, 'Invalid entry source');
    }

    const entry = await entryRepository.createEntry(req.user.id, req.body);
    scheduleUserInsightRefresh(req.user.id);
    return res.status(201).json({ entry });
  } catch (error) {
    return next(error);
  }
}

async function upsertEntryByClientId(req, res, next) {
  try {
    validateVersion(req.body);
    const clientEntryId = String(req.params.clientEntryId || '').trim();
    if (!clientEntryId || clientEntryId.length > 200) {
      throw httpError(400, 'Invalid client entry id');
    }
    if (!allowedSources.has(req.body.source)) {
      throw httpError(400, 'Invalid entry source');
    }
    const result = await entryRepository.upsertEntryByClientId(
      req.user.id, clientEntryId, req.body,
    );
    if (result.operation) scheduleUserInsightRefresh(req.user.id);
    return res.status(result.operation === 'created' ? 201 : 200).json({
      entry: result.entry,
      operation: result.operation || 'unchanged',
      upload_status: result.upload_status,
    });
  } catch (error) {
    return next(error);
  }
}

async function deleteEntryByClientId(req, res, next) {
  try {
    validateVersion(req.body);
    const clientEntryId = String(req.params.clientEntryId || '').trim();
    if (!clientEntryId || clientEntryId.length > 200) {
      throw httpError(400, 'Invalid client entry id');
    }
    const deleted = await entryRepository.deleteEntryByClientId(
      req.user.id, clientEntryId, req.body,
    );
    if (deleted) scheduleUserInsightRefresh(req.user.id);
    return res.status(204).send();
  } catch (error) {
    return next(error);
  }
}

async function listEntries(req, res, next) {
  try {
    if (req.query.source && !allowedSources.has(req.query.source)) {
      throw httpError(400, 'Invalid entry source');
    }

    const entries = await entryRepository.listEntries(req.user.id, req.query);
    return res.json({ entries });
  } catch (error) {
    return next(error);
  }
}

async function deleteEntry(req, res, next) {
  try {
    const deleted = await entryRepository.deleteEntry(req.user.id, req.params.id);
    if (!deleted) {
      throw httpError(404, 'Entry not found');
    }

    scheduleUserInsightRefresh(req.user.id);
    return res.status(204).send();
  } catch (error) {
    return next(error);
  }
}

async function updateEntryImportance(req, res, next) {
  try {
    if (typeof req.body.is_important !== 'boolean') {
      throw httpError(400, 'is_important must be a boolean');
    }

    const entry = await entryRepository.updateEntryImportance(
      req.user.id,
      req.params.id,
      req.body.is_important,
    );
    if (!entry) {
      throw httpError(404, 'Entry not found');
    }
    return res.json({ entry });
  } catch (error) {
    return next(error);
  }
}

async function listFollowUps(req, res, next) {
  try {
    const followUps = await entryRepository.listFollowUps(
      req.user.id,
      req.params.id,
    );
    return res.json({ follow_ups: followUps });
  } catch (error) {
    return next(error);
  }
}

async function createFollowUp(req, res, next) {
  try {
    const question = String(req.body.question || '').trim();
    const answer = String(req.body.answer || '').trim();
    if (!question || !answer) {
      throw httpError(400, 'question and answer are required');
    }
    if (question.length > 4000 || answer.length > 30000) {
      throw httpError(400, 'Follow-up content is too long');
    }

    const followUp = await entryRepository.createFollowUp(
      req.user.id,
      req.params.id,
      question,
      answer,
    );
    if (!followUp) {
      throw httpError(404, 'Entry not found');
    }
    return res.status(201).json({ follow_up: followUp });
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  createEntry,
  upsertEntryByClientId,
  deleteEntryByClientId,
  listEntries,
  deleteEntry,
  updateEntryImportance,
  listFollowUps,
  createFollowUp,
};
