const express = require('express');
const aiController = require('../controllers/ai.controller');
const auth = require('../middleware/auth');
const requireAiConsent = require('../middleware/requireAiConsent');

const router = express.Router();

router.post('/chat', auth, requireAiConsent, aiController.chat);
router.post('/explain', auth, requireAiConsent, aiController.explain);

module.exports = router;
