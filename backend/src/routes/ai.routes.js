const express = require('express');
const aiController = require('../controllers/ai.controller');
const auth = require('../middleware/auth');
const requireAiConsent = require('../middleware/requireAiConsent');
const { createAiRequestGuard } = require('../middleware/aiRequestGuard');

const router = express.Router();
const guard = createAiRequestGuard();

router.post('/chat', auth, requireAiConsent, guard, aiController.chat);
router.post('/xiaou-asks', auth, requireAiConsent, guard, aiController.xiaouAsks);
router.post('/explain', auth, requireAiConsent, guard, aiController.explain);
router.post('/reader-question', auth, requireAiConsent, guard, aiController.readerQuestion);

module.exports = router;
