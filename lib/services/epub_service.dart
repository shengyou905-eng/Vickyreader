import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import '../config/constants.dart';
import '../models/book.dart';

class EpubChapter {
  final String title;
  final String content; // raw HTML content with resolved image paths
  final int index;

  EpubChapter({
    required this.title,
    required this.content,
    required this.index,
  });
}

class EpubMetadata {
  final String title;
  final String author;
  final String? description;
  final String? coverHref;

  EpubMetadata({
    required this.title,
    required this.author,
    this.description,
    this.coverHref,
  });
}

class EpubService {
  static Future<Book> importEpub(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Parse container.xml
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) throw Exception('Invalid EPUB: missing container.xml');

    final containerXml = XmlDocument.parse(
      utf8.decode(containerFile.content as List<int>),
    );
    final rootfile = containerXml
        .findAllElements('rootfile')
        .firstWhere((e) => e.getAttribute('media-type') == 'application/oebps-package+xml');
    final opfPath = rootfile.getAttribute('full-path')!;

    // Parse content.opf
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) throw Exception('Invalid EPUB: missing content.opf');

    final opfDir = p.dirname(opfPath);
    final opfXml = XmlDocument.parse(
      utf8.decode(opfFile.content as List<int>),
    );

    final metadata = _parseMetadata(opfXml);
    final manifest = _parseManifest(opfXml);
    final spine = _parseSpine(opfXml);
    final guide = _parseGuide(opfXml);

    // Setup book directories
    final appDir = (await getApplicationDocumentsDirectory()).path;
    final bookDir = p.join(appDir, AppConstants.booksDir);
    await Directory(bookDir).create(recursive: true);
    final bookId = const Uuid().v4();
    final bookChapterDir = p.join(bookDir, bookId);
    await Directory(bookChapterDir).create();
    final imageDir = p.join(bookChapterDir, 'images');
    await Directory(imageDir).create();

    // Extract ALL images from EPUB to book images dir
    final imageMap = _extractAllImages(archive, imageDir);

    // Extract cover image (multi-strategy)
    String? coverPath;
    // Strategy 1: metadata coverHref
    if (metadata.coverHref != null) {
      coverPath = await _extractCoverByHref(archive, opfDir, metadata.coverHref!, appDir);
    }
    // Strategy 2: guide cover reference
    if (coverPath == null && guide.coverHref != null) {
      coverPath = await _extractCoverByHref(archive, opfDir, guide.coverHref!, appDir);
    }
    // Strategy 3: manifest item with "cover" in id
    coverPath ??= await _extractCoverById(archive, opfDir, manifest, appDir);
    // Strategy 4: first image in book
    if (coverPath == null && imageMap.isNotEmpty) {
      coverPath = imageMap.values.first;
    }

    // Extract chapters
    final chapters = <EpubChapter>[];
    for (int i = 0; i < spine.length; i++) {
      final href = spine[i];
      final fullPath = _resolvePath(opfDir, href);
      final file = archive.findFile(fullPath);
      if (file != null) {
        final rawHtml = utf8.decode(file.content as List<int>);
        final cleanContent = _cleanHtml(rawHtml, archive, opfDir);
        final contentWithImages = _rewriteImagePaths(cleanContent, imageMap);
        final title = _extractChapterTitle(rawHtml) ?? '第${i + 1}章';
        chapters.add(EpubChapter(
          title: title,
          content: contentWithImages,
          index: i,
        ));
      }
    }

    // Save chapter files
    for (final chapter in chapters) {
      final chapterFile = File(p.join(bookChapterDir, 'ch_${chapter.index}.html'));
      await chapterFile.writeAsString(chapter.content);
    }

    // Save metadata
    final titlesFile = File(p.join(bookChapterDir, 'titles.json'));
    await titlesFile.writeAsString(jsonEncode(chapters.map((c) => c.title).toList()));

    final spineFile = File(p.join(bookChapterDir, 'spine.json'));
    await spineFile.writeAsString(jsonEncode(spine));

    return Book(
      id: bookId,
      title: metadata.title,
      author: metadata.author,
      coverPath: coverPath,
      filePath: filePath,
      description: metadata.description,
      addedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
      chapterTitles: chapters.map((c) => c.title).toList(),
    );
  }

  static Future<List<EpubChapter>> getChapters(String bookId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final bookChapterDir = p.join(appDir.path, AppConstants.booksDir, bookId);
    final titlesFile = File(p.join(bookChapterDir, 'titles.json'));

    List<String> titles = [];
    if (await titlesFile.exists()) {
      titles = (jsonDecode(await titlesFile.readAsString()) as List).cast<String>();
    }

    final chapters = <EpubChapter>[];
    for (int i = 0; i < titles.length; i++) {
      final chapterFile = File(p.join(bookChapterDir, 'ch_$i.html'));
      if (await chapterFile.exists()) {
        chapters.add(EpubChapter(
          title: titles[i],
          content: await chapterFile.readAsString(),
          index: i,
        ));
      }
    }
    return chapters;
  }

  /// Get the chapter HTML file path for file-based loading
  static Future<String> getChapterFilePath(String bookId, int index) async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, AppConstants.booksDir, bookId, 'ch_$index.html');
  }

  static Future<List<String>> getSpine(String bookId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final spineFile = File(p.join(appDir.path, AppConstants.booksDir, bookId, 'spine.json'));
    if (await spineFile.exists()) {
      return (jsonDecode(await spineFile.readAsString()) as List).cast<String>();
    }
    return [];
  }

  static String getPlainText(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    return document.body?.text ?? '';
  }

  static ({String before, String after}) getContext(
      String htmlContent, String selectedText, int charCount) {
    final plainText = getPlainText(htmlContent);
    final idx = plainText.indexOf(selectedText);
    if (idx == -1) return (before: '', after: '');
    final before = plainText.substring((idx - charCount).clamp(0, idx), idx);
    final after = plainText.substring(
      (idx + selectedText.length).clamp(0, plainText.length),
      (idx + selectedText.length + charCount).clamp(0, plainText.length),
    );
    return (before: before, after: after);
  }

  // ---- Internal ----

  static EpubMetadata _parseMetadata(XmlDocument opf) {
    final metadataNode = opf.findAllElements('metadata').first;
    final dc = 'http://purl.org/dc/elements/1.1/';
    final dcterms = 'http://purl.org/dc/terms/';

    String title = '';
    String author = '';
    String? description;
    String? coverHref;

    final titleNode = metadataNode.findElements('${dc}title').firstOrNull ??
        metadataNode.findElements('title').firstOrNull;
    title = titleNode?.innerText ?? 'Unknown Title';

    final creatorNode = metadataNode.findElements('${dc}creator').firstOrNull ??
        metadataNode.findElements('creator').firstOrNull;
    author = creatorNode?.innerText ?? 'Unknown Author';

    final descNode = metadataNode.findElements('${dc}description').firstOrNull ??
        metadataNode.findElements('${dcterms}description').firstOrNull ??
        metadataNode.findElements('description').firstOrNull;
    description = descNode?.innerText;

    // EPUB 2: <meta name="cover" content="cover-id"/>
    for (final meta in metadataNode.findElements('meta')) {
      if (meta.getAttribute('name') == 'cover') {
        final coverId = meta.getAttribute('content');
        if (coverId != null) {
          for (final item in opf.findAllElements('item')) {
            if (item.getAttribute('id') == coverId) {
              coverHref = item.getAttribute('href');
              break;
            }
          }
        }
      }
    }

    // EPUB 3: <item properties="cover-image" href="..."/>
    // Also check property (singular — some EPUBs use this)
    if (coverHref == null) {
      for (final item in opf.findAllElements('item')) {
        final props = item.getAttribute('properties') ?? '';
        final prop = item.getAttribute('property') ?? '';
        if (props.contains('cover-image') || prop.contains('cover-image')) {
          coverHref = item.getAttribute('href');
          break;
        }
      }
    }

    return EpubMetadata(
      title: title,
      author: author,
      description: description,
      coverHref: coverHref,
    );
  }

  static Map<String, String> _parseManifest(XmlDocument opf) {
    final manifest = <String, String>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) manifest[id] = href;
    }
    return manifest;
  }

  static List<String> _parseSpine(XmlDocument opf) {
    final spine = <String>[];
    final manifest = _parseManifest(opf);
    for (final itemref in opf.findAllElements('itemref')) {
      final idref = itemref.getAttribute('idref');
      if (idref != null && manifest.containsKey(idref)) {
        spine.add(manifest[idref]!);
      }
    }
    return spine;
  }

  /// Parse EPUB 2 `guide` element for cover reference
  static ({String? coverHref}) _parseGuide(XmlDocument opf) {
    String? coverHref;
    for (final ref in opf.findAllElements('reference')) {
      final type = ref.getAttribute('type') ?? '';
      if (type == 'cover' || type == 'cover-page') {
        final href = ref.getAttribute('href');
        if (href != null) coverHref = href;
        break;
      }
    }
    return (coverHref: coverHref);
  }

  // ---- Image extraction ----

  /// Extract ALL images from EPUB archive into the book's images directory.
  /// Returns a map of original href → local file path.
  static Map<String, String> _extractAllImages(Archive archive, String imageDir) {
    final imageMap = <String, String>{};
    for (final file in archive.files) {
      if (file.isFile && _isImageFile(file.name)) {
        final ext = p.extension(file.name).isNotEmpty ? p.extension(file.name) : '.jpg';
        final localName = '${_hashFilename(file.name)}$ext';
        final localPath = p.join(imageDir, localName);
        try {
          File(localPath).writeAsBytesSync(file.content as List<int>);
          imageMap[file.name] = localPath;
        } catch (_) {}
      }
    }
    return imageMap;
  }

  static bool _isImageFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.svg');
  }

  /// Rewrite image src in HTML from EPUB paths to local file paths
  static String _rewriteImagePaths(String html, Map<String, String> imageMap) {
    if (imageMap.isEmpty) return html;
    var result = html;
    for (final entry in imageMap.entries) {
      // Try multiple path variants: exact, basename, relative
      final basename = p.basename(entry.key);
      final fileUri = Uri.file(entry.value);
      // Replace exact match
      result = result.replaceAll(entry.key, fileUri.toString());
      // Replace basename match (common in flat EPUBs)
      result = result.replaceAll('src="$basename"', 'src="${fileUri.toString()}"');
      result = result.replaceAll("src='$basename'", "src='${fileUri.toString()}'");
      // Replace URL-decoded versions
      final decoded = Uri.decodeFull(entry.key);
      if (decoded != entry.key) {
        result = result.replaceAll(decoded, fileUri.toString());
      }
    }
    return result;
  }

  // ---- Cover extraction strategies ----

  static Future<String?> _extractCoverByHref(
      Archive archive, String opfDir, String coverHref, String appDir) async {
    try {
      final resolvedPath = _resolvePath(opfDir, coverHref);
      var file = archive.findFile(resolvedPath);
      // Try case-insensitive match
      file ??= archive.files
          .where((f) => f.name.toLowerCase() == resolvedPath.toLowerCase())
          .firstOrNull;
      // Try just the filename (some EPUBs have flatter structure)
      if (file == null) {
        final basename = p.basename(resolvedPath);
        file = archive.files
            .where((f) =>
                f.name.endsWith(basename) && _isImageFile(f.name))
            .firstOrNull;
      }
      if (file != null) {
        return await _saveCoverFile(file, appDir);
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _extractCoverById(
      Archive archive, String opfDir,
      Map<String, String> manifest, String appDir) async {
    try {
      // Look for manifest items with "cover" in their id
      for (final entry in manifest.entries) {
        if (entry.key.toLowerCase().contains('cover') && _isImageFile(entry.value)) {
          final resolvedPath = _resolvePath(opfDir, entry.value);
          final file = archive.findFile(resolvedPath);
          if (file != null) return await _saveCoverFile(file, appDir);
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<String> _saveCoverFile(ArchiveFile file, String appDir) async {
    final coversDir = p.join(appDir, 'covers');
    await Directory(coversDir).create(recursive: true);
    final ext = p.extension(file.name).isNotEmpty ? p.extension(file.name) : '.jpg';
    final coverFile = File(p.join(coversDir, '${const Uuid().v4()}$ext'));
    await coverFile.writeAsBytes(file.content as List<int>);
    return coverFile.path;
  }

  // ---- HTML processing ----

  static String _resolvePath(String base, String href) {
    // Handle URL-encoded paths
    final decoded = Uri.decodeFull(href);
    if (decoded.startsWith('/')) return decoded.substring(1);
    final result = p.normalize(p.join(base, decoded)).replaceAll('\\', '/');
    return result;
  }

  static String _cleanHtml(String rawHtml, Archive archive, String opfDir) {
    // Remove scripts (security)
    var cleaned = rawHtml
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<img[^>]*src="kindle:[^"]*"[^>]*/?>', caseSensitive: false), '');

    // Inline CSS from <link rel="stylesheet"> before removing link tags
    final cssLinkRe = RegExp(
      r'<link[^>]+rel="stylesheet"[^>]+href="([^"]+)"[^>]*/?>',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAllMapped(cssLinkRe, (m) {
      final href = m.group(1);
      if (href == null) return '';
      final resolved = _resolvePath(opfDir, href);
      final cssFile = archive.findFile(resolved);
      if (cssFile != null) {
        final css = utf8.decode(cssFile.content as List<int>);
        return '<style>\n$css\n</style>';
      }
      return '';
    });

    // Remove remaining <link> tags
    cleaned = cleaned.replaceAll(RegExp(r'<link[^>]*/?>', caseSensitive: false), '');

    // Fix self-closing tags that might confuse the parser
    cleaned = cleaned.replaceAll(RegExp(r'<br\s*/>', caseSensitive: false), '<br>');

    return cleaned;
  }

  static String? _extractChapterTitle(String html) {
    final hMatch =
        RegExp(r'<h[1-6][^>]*>(.*?)</h[1-6]>', caseSensitive: false).firstMatch(html);
    if (hMatch != null) {
      return html_parser.parseFragment(hMatch.group(1)!).text?.trim();
    }
    final titleMatch =
        RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false).firstMatch(html);
    if (titleMatch != null) {
      return html_parser.parseFragment(titleMatch.group(1)!).text?.trim();
    }
    return null;
  }

  static String _hashFilename(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 12);
  }
}
