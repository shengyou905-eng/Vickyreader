const readingProgressRepository = require('../repositories/readingProgress.repository');
const httpError = require('../utils/httpError');

async function saveReadingProgress(req, res, next) {
  try {
    if (!req.body.book_id) {
      throw httpError(400, 'book_id is required');
    }

    const readingProgress = await readingProgressRepository.upsertReadingProgress(
      req.user.id,
      req.body,
    );
    return res.json({ reading_progress: readingProgress });
  } catch (error) {
    return next(error);
  }
}

async function getReadingProgress(req, res, next) {
  try {
    const readingProgress = await readingProgressRepository.getReadingProgress(
      req.user.id,
      req.params.bookId,
    );

    if (!readingProgress) {
      return res.status(404).json({ error: 'Reading progress not found' });
    }

    return res.json({ reading_progress: readingProgress });
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  saveReadingProgress,
  getReadingProgress,
};
