const insightRepository = require('../repositories/insight.repository');

const pendingRefreshes = new Map();

function scheduleUserInsightRefresh(userId, { delayMs = 250 } = {}) {
  if (!userId) return;
  const pending = pendingRefreshes.get(userId);
  if (pending) clearTimeout(pending);

  const timer = setTimeout(async () => {
    pendingRefreshes.delete(userId);
    try {
      await insightRepository.refreshUserInsight(userId);
    } catch (error) {
      console.error('[user-insights] background refresh failed', {
        userId,
        message: error.message,
      });
    }
  }, delayMs);
  timer.unref?.();
  pendingRefreshes.set(userId, timer);
}

module.exports = {
  scheduleUserInsightRefresh,
};
