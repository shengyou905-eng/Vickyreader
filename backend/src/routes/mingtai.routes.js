const express = require('express');
const auth = require('../middleware/auth');
const mingtaiController = require('../controllers/mingtai.controller');

const router = express.Router();

router.get('/books', mingtaiController.listBooks);
router.post('/books', auth, mingtaiController.publishBook);
router.post('/publish-book', auth, mingtaiController.publishBook);
router.get('/books/:id', mingtaiController.getBook);
router.post('/books/:id/borrow', auth, mingtaiController.borrowBook);
router.post('/annotations/:id/resonances', auth, mingtaiController.createResonance);
router.post('/publish', auth, mingtaiController.publish);
router.get('/feed', mingtaiController.feed);

module.exports = router;
