const crypto = require('crypto');
const fs = require('fs/promises');
const path = require('path');

const uploadDir = path.resolve(__dirname, '..', '..', 'uploads', 'public_books');
const coverUploadDir = path.resolve(
  __dirname,
  '..',
  '..',
  'uploads',
  'public_book_covers',
);
const profileAvatarUploadDir = path.resolve(
  __dirname,
  '..',
  '..',
  'uploads',
  'profile_avatars',
);
const backendRoot = path.resolve(__dirname, '..', '..');
const supportedExtensions = new Set(['epub', 'txt', 'pdf']);
const supportedCoverExtensions = new Set(['jpg', 'jpeg', 'png', 'gif', 'webp']);
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

function normalizeCoverType({ fileName, mimeType }) {
  const fileType = path.extname(String(fileName || '')).replace('.', '').toLowerCase();
  if (supportedCoverExtensions.has(fileType)) return fileType;

  const contentType = String(mimeType || '').toLowerCase();
  for (const type of supportedCoverExtensions) {
    if (contentType.includes(type)) return type;
  }
  return 'jpg';
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

async function savePublicBookCover(buffer, { fileName, mimeType }) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) return null;

  const type = normalizeCoverType({ fileName, mimeType });
  await fs.mkdir(coverUploadDir, { recursive: true });
  const storedName = `${Date.now()}-${crypto.randomUUID()}.${type}`;
  const absolutePath = path.join(coverUploadDir, storedName);
  await fs.writeFile(absolutePath, buffer);

  const storagePath = path.posix.join('uploads', 'public_book_covers', storedName);
  return {
    storage_path: storagePath,
    public_path: `/${storagePath}`,
  };
}

async function saveProfileAvatar(buffer, { fileName, mimeType }) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    throw Object.assign(new Error('avatar image is required'), {
      statusCode: 400,
    });
  }

  const type = normalizeCoverType({ fileName, mimeType });
  await fs.mkdir(profileAvatarUploadDir, { recursive: true });
  const storedName = `${Date.now()}-${crypto.randomUUID()}.${type}`;
  const absolutePath = path.join(profileAvatarUploadDir, storedName);
  await fs.writeFile(absolutePath, buffer);

  const storagePath = path.posix.join('uploads', 'profile_avatars', storedName);
  return {
    storage_path: storagePath,
    public_path: `/${storagePath}`,
  };
}

async function deletePublicBookFile(storagePath) {
  const absolutePath = absoluteStoragePath(storagePath);
  if (!absolutePath) return;
  await fs.unlink(absolutePath).catch((error) => {
    if (error.code !== 'ENOENT') throw error;
  });
}

function absoluteStoragePath(storagePath) {
  const normalized = String(storagePath || '').replace(/\\/g, '/').replace(/^\/+/, '');
  if (!normalized) return '';

  const absolutePath = path.resolve(backendRoot, normalized);
  if (!absolutePath.startsWith(backendRoot)) {
    throw Object.assign(new Error('Invalid storage_path'), {
      statusCode: 400,
    });
  }
  return absolutePath;
}

module.exports = {
  absoluteStoragePath,
  deletePublicBookFile,
  savePublicBookCover,
  savePublicBookFile,
  saveProfileAvatar,
};
