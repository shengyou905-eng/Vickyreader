const crypto = require('crypto');
const fs = require('fs/promises');
const path = require('path');

const uploadDir = path.resolve(__dirname, '..', '..', 'uploads', 'public_books');
const supportedExtensions = new Set(['epub', 'txt', 'pdf']);
const mimeByType = {
  epub: 'application/epub+zip',
  txt: 'text/plain',
  pdf: 'application/pdf',
};

function sanitizeFileName(value) {
  return String(value || '')
    .normalize('NFKD')
    .trim()
    .replace(/[^a-zA-Z0-9._-]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 80);
}

function typeFromMime(mime) {
  const contentType = String(mime || '').toLowerCase();
  if (contentType.includes('epub')) return 'epub';
  if (contentType.includes('pdf')) return 'pdf';
  if (contentType.startsWith('text/plain')) return 'txt';
  return '';
}

function typeFromName(fileName) {
  const ext = path.extname(String(fileName || '')).replace('.', '').toLowerCase();
  return supportedExtensions.has(ext) ? ext : '';
}

function normalizeFileType({ fileType, fileName, mimeType }) {
  const rawType = String(fileType || '').toLowerCase().replace('.', '').trim();
  const type = supportedExtensions.has(rawType)
    ? rawType
    : typeFromName(fileName) || typeFromMime(mimeType);
  if (!supportedExtensions.has(type)) {
    throw Object.assign(new Error('Unsupported public book file type'), {
      statusCode: 400,
    });
  }
  return type;
}

async function savePublicBookFile(buffer, { fileName, fileType, mimeType }) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    throw Object.assign(new Error('book file is required'), {
      statusCode: 400,
    });
  }

  const type = normalizeFileType({ fileType, fileName, mimeType });
  await fs.mkdir(uploadDir, { recursive: true });

  const baseName = sanitizeFileName(path.basename(String(fileName || ''), path.extname(String(fileName || ''))));
  const fallbackName = crypto
    .createHash('sha1')
    .update(String(fileName || Date.now()))
    .digest('hex')
    .slice(0, 12);
  const safeBaseName = baseName || `public-book-${fallbackName}`;
  const storedName = `${Date.now()}-${crypto.randomUUID()}-${safeBaseName}.${type}`;
  const absolutePath = path.join(uploadDir, storedName);
  await fs.writeFile(absolutePath, buffer);

  const storagePath = path.posix.join('uploads', 'public_books', storedName);
  return {
    file_type: type,
    file_size: buffer.length,
    mime_type: mimeByType[type],
    storage_path: storagePath,
    public_path: `/${storagePath}`,
  };
}

module.exports = {
  savePublicBookFile,
};
