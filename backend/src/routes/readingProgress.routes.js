const express = require('express');
const auth = require('../middleware/auth');
const readingProgressController = require('../controllers/readingProgress.controller');

const router = express.Router();

router.post('/', auth, readingProgressController.saveReadingProgress);
router.get('/:bookId', auth, readingProgressController.getReadingProgress);

module.exports = router;
