const express = require('express');
const auth = require('../middleware/auth');
const entriesController = require('../controllers/entries.controller');

const router = express.Router();

router.post('/', auth, entriesController.createEntry);
router.get('/', auth, entriesController.listEntries);
router.delete('/:id', auth, entriesController.deleteEntry);

module.exports = router;
