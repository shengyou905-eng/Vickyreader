const { AI_CONSENT_VERSION } = require('../controllers/auth.controller');

function requireAiConsent(req, res, next) {
  if (Number(req.authUser?.ai_consent_version || 0) < AI_CONSENT_VERSION) {
    return res.status(428).json({
      error: '使用小U前需要先同意第三方 AI 数据处理说明',
      code: 'AI_CONSENT_REQUIRED',
      required_version: AI_CONSENT_VERSION,
    });
  }
  return next();
}

module.exports = requireAiConsent;
