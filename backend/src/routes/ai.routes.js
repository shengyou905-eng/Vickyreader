const express = require('express');
const aiController = require('../controllers/ai.controller');
const auth = require('../middleware/auth');

const router = express.Router();

router.post('/chat', auth, aiController.chat);

module.exports = router;
