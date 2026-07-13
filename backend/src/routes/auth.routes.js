const express = require('express');
const authController = require('../controllers/auth.controller');
const auth = require('../middleware/auth');

const router = express.Router();

router.post('/register', authController.register);
router.post('/login', authController.login);
router.post('/logout', auth, authController.logout);
router.get('/ai-consent', auth, authController.getAiConsent);
router.post('/ai-consent', auth, authController.acceptAiConsent);
router.delete('/ai-consent', auth, authController.revokeAiConsent);
router.delete('/account', auth, authController.deleteAccount);

module.exports = router;
