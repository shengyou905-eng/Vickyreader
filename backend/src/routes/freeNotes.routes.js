const express = require('express');
const auth = require('../middleware/auth');
const freeNotesController = require('../controllers/freeNotes.controller');

const router = express.Router();

router.get('/', auth, freeNotesController.listFreeNotes);
router.post('/', auth, freeNotesController.upsertFreeNote);
router.delete('/:id', auth, freeNotesController.deleteFreeNote);

module.exports = router;
