const express = require('express');
const auth = require('../middleware/auth');
const mingtaiController = require('../controllers/mingtai.controller');

const router = express.Router();

router.post('/publish', auth, mingtaiController.publish);
router.get('/feed', mingtaiController.feed);

module.exports = router;
