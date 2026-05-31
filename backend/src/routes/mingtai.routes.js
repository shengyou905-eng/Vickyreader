const express = require('express');
const auth = require('../middleware/auth');
const mingtaiController = require('../controllers/mingtai.controller');

const router = express.Router();

const publicBookUpload = express.raw({
  type: (req) => {
    const contentType = String(req.headers['content-type'] || '').toLowerCase();
    return (
      contentType.startsWith('application/octet-stream') ||
      contentType.startsWith('application/epub+zip') ||
      contentType.startsWith('application/pdf') ||
      contentType.startsWith('text/plain') ||
      contentType.startsWith('multipart/form-data')
    );
  },
  limit: '100mb',
});

router.get('/books', mingtaiController.listBooks);
router.get('/home', mingtaiController.getHome);
router.post('/books', auth, publicBookUpload, mingtaiController.publishBook);
router.get('/books/:id/chapters', mingtaiController.listBookChapters);
router.get('/books/:id/chapters/:chapterIndex', mingtaiController.getBookChapter);
router.get('/books/:id', mingtaiController.getBook);
router.post('/books/:id/borrow', auth, mingtaiController.borrowBook);
router.post('/books/:id/read', mingtaiController.recordBookRead);
router.post('/books/:id/annotations', auth, mingtaiController.createBookAnnotation);
router.post('/annotations/:id/comments', auth, mingtaiController.createAnnotationComment);
router.post('/annotations/:id/resonance', auth, mingtaiController.createResonance);
router.post('/publish', auth, mingtaiController.publish);

module.exports = router;
