const express = require('express');
const auth = require('../middleware/auth');
const controller = require('../controllers/xiaouConversation.controller');

const router = express.Router();

router.get('/conversations', auth, controller.listConversations);
router.post('/conversations', auth, controller.createConversation);
router.get('/conversations/:id', auth, controller.getConversation);
router.post('/conversations/:id/messages', auth, controller.appendMessage);
router.delete('/conversations/:id', auth, controller.deleteConversation);

module.exports = router;
