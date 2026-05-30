const express = require('express');
const auth = require('../middleware/auth');
const freeNotesController = require('../controllers/freeNotes.controller');

const router = express.Router();

router.get('/', auth, freeNotesController.listFreeNotes);
router.post('/', auth, freeNotesController.upsertFreeNote);
router.post('/:id/xiaou-authorization', auth, freeNotesController.authorizeForXiaou);
router.delete(
  '/:id/xiaou-authorization',
  auth,
  freeNotesController.revokeXiaouAuthorization,
);
router.delete('/:id', auth, freeNotesController.deleteFreeNote);

module.exports = router;
