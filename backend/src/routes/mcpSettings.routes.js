const express = require('express');
const auth = require('../middleware/auth');
const mcpSettingsController = require('../controllers/mcpSettings.controller');

const router = express.Router();

router.get('/token', auth, mcpSettingsController.getMcpTokenStatus);
router.post('/token', auth, mcpSettingsController.generateMcpToken);
router.delete('/token', auth, mcpSettingsController.revokeMcpToken);

module.exports = router;
