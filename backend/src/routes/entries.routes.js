const express = require('express');
const auth = require('../middleware/auth');
const entriesController = require('../controllers/entries.controller');

const router = express.Router();

router.post('/', auth, entriesController.createEntry);
router.get('/', auth, entriesController.listEntries);

module.exports = router;
