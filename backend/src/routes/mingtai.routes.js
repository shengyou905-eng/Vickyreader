const express = require('express');
const auth = require('../middleware/auth');
const optionalAuth = require('../middleware/optionalAuth');
const mingtaiController = require('../controllers/mingtai.controller');
const communityController = require('../controllers/community.controller');

const router = express.Router();

router.get('/community/feed', optionalAuth, communityController.feed);
router.get('/community/search', optionalAuth, communityController.search);
router.post('/community/books/resolve', auth, communityController.resolveBook);
router.get('/community/books/:id', optionalAuth, communityController.getBook);
router.put('/community/books/:id/state', auth, communityController.setBookState);
router.post('/community/posts', auth, communityController.createPost);
router.delete('/community/posts/:id', auth, communityController.deletePost);
router.get('/community/posts/:id/comments', communityController.listComments);
router.post('/community/posts/:id/comments', auth, communityController.createComment);
router.post('/community/posts/:id/resonance', auth, communityController.toggleResonance);
router.get('/community/profiles/:userId', optionalAuth, communityController.getProfile);
router.post('/community/profiles/:userId/follow', auth, communityController.follow);
router.delete('/community/profiles/:userId/follow', auth, communityController.unfollow);
router.get('/community/notifications', auth, communityController.notifications);
router.patch('/community/notifications/read-all', auth, communityController.markNotificationsRead);

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
router.post('/books', auth, (_req, res) => {
  res.status(410).json({
    error: '明台已停止接收电子书文件，请发布关联书籍的阅读想法。',
  });
});
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
