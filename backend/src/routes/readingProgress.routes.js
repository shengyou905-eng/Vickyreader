const express = require('express');
const auth = require('../middleware/auth');
const readingProgressController = require('../controllers/readingProgress.controller');

const router = express.Router();

// Two segments cannot match the old unversioned DELETE /:bookId route.
router.put('/versioned/:bookId', auth, readingProgressController.saveReadingProgress);
router.delete('/versioned/:bookId', auth, readingProgressController.deleteReadingProgress);
router.get('/versioned/:bookId', auth, readingProgressController.getReadingProgress);
router.post('/', auth, readingProgressController.saveReadingProgress);
// Old apps apply GET by wall-clock time, potentially overwriting their offline
// queue's source state while legacy uploads are paused for upgrade.
router.get('/:bookId', auth, (req, res) => res.status(428).json({
  error: 'Upgrade required for revision-safe reading progress sync',
}));
router.delete('/:bookId', auth, readingProgressController.deleteReadingProgress);

module.exports = router;
