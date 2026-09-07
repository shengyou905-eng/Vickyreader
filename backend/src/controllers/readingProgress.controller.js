const readingProgressRepository = require('../repositories/readingProgress.repository');
const httpError = require('../utils/httpError');
const { validateVersion } = require('../repositories/uploadState.repository');

async function saveReadingProgress(req, res, next) {
  try {
    validateVersion(req.body);
    const bookId = req.params.bookId || req.body.book_id;
    if (typeof bookId !== 'string' || !bookId.trim() || bookId.length > 200 || bookId.trim() !== bookId) {
      throw httpError(400, 'book_id is required');
    }

    const readingProgress = await readingProgressRepository.upsertReadingProgress(
      req.user.id,
      { ...req.body, book_id: bookId },
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

async function deleteReadingProgress(req, res, next) {
  try {
    validateVersion(req.body);
    await readingProgressRepository.deleteReadingProgress(
      req.user.id,
      req.params.bookId,
      req.body,
    );
    return res.status(204).send();
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  saveReadingProgress,
  getReadingProgress,
  deleteReadingProgress,
};
