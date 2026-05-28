const path = require('path');
const zlib = require('zlib');

function parsePublicBookChapters(buffer, { fileType, title = '' } = {}) {
  const type = String(fileType || '').toLowerCase().replace('.', '').trim();
  if (type === 'epub') return parseEpubChapters(buffer);
  if (type === 'txt') return parseTxtChapters(buffer, { title });
  return [];
}

function parseEpubChapters(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) return [];

  const zip = readZip(buffer);
  const containerPath = findZipPath(zip, 'META-INF/container.xml');
  if (!containerPath) {
    throw Object.assign(new Error('Invalid EPUB: missing container.xml'), {
      statusCode: 400,
    });
  }

  const containerXml = zipText(zip, containerPath);
  const opfPath = attr(
    firstTag(containerXml, 'rootfile', (tag) => attr(tag, 'full-path')),
    'full-path',
  );
  if (!opfPath) {
    throw Object.assign(new Error('Invalid EPUB: missing OPF path'), {
      statusCode: 400,
    });
  }

  const normalizedOpfPath = normalizeArchivePath(opfPath);
  const opfZipPath = findZipPath(zip, normalizedOpfPath);
  if (!opfZipPath) {
    throw Object.assign(new Error('Invalid EPUB: missing content.opf'), {
      statusCode: 400,
    });
  }

  const opfXml = zipText(zip, opfZipPath);
  const opfDir = archiveDir(opfZipPath);
  const manifest = parseManifest(opfXml);
  const spine = parseSpine(opfXml);
  const chapters = [];

  for (const itemRef of spine) {
    const item = manifest.get(itemRef);
    if (!item?.href) continue;

    const chapterPath = findZipPath(zip, joinArchivePath(opfDir, item.href));
    if (!chapterPath) continue;

    const rawHtml = zipText(zip, chapterPath);
    const content = normalizeChapterHtml(rawHtml);
    const plainText = htmlToText(content);
    if (!plainText) continue;

    chapters.push({
      chapter_index: chapters.length,
      title: chapterTitle(rawHtml, chapters.length),
      content,
      plain_text: plainText,
      href: chapterPath,
    });
  }

  return chapters;
}

function parseTxtChapters(buffer, { title = '' } = {}) {
  const text = decodeText(buffer).replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const chunks = splitTxtChapters(text);
  const fallbackTitle = cleanText(title) || '正文';
  return chunks.map((chunk, index) => {
    const chapterTitleText = cleanText(chunk.title) || (
      chunks.length === 1 ? fallbackTitle : `第${index + 1}部分`
    );
    const content = txtChapterHtml(chapterTitleText, chunk.content);
    return {
      chapter_index: index,
      title: chapterTitleText,
      content,
      plain_text: cleanText(chunk.content),
      href: '',
    };
  }).filter((chapter) => chapter.plain_text);
}

function splitTxtChapters(text) {
  const patterns = [
    /(第[零一二三四五六七八九十百千\d]+[章节回卷部])/g,
    /(序[言章]|前言|楔子|尾声|后记|附录|番外)/g,
    /(Chapter\s+\d+)/gi,
    /(Part\s+\d+)/gi,
    /^(\d+[\.\、]\s*.+)$/gm,
  ];
  const markers = new Map();

  for (const pattern of patterns) {
    for (const match of text.matchAll(pattern)) {
      const index = match.index ?? 0;
      const tooClose = [...markers.keys()].some((existing) => Math.abs(existing - index) < 3);
      if (!tooClose) markers.set(index, match[1] || match[0]);
    }
  }

  const sorted = [...markers.entries()].sort((a, b) => a[0] - b[0]);
  if (sorted.length === 0) return splitTextByLength(text, 5000);

  const chapters = [];
  if (sorted[0][0] > 200) {
    const before = text.slice(0, sorted[0][0]).trim();
    if (before) chapters.push({ title: '前言', content: before });
  }

  for (let i = 0; i < sorted.length; i += 1) {
    const start = sorted[i][0];
    const end = i + 1 < sorted.length ? sorted[i + 1][0] : text.length;
    const content = text.slice(start, end).trim();
    if (content) chapters.push({ title: sorted[i][1], content });
  }

  return chapters;
}

