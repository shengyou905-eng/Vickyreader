const express = require('express');
const insightsController = require('../controllers/insights.controller');
const auth = require('../middleware/auth');

const router = express.Router();

router.get('/home', auth, insightsController.getHome);
router.post('/refresh', auth, insightsController.refreshHome);
router.post('/questions/:questionId/answer', auth, insightsController.answerQuestion);

module.exports = router;
