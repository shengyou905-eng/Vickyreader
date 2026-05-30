const express = require('express');
const aiController = require('../controllers/ai.controller');
const auth = require('../middleware/auth');

const router = express.Router();

router.post('/chat', auth, (_req, res) => {
  res.status(410).json({
    error: '小U已收敛为阅读回顾入口，请使用固定引导问题。',
  });
});
router.post('/explain', auth, aiController.explain);

module.exports = router;
