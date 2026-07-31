const repository = require('../repositories/xiaouConversation.repository');
const httpError = require('../utils/httpError');

async function createConversation(req, res, next) {
  try {
    const conversation = await repository.createConversation(
      req.user.id,
      req.body,
    );
    return res.status(201).json({ conversation });
  } catch (error) {
    return next(error);
  }
}

async function listConversations(req, res, next) {
  try {
    const conversations = await repository.listConversations(
      req.user.id,
      req.query,
    );
    return res.json({ conversations });
  } catch (error) {
    return next(error);
  }
}

async function getConversation(req, res, next) {
  try {
    const conversation = await repository.getConversation(
      req.user.id,
      req.params.id,
    );
    if (!conversation) throw httpError(404, 'Conversation not found');
    return res.json({ conversation });
  } catch (error) {
    return next(error);
  }
}

async function appendMessage(req, res, next) {
  try {
    const role = String(req.body.role || '').trim();
    const content = String(req.body.content || '').trim();
    const status = String(req.body.status || 'completed').trim();
    if (!['user', 'assistant'].includes(role)) {
      throw httpError(400, 'role must be user or assistant');
    }
    if (!content) throw httpError(400, 'content is required');
    if (!['completed', 'cancelled', 'error'].includes(status)) {
      throw httpError(400, 'invalid message status');
    }

    const message = await repository.appendMessage(
      req.user.id,
      req.params.id,
      { role, content, status },
    );
    if (!message) throw httpError(404, 'Conversation not found');
    return res.status(201).json({ message });
  } catch (error) {
    return next(error);
  }
}

async function deleteConversation(req, res, next) {
  try {
    const deleted = await repository.deleteConversation(
      req.user.id,
      req.params.id,
    );
    if (!deleted) throw httpError(404, 'Conversation not found');
    return res.status(204).send();
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  createConversation,
  listConversations,
  getConversation,
  appendMessage,
  deleteConversation,
};
