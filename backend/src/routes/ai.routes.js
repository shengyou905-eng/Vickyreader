const express = require('express');
const aiController = require('../controllers/ai.controller');
const auth = require('../middleware/auth');

const router = express.Router();

router.post('/chat', auth, aiController.chat);
router.post('/explain', auth, aiController.explain);

module.exports = router;
