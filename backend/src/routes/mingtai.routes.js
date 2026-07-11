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
router.get('/profiles/me', auth, mingtaiController.getMyProfile);
router.put('/profiles/me', auth, mingtaiController.updateMyProfile);
router.post('/profiles/me/avatar', auth, mingtaiController.uploadMyProfileAvatar);
router.get('/profiles/:userId', mingtaiController.getPublicProfile);
router.get('/notifications', auth, mingtaiController.listNotifications);
router.get(
  '/notifications/unread-count',
  auth,
  mingtaiController.getUnreadNotificationCount,
);
router.patch(
  '/notifications/read-all',
  auth,
  mingtaiController.markAllNotificationsRead,
);
router.patch(
  '/notifications/:id/read',
  auth,
  mingtaiController.markNotificationRead,
);
router.post('/books', auth, publicBookUpload, mingtaiController.publishBook);
router.delete('/books', auth, mingtaiController.deleteMyBooks);
router.delete('/books/:id', auth, mingtaiController.deleteMyBook);
router.patch('/reviews/:id', auth, mingtaiController.updateBookReview);
router.delete('/reviews/:id', auth, mingtaiController.deleteBookReview);
router.get('/reviews/:id/comments', mingtaiController.listBookReviewComments);
router.post(
  '/reviews/:id/comments',
  auth,
  mingtaiController.createBookReviewComment,
);
router.post(
  '/reviews/:id/resonance',
  auth,
  mingtaiController.createBookReviewResonance,
);
router.get('/books/:id/chapters', mingtaiController.listBookChapters);
router.get('/books/:id/chapters/:chapterIndex', mingtaiController.getBookChapter);
router.get('/books/:id/reviews', mingtaiController.listBookReviews);
router.post('/books/:id/reviews', auth, mingtaiController.createBookReview);
router.get('/books/:id', mingtaiController.getBook);
router.post('/books/:id/borrow', auth, mingtaiController.borrowBook);
router.post('/books/:id/read', mingtaiController.recordBookRead);
router.post('/books/:id/annotations', auth, mingtaiController.createBookAnnotation);
router.get('/annotations/:id/comments', mingtaiController.listAnnotationComments);
router.post('/annotations/:id/comments', auth, mingtaiController.createAnnotationComment);
router.post('/annotations/:id/resonance', auth, mingtaiController.createResonance);
router.post('/publish', auth, mingtaiController.publish);

module.exports = router;
