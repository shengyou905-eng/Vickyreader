const insightRepository = require('../repositories/insight.repository');
const { scheduleUserInsightRefresh } = require('../services/insightRefresh.service');
const httpError = require('../utils/httpError');

async function getHome(req, res, next) {
  try {
    const insight = await insightRepository.getOrCreateUserInsight(req.user.id);
    if (insightRepository.isStale(insight)) {
      scheduleUserInsightRefresh(req.user.id, { delayMs: 0 });
    }
    return res.json({ insight: presentInsight(insight) });
  } catch (error) {
    return next(error);
  }
}

async function answerQuestion(req, res, next) {
  try {
    const insight = await insightRepository.getOrCreateUserInsight(req.user.id);
    const questionId = String(req.params.questionId || '').trim();
    const questions = asArray(insight.high_value_questions);
    const question = questions.find((item) => item.id === questionId);
    if (!question) {
      throw httpError(404, '这条回望问题已经更新，请刷新小U首页');
    }
    if (insightRepository.isStale(insight)) {
      scheduleUserInsightRefresh(req.user.id, { delayMs: 0 });
    }
    return res.json({
      question_id: question.id,
      question: question.title,
      answer: question.answer,
      generated_at: insight.refreshed_at,
      cached: true,
    });
  } catch (error) {
    return next(error);
  }
}

async function refreshHome(req, res, next) {
  try {
    scheduleUserInsightRefresh(req.user.id, { delayMs: 0 });
    return res.status(202).json({ status: 'refreshing' });
  } catch (error) {
    return next(error);
  }
}

function presentInsight(insight) {
  return {
    recent_focus: insight.recent_focus || {},
    weekly_summary: insight.weekly_summary || '',
    long_term_topics: asArray(insight.long_term_topics),
    high_value_questions: asArray(insight.high_value_questions),
    recent_entries: asArray(insight.recent_entries),
    deep_reflection: insight.deep_reflection || '',
    source_entry_count: Number(insight.source_entry_count) || 0,
    authorized_note_count: Number(insight.authorized_note_count) || 0,
    refreshed_at: insight.refreshed_at,
  };
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

module.exports = {
  getHome,
  answerQuestion,
  refreshHome,
};
