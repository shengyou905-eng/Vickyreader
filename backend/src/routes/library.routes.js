const express = require('express');
const auth = require('../middleware/auth');
const libraryController = require('../controllers/library.controller');

const router = express.Router();

router.post('/books/sync', auth, libraryController.syncLibraryBooks);
router.delete('/books/:bookId/data', auth, libraryController.permanentlyDeleteBookData);
router.delete('/books/:bookId', auth, libraryController.deleteLibraryBook);

module.exports = router;