function splitTextByLength(text, maxLength) {
  const chapters = [];
  let start = 0;
  while (start < text.length) {
    let end = Math.min(start + maxLength, text.length);
    if (end < text.length) {
      const paraBreak = text.lastIndexOf('\n\n', end);
      if (paraBreak > start + maxLength * 0.5) end = paraBreak;
    }
    const content = text.slice(start, end).trim();
    if (content) {
      chapters.push({ title: `第${chapters.length + 1}部分`, content });
    }
    start = end > start ? end : start + maxLength;
  }
  return chapters.length > 0 ? chapters : [{ title: '正文', content: text.trim() }];
}

function readZip(buffer) {
  const entries = new Map();
  const eocdOffset = findEndOfCentralDirectory(buffer);
  if (eocdOffset < 0) {
    throw Object.assign(new Error('Invalid EPUB: missing zip directory'), {
      statusCode: 400,
    });
  }

  const totalEntries = buffer.readUInt16LE(eocdOffset + 10);
  const centralDirectoryOffset = buffer.readUInt32LE(eocdOffset + 16);
  let offset = centralDirectoryOffset;

  for (let i = 0; i < totalEntries; i += 1) {
    if (buffer.readUInt32LE(offset) !== 0x02014b50) break;
    const compressionMethod = buffer.readUInt16LE(offset + 10);
    const compressedSize = buffer.readUInt32LE(offset + 20);
    const localHeaderOffset = buffer.readUInt32LE(offset + 42);
    const fileNameLength = buffer.readUInt16LE(offset + 28);
    const extraLength = buffer.readUInt16LE(offset + 30);
    const commentLength = buffer.readUInt16LE(offset + 32);
    const name = normalizeArchivePath(
      buffer.slice(offset + 46, offset + 46 + fileNameLength).toString('utf8'),
    );

    if (name && !name.endsWith('/')) {
      entries.set(name.toLowerCase(), {
        name,
        compressionMethod,
        compressedSize,
        localHeaderOffset,
      });
    }
    offset += 46 + fileNameLength + extraLength + commentLength;
  }

  return { buffer, entries };
}

function findEndOfCentralDirectory(buffer) {
  const min = Math.max(0, buffer.length - 65557);
  for (let offset = buffer.length - 22; offset >= min; offset -= 1) {
    if (buffer.readUInt32LE(offset) === 0x06054b50) return offset;
  }
  return -1;
}

function zipText(zip, archivePath) {
  const bytes = zipBytes(zip, archivePath);
  return decodeText(bytes);
}

function zipBytes(zip, archivePath) {
  const entry = zip.entries.get(normalizeArchivePath(archivePath).toLowerCase());
  if (!entry) return Buffer.alloc(0);

  const { buffer } = zip;
  const offset = entry.localHeaderOffset;
  if (buffer.readUInt32LE(offset) !== 0x04034b50) return Buffer.alloc(0);

  const fileNameLength = buffer.readUInt16LE(offset + 26);
  const extraLength = buffer.readUInt16LE(offset + 28);
  const dataStart = offset + 30 + fileNameLength + extraLength;
  const compressed = buffer.slice(dataStart, dataStart + entry.compressedSize);

  if (entry.compressionMethod === 0) return compressed;
  if (entry.compressionMethod === 8) return zlib.inflateRawSync(compressed);

  throw Object.assign(new Error('Unsupported EPUB compression method'), {
    statusCode: 400,
  });
}

