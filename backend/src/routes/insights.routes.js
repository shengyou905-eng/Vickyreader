const express = require('express');
const insightsController = require('../controllers/insights.controller');
const auth = require('../middleware/auth');

const router = express.Router();

router.post('/questions/:questionId/answer', auth, insightsController.answerQuestion);

module.exports = router;
