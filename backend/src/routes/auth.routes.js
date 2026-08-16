const express = require('express');
const authController = require('../controllers/auth.controller');
const appleAuthController = require('../controllers/appleAuth.controller');
const auth = require('../middleware/auth');

const router = express.Router();

router.post('/register', authController.register);
router.post('/login', authController.login);
router.post('/apple/prepare', appleAuthController.prepare);
router.post('/apple/login', appleAuthController.login);
router.post('/apple/bind', auth, appleAuthController.bind);
router.post('/logout', auth, authController.logout);
router.get('/ai-consent', auth, authController.getAiConsent);
router.post('/ai-consent', auth, authController.acceptAiConsent);
router.delete('/ai-consent', auth, authController.revokeAiConsent);
router.delete('/account', auth, authController.deleteAccount);

module.exports = router;