function findZipPath(zip, requestedPath) {
  const normalized = normalizeArchivePath(requestedPath).toLowerCase();
  if (zip.entries.has(normalized)) return zip.entries.get(normalized).name;
  return [...zip.entries.values()].find((entry) => entry.name.toLowerCase() === normalized)?.name || '';
}

function parseManifest(opfXml) {
  const manifest = new Map();
  for (const tag of allTags(opfXml, 'item')) {
    const id = attr(tag, 'id');
    const href = attr(tag, 'href');
    const mediaType = attr(tag, 'media-type');
    if (id && href && /xhtml|html|xml/i.test(mediaType || href)) {
      manifest.set(id, { href, mediaType });
    }
  }
  return manifest;
}

function parseSpine(opfXml) {
  return allTags(opfXml, 'itemref')
    .map((tag) => attr(tag, 'idref'))
    .filter(Boolean);
}

function normalizeChapterHtml(rawHtml) {
  const bodyMatch = rawHtml.match(/<body\b[^>]*>([\s\S]*?)<\/body>/i);
  const body = bodyMatch ? bodyMatch[1] : rawHtml;
  const cleaned = body
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, '')
    .replace(/<nav\b[^>]*>[\s\S]*?<\/nav>/gi, '')
    .trim();
  return `<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>${cleaned}</body></html>`;
}

function txtChapterHtml(title, content) {
  const paragraphs = escapeHtml(content)
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => `<p>${line}</p>`)
    .join('\n');
  return `<!DOCTYPE html><html><head><meta charset="utf-8"></head><body><h1 class="chapter-title">${escapeHtml(title)}</h1>${paragraphs}</body></html>`;
}

function chapterTitle(rawHtml, index) {
  const titleTags = [
    /<h1\b[^>]*>([\s\S]*?)<\/h1>/i,
    /<h2\b[^>]*>([\s\S]*?)<\/h2>/i,
    /<h3\b[^>]*>([\s\S]*?)<\/h3>/i,
    /<title\b[^>]*>([\s\S]*?)<\/title>/i,
  ];
  for (const pattern of titleTags) {
    const value = cleanText(stripTags(rawHtml.match(pattern)?.[1] || ''));
    if (value) return value.slice(0, 120);
  }
  return `第${index + 1}章`;
}

function htmlToText(html) {
  return cleanText(stripTags(html));
}

function stripTags(value) {
  return decodeEntities(String(value || '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<[^>]+>/g, ' '));
}

function cleanText(value) {
  return decodeEntities(String(value || ''))
    .replace(/\u00a0/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function decodeEntities(value) {
  return String(value || '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(parseInt(dec, 10)));
}

function escapeHtml(value) {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function allTags(xml, tagName) {
  const pattern = new RegExp(`<[^>]*:?${tagName}\\b[^>]*>`, 'gi');
  return xml.match(pattern) || [];
}

function firstTag(xml, tagName, predicate) {
  const tags = allTags(xml, tagName);
  return tags.find((tag) => !predicate || predicate(tag)) || '';
}

function attr(tag, name) {
  const match = String(tag || '').match(new RegExp(`\\b${name}\\s*=\\s*["']([^"']+)["']`, 'i'));
  return decodeEntities(match?.[1] || '');
}

function normalizeArchivePath(value) {
  return String(value || '').replace(/\\/g, '/').replace(/^\/+/, '').replace(/\/+/g, '/');
}

function archiveDir(value) {
  const dir = path.posix.dirname(normalizeArchivePath(value));
  return dir === '.' ? '' : dir;
}

function joinArchivePath(base, href) {
  const rawHref = normalizeArchivePath(href);
  if (!base) return normalizeArchivePath(path.posix.normalize(rawHref));
  return normalizeArchivePath(path.posix.normalize(path.posix.join(base, rawHref)));
}

function decodeText(buffer) {
  return Buffer.from(buffer || []).toString('utf8').replace(/^\uFEFF/, '');
}

module.exports = {
  parsePublicBookChapters,
};
