const assert = require('assert');
const { _parseMultipartBody } = require('../controllers/mingtai.controller');
const { parsePublicBookChapters } = require('./publicBookParser');

function makeStoredZip(entries) {
  let offset = 0;
  const locals = [];
  const centrals = [];

  for (const [name, text] of entries) {
    const nameBytes = Buffer.from(name);
    const data = Buffer.from(text);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt32LE(data.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(nameBytes.length, 26);
    locals.push(local, nameBytes, data);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt32LE(data.length, 20);
    central.writeUInt32LE(data.length, 24);
    central.writeUInt16LE(nameBytes.length, 28);
    central.writeUInt32LE(offset, 42);
    centrals.push(central, nameBytes);
    offset += local.length + nameBytes.length + data.length;
  }

  const centralDirectory = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(centralDirectory.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, centralDirectory, end]);
}

function makeEpub() {
  return makeStoredZip([
    [
      'META-INF/container.xml',
      '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
    ],
    [
      'OEBPS/content.opf',
      '<package><manifest><item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>',
    ],
    [
      'OEBPS/ch1.xhtml',
      '<html><head><title>第一章</title></head><body><p>hello world</p></body></html>',
    ],
  ]);
}

function makeMultipartBody(boundary, epub, cover) {
  const text = (value) => Buffer.from(value, 'utf8');
  return Buffer.concat([
    text(`--${boundary}\r\nContent-Disposition: form-data; name="title"\r\n\r\n测试书\r\n`),
    text(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="book.epub"\r\nContent-Type: application/epub+zip\r\n\r\n`),
    epub,
    text('\r\n'),
    text(`--${boundary}\r\nContent-Disposition: form-data; name="cover"; filename="cover.png"\r\nContent-Type: image/png\r\n\r\n`),
    cover,
    text(`\r\n--${boundary}--\r\n`),
  ]);
}

const epub = makeEpub();
const cover = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x00, 0xff]);
const boundary = '----zhidu-test-boundary';
const parsed = _parseMultipartBody({
  headers: { 'content-type': `multipart/form-data; boundary=${boundary}` },
  body: makeMultipartBody(boundary, epub, cover),
});

assert.strictEqual(parsed.fields.title, '测试书');
assert(parsed.files.file.buffer.equals(epub), 'EPUB bytes changed during multipart parsing');
assert(parsed.files.cover.buffer.equals(cover), 'Cover bytes changed during multipart parsing');

const chapters = parsePublicBookChapters(parsed.files.file.buffer, {
  fileType: 'epub',
});
assert.strictEqual(chapters.length, 1);
assert(chapters[0].plain_text.includes('hello world'));

const gbkTxt = Buffer.from(
  'b5dad2bbd5c20ad5e2cac7d6d0cec4c4dac8dd',
  'hex',
);
const txtChapters = parsePublicBookChapters(gbkTxt, { fileType: 'txt' });
assert.strictEqual(txtChapters.length, 1);
assert(txtChapters[0].plain_text.includes('这是中文内容'));

const longTxt = Buffer.from(`第一章\n${'这是较长的正文。'.repeat(1600)}`, 'utf8');
const longTxtChapters = parsePublicBookChapters(longTxt, { fileType: 'txt' });
assert(longTxtChapters.length > 1, 'oversized TXT chapter was not split');
assert(longTxtChapters.every((chapter) => chapter.plain_text.length <= 8100));

console.log('Mingtai EPUB/TXT parser smoke test: ok');
