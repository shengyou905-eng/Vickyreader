import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class BmobApi {
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'auth_user_id';
  static const _emailKey = 'auth_email';
  static const _authTimeout = Duration(seconds: 20);
  static const _mingtaiTimeout = Duration(seconds: 20);
  static const _mingtaiUploadTimeout = Duration(seconds: 75);

  String? _token;
  String? _userId;
  String? _email;

  BmobApi._();

  static final BmobApi instance = BmobApi._();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _userId = prefs.getString(_userIdKey);
    _email = prefs.getString(_emailKey);
  }

  bool get isLoggedIn => _token?.trim().isNotEmpty ?? false;
  String? get userId => _userId;
  String? get email => _email;
  String? get token => _token;

  // ---- Auth ----

  Future<Map<String, dynamic>?> signUp(String email, String password) async {
    try {
      final res = await _postJsonWithRetry(
        Uri.parse('${AppConstants.apiBaseUrl}/api/auth/register'),
        {'email': email, 'password': password},
      );

      if (res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>;
        await _saveSession(
          token: data['token'] as String,
          userId: user['id'] as String,
          email: user['email'] as String? ?? email,
        );
        return data;
      }
      final err = _tryDecodeError(res.body, res.statusCode);
      return {'error': err};
    } catch (e) {
      return {'error': _friendlyError(e)};
    }
  }

  Future<Map<String, dynamic>?> signIn(String email, String password) async {
    try {
      final res = await _postJsonWithRetry(
        Uri.parse('${AppConstants.apiBaseUrl}/api/auth/login'),
        {'email': email, 'password': password},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>;
        await _saveSession(
          token: data['token'] as String,
          userId: user['id'] as String,
          email: user['email'] as String? ?? email,
        );
        return data;
      }
      final err = _tryDecodeError(res.body, res.statusCode);
      return {'error': err};
    } catch (e) {
      return {'error': _friendlyError(e)};
    }
  }

  Future<void> signOut() async {
    _token = null;
    _userId = null;
    _email = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_emailKey);
  }

  // ---- Data CRUD ----

  Future<List<Map<String, dynamic>>> select(
    String table, {
    String? whereJson,
    String? order,
    int? limit,
  }) async {
    final queryParams = <String, String>{};
    if (whereJson != null) queryParams['where'] = whereJson;
    if (order != null) queryParams['order'] = order;
    if (limit != null) queryParams['limit'] = limit.toString();

    final uri = Uri.parse(
      '${AppConstants.apiBaseUrl}/api/classes/$table',
    ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    final res = await http
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['results'] ?? []);
    }
    throw Exception('查询失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>?> create(
    String table,
    Map<String, dynamic> body,
  ) async {
    final res = await http
        .post(
          Uri.parse('${AppConstants.apiBaseUrl}/api/classes/$table'),
          headers: _authHeaders(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('创建失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<bool> update(
    String table,
    String objectId,
    Map<String, dynamic> body,
  ) async {
    final res = await http
        .put(
          Uri.parse('${AppConstants.apiBaseUrl}/api/classes/$table/$objectId'),
          headers: _authHeaders(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return true;
    throw Exception('更新失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<bool> delete(String table, String objectId) async {
    final res = await http
        .delete(
          Uri.parse('${AppConstants.apiBaseUrl}/api/classes/$table/$objectId'),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return true;
    throw Exception('删除失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>?> createUserEntry(
    Map<String, dynamic> body,
  ) async {
    final res = await http
        .post(
          Uri.parse('${AppConstants.apiBaseUrl}/api/entries'),
          headers: _authHeaders(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 201) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['entry'] as Map<String, dynamic>?;
    }
    throw Exception('创建 user_entry 失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<List<Map<String, dynamic>>> listUserEntries({
    String? bookId,
    String? source,
    String? tag,
    String? createdAt,
    String? createdAtFrom,
    String? createdAtTo,
    int? limit,
  }) async {
    final queryParams = <String, String>{};
    if (bookId != null && bookId.isNotEmpty) queryParams['book_id'] = bookId;
    if (source != null && source.isNotEmpty) queryParams['source'] = source;
    if (tag != null && tag.isNotEmpty) queryParams['tag'] = tag;
    if (createdAt != null && createdAt.isNotEmpty) {
      queryParams['created_at'] = createdAt;
    }
    if (createdAtFrom != null && createdAtFrom.isNotEmpty) {
      queryParams['created_at_from'] = createdAtFrom;
    }
    if (createdAtTo != null && createdAtTo.isNotEmpty) {
      queryParams['created_at_to'] = createdAtTo;
    }
    if (limit != null) queryParams['limit'] = limit.toString();

    final uri = Uri.parse(
      '${AppConstants.apiBaseUrl}/api/entries',
    ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    final res = await http
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['entries'] ?? []);
    }
    throw Exception('查询 user_entries 失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<bool> deleteUserEntry(String id) async {
    try {
      final res = await http
          .delete(
            Uri.parse('${AppConstants.apiBaseUrl}/api/entries/$id'),
            headers: _authHeaders(),
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 204) return true;
      if (res.statusCode == 404) return false;
      throw Exception('删除 user_entry 失败 (HTTP ${res.statusCode}): ${res.body}');
    } on TimeoutException {
      throw Exception('删除接口超时：请确认线上后端已部署 DELETE /api/entries/:id');
    }
  }

  Future<List<Map<String, dynamic>>> listFreeNotes({
    String? query,
    int limit = 500,
  }) async {
    final queryParams = <String, String>{'limit': limit.toString()};
    final q = query?.trim() ?? '';
    if (q.isNotEmpty) queryParams['query'] = q;

    final uri = Uri.parse(
      '${AppConstants.apiBaseUrl}/api/free-notes',
    ).replace(queryParameters: queryParams);
    final res = await http
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['notes'] ?? []);
    }
    throw Exception('查询随心记失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>?> upsertFreeNote({
    required String id,
    required String title,
    required String content,
    required String createdAt,
    required String updatedAt,
  }) async {
    final res = await http
        .post(
          Uri.parse('${AppConstants.apiBaseUrl}/api/free-notes'),
          headers: _authHeaders(),
          body: jsonEncode({
            'id': id,
            'title': title,
            'content': content,
            'created_at': createdAt,
            'updated_at': updatedAt,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['note'] as Map<String, dynamic>?;
    }
    throw Exception('保存随心记失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<bool> deleteFreeNote(String id) async {
    final safeId = Uri.encodeComponent(id);
    final res = await http
        .delete(
          Uri.parse('${AppConstants.apiBaseUrl}/api/free-notes/$safeId'),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 204) return true;
    if (res.statusCode == 404) return false;
    throw Exception('删除随心记失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<void> setFreeNoteXiaouAuthorization(
    String id, {
    required bool authorized,
  }) async {
    final safeId = Uri.encodeComponent(id);
    final uri = Uri.parse(
      '${AppConstants.apiBaseUrl}/api/free-notes/$safeId/xiaou-authorization',
    );
    final res = authorized
        ? await http
              .post(uri, headers: _authHeaders())
              .timeout(const Duration(seconds: 15))
        : await http
              .delete(uri, headers: _authHeaders())
              .timeout(const Duration(seconds: 15));
    if (authorized && res.statusCode == 200) return;
    if (!authorized && res.statusCode == 204) return;
    throw Exception(
      '${authorized ? '授权' : '撤回授权'}失败 '
      '(HTTP ${res.statusCode}): ${res.body}',
    );
  }

  Future<Map<String, dynamic>> getXiaouHomeInsight() async {
    final res = await http
        .get(
          Uri.parse('${AppConstants.apiBaseUrl}/api/insights/home'),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 5));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return Map<String, dynamic>.from(data['insight'] ?? {});
    }
    throw Exception('读取小U首页失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<List<Map<String, dynamic>>> publishMingtaiAnnotations(
    List<String> entryIds,
  ) async {
    final res = await http
        .post(
          Uri.parse('${AppConstants.apiBaseUrl}/api/mingtai/publish'),
          headers: _authHeaders(),
          body: jsonEncode({'entry_ids': entryIds}),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode == 201) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['annotations'] ?? []);
    }
    throw Exception('公开到明台失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> publishMingtaiBook({
    required String sourceBookId,
    required String title,
    required String copyrightStatus,
    required String filePath,
    required String fileType,
    String? author,
    String? coverPath,
    String? description,
    List<String> entryIds = const [],
  }) async {
    await init();
    final token = _token?.trim() ?? '';
    debugPrint('[MingtaiPublishBook] hasToken=${token.isNotEmpty}');
    if (token.isEmpty) {
      throw Exception('请先登录后再发布到明台');
    }
    _token = token;

    final file = File(filePath);
    debugPrint('[MingtaiPublishBook] file.path=${file.path}');
    debugPrint('[MingtaiPublishBook] file.existsSync=${file.existsSync()}');
    if (!await file.exists()) {
      throw Exception('发布失败：找不到本地书籍文件');
    }
    final fileLen = await file.length();
    final ext = p.extension(filePath).toLowerCase();
    // Check file header (EPUB is ZIP, should start with PK)
    final header = await file
        .openRead(0, 2)
        .toList()
        .then((l) => l.isNotEmpty ? String.fromCharCodes(l[0]) : '');
    final isZip = header.startsWith('PK');
    debugPrint(
      '[MingtaiPublishBook] file.length=$fileLen extension=$ext isZip=$isZip',
    );

    final resolvedSourceBookId = sourceBookId.trim().isNotEmpty
        ? sourceBookId.trim()
        : _fallbackSourceBookId(filePath: filePath, title: title);
    final localCoverPath = coverPath?.trim() ?? '';
    final localCover = localCoverPath.isNotEmpty ? File(localCoverPath) : null;
    final hasLocalCover = localCover != null && await localCover.exists();
    final fields = <String, String>{
      'source_book_id': resolvedSourceBookId,
      'title': title,
      'author': author ?? '',
      'cover_url': _publicUrlOrEmpty(coverPath),
      'description': description ?? '',
      'copyright_status': copyrightStatus,
      'file_type': fileType,
      'file_name': p.basename(filePath),
      'file_size': (await file.length()).toString(),
      if (entryIds.isNotEmpty) 'entry_ids': entryIds.join(','),
    };
    final uri = Uri.parse('${AppConstants.apiBaseUrl}/api/mingtai/books');

    debugPrint('[MingtaiPublishBook] POST $uri');
    debugPrint(
      '[MingtaiPublishBook] request.body=${jsonEncode({...fields, 'cover_file': hasLocalCover ? p.basename(localCoverPath) : ''})}',
    );
    debugPrint('[MingtaiPublishBook] source_book_id=$resolvedSourceBookId');

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders(contentType: ''))
      ..headers.addAll({
        'x-source-book-id': resolvedSourceBookId,
        'x-file-type': fileType,
        'x-copyright-status': copyrightStatus,
      })
      ..fields.addAll(fields)
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: p.basename(filePath),
        ),
      );
    debugPrint(
      '[MingtaiPublishBook] multipart file field=file filename=${p.basename(filePath)} path=$filePath size=$fileLen extension=$ext',
    );
    if (hasLocalCover) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'cover',
          localCoverPath,
          filename: p.basename(localCoverPath),
        ),
      );
    }
    final streamed = await request.send().timeout(const Duration(minutes: 3));
    final res = await http.Response.fromStream(
      streamed,
    ).timeout(const Duration(minutes: 3));

    debugPrint('[MingtaiPublishBook] statusCode=${res.statusCode}');
    debugPrint('[MingtaiPublishBook] response.body=${res.body}');

    if (res.statusCode == 201) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      _assertPublishedBookReadable(data);
      return data;
    }
    if (res.statusCode == 401) {
      await signOut();
      throw Exception('登录已过期，请重新登录后再发布到明台');
    }
    throw Exception('发布书籍到明台失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> deleteMyMingtaiBooks() async {
    await init();
    final res = await http
        .delete(
          Uri.parse('${AppConstants.apiBaseUrl}/api/mingtai/books'),
          headers: _authHeaders(),
        )
        .timeout(_mingtaiTimeout);

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('清理明台书籍失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  void _assertPublishedBookReadable(Map<String, dynamic> data) {
    final rawBook = data['book'];
    final book = rawBook is Map ? Map<String, dynamic>.from(rawBook) : data;
    final fileUrl = book['file_url']?.toString().trim() ?? '';
    if (fileUrl.isEmpty) {
      throw Exception('服务器没有保存书籍文件：public_books.file_url 为空。请先部署最新后端后重新发布。');
    }
    final fileType = book['file_type']?.toString().trim().toLowerCase() ?? '';
    final chapterCount =
        int.tryParse(book['chapter_count']?.toString() ?? '') ?? 0;
    if ((fileType == 'epub' || fileType == 'txt') && chapterCount <= 0) {
      throw Exception('服务器没有生成章节缓存，请先部署最新后端后重新发布。');
    }
  }

  Future<List<Map<String, dynamic>>> listMingtaiBooks({
    int limit = 50,
    String search = '',
  }) async {
    final queryParameters = <String, String>{'limit': limit.toString()};
    final q = search.trim();
    if (q.isNotEmpty) queryParameters['q'] = q;
    final uri = Uri.parse(
      '${AppConstants.apiBaseUrl}/api/mingtai/books',
    ).replace(queryParameters: queryParameters);

    debugPrint('[MingtaiBooks] GET $uri');
    try {
      final res = await http
          .get(uri, headers: _authHeaders())
          .timeout(_mingtaiTimeout);

      debugPrint('[MingtaiBooks] statusCode=${res.statusCode}');

      Map<String, dynamic> data;
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[MingtaiBooks] parsed json error=$e');
        throw Exception('明台书库返回不是 JSON (HTTP ${res.statusCode})');
      }

      if (res.statusCode == 200) {
        final books = data['books'];
        if (books is List) {
          debugPrint('[MingtaiBooks] books.length=${books.length}');
          return List<Map<String, dynamic>>.from(books);
        }
        debugPrint('[MingtaiBooks] books missing or not list, fallback=[]');
        return [];
      }

      throw Exception(
        data['error']?.toString() ??
            '读取明台书库失败 (HTTP ${res.statusCode}): ${res.body}',
      );
    } on TimeoutException catch (e) {
      debugPrint('[MingtaiBooks] timeout=$e');
      throw Exception('明台连接有点慢，请稍后重试');
    }
  }

  Future<Map<String, dynamic>> getMingtaiHome() async {
    try {
      final res = await http
          .get(
            Uri.parse('${AppConstants.apiBaseUrl}/api/mingtai/home'),
            headers: _authHeaders(),
          )
          .timeout(_mingtaiTimeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      throw Exception('读取明台首页失败 (HTTP ${res.statusCode}): ${res.body}');
    } on TimeoutException {
      throw Exception('明台连接有点慢，请稍后重试');
    }
  }

  Future<Map<String, dynamic>> getMingtaiBook(String bookId) async {
    late final http.Response res;
    try {
      res = await http
          .get(
            Uri.parse('${AppConstants.apiBaseUrl}/api/mingtai/books/$bookId'),
            headers: _authHeaders(),
          )
          .timeout(_mingtaiTimeout);
    } on TimeoutException {
      throw Exception('明台书籍加载超时，请稍后重试');
    }

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('读取明台书籍失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<List<Map<String, dynamic>>> listMingtaiBookReviews(
    String bookId,
  ) async {
    late final http.Response res;
    try {
      res = await http
          .get(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/mingtai/books/$bookId/reviews',
            ),
            headers: _authHeaders(),
          )
          .timeout(_mingtaiTimeout);
    } on TimeoutException {
      throw Exception('读者短评加载超时，请稍后重试');
    }

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['reviews'] ?? []);
    }
    throw Exception('读取读者短评失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> createMingtaiBookReview({
    required String bookId,
    required String content,
  }) async {
    late final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/mingtai/books/$bookId/reviews',
            ),
            headers: _authHeaders(),
            body: jsonEncode({'content': content}),
          )
          .timeout(_mingtaiTimeout);
    } on TimeoutException {
      throw Exception('发布短评超时，请稍后重试');
    }

    if (res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('发布短评失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> updateMingtaiBookReview({
    required String reviewId,
    required String content,
  }) async {
    late final http.Response res;
    try {
      res = await http
          .patch(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/mingtai/reviews/$reviewId',
            ),
            headers: _authHeaders(),
            body: jsonEncode({'content': content}),
          )
          .timeout(_mingtaiTimeout);
    } on TimeoutException {
      throw Exception('修改短评超时，请稍后重试');
    }

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('修改短评失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<void> deleteMingtaiBookReview(String reviewId) async {
    late final http.Response res;
    try {
      res = await http
          .delete(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/mingtai/reviews/$reviewId',
            ),
            headers: _authHeaders(),
          )
          .timeout(_mingtaiTimeout);
    } on TimeoutException {
      throw Exception('删除短评超时，请稍后重试');
    }

    if (res.statusCode == 200) return;
    throw Exception('删除短评失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> getMingtaiMyProfile() async {
    late final http.Response res;
    try {
      res = await http
          .get(
            Uri.parse('${AppConstants.apiBaseUrl}/api/mingtai/profiles/me'),
            headers: _authHeaders(),
          )
          .timeout(_mingtaiTimeout);
    } on TimeoutException {
      throw Exception('阅读档案加载超时，请稍后重试');
    }

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    if (res.statusCode == 404) {
      return _emptyMingtaiProfile(userId: _userId ?? '', email: _email ?? '');
    }
    throw Exception('读取阅读档案失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> updateMingtaiMyProfile({
    required String nickname,
    required String avatarUrl,
    required String bio,
  }) async {
    late final http.Response res;
    try {
      res = await http
          .put(
            Uri.parse('${AppConstants.apiBaseUrl}/api/mingtai/profiles/me'),
            headers: _authHeaders(),
            body: jsonEncode({
              'nickname': nickname,
              'avatar_url': avatarUrl,
              'bio': bio,
            }),
          )
          .timeout(_mingtaiTimeout);
    } on TimeoutException {
      throw Exception('资料保存超时，请稍后重试');
    }

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('保存阅读档案失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> uploadMingtaiProfileAvatar({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    String nickname = '',
    String bio = '',
  }) async {
    late final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/mingtai/profiles/me/avatar',
            ),
            headers: _authHeaders(),
            body: jsonEncode({
              'file_name': fileName,
              'mime_type': mimeType,
              'image_base64': base64Encode(bytes),
              'nickname': nickname,
              'bio': bio,
            }),
          )
          .timeout(_mingtaiUploadTimeout);
    } on TimeoutException {
      throw Exception('头像上传有点慢，请换一张更小的图片或稍后重试');
    }

    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('头像上传失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> getMingtaiPublicProfile(String userId) async {
    late final http.Response res;
    try {
      res = await http
          .get(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/mingtai/profiles/$userId',
            ),
            headers: _authHeaders(),
          )
          .timeout(_mingtaiTimeout);
    } on TimeoutException {
      throw Exception('公开阅读档案加载超时，请稍后重试');
    }

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    if (res.statusCode == 404) {
      return _emptyMingtaiProfile(userId: userId, email: '');
    }
    throw Exception('读取公开阅读档案失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Map<String, dynamic> _emptyMingtaiProfile({
    required String userId,
    required String email,
  }) {
    final nickname = email.trim().isEmpty
        ? '知读读者'
        : email.trim().split('@').first;
    return {
      'profile': {
        'user_id': userId,
        'nickname': nickname.isEmpty ? '知读读者' : nickname,
        'avatar_url': '',
        'bio': '',
      },
      'stats': {
        'public_books': 0,
        'public_thoughts': 0,
        'public_reviews': 0,
        'mingtai_stops': 0,
      },
      'recent_books': [],
      'reviews': [],
      'annotations': [],
    };
  }

  Future<List<Map<String, dynamic>>> listMingtaiBookChapters(
    String bookId,
  ) async {
    late final http.Response res;
    try {
      res = await http
          .get(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/mingtai/books/$bookId/chapters',
            ),
            headers: _authHeaders(),
          )
          .timeout(_mingtaiTimeout);
    } on TimeoutException {
      throw Exception('明台章节目录加载超时，请稍后重试');
    }

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['chapters'] ?? []);
    }
    throw Exception('读取明台章节目录失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> getMingtaiBookChapter(
    String bookId,
    int chapterIndex,
  ) async {
    late final http.Response res;
    try {
      res = await http
          .get(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/mingtai/books/$bookId/chapters/$chapterIndex',
            ),
            headers: _authHeaders(),
          )
          .timeout(_mingtaiTimeout);
    } on TimeoutException {
      throw Exception('明台章节内容加载超时，请稍后重试');
    }

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return Map<String, dynamic>.from(data['chapter'] ?? {});
    }
    throw Exception('读取明台章节失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> borrowMingtaiBook(String bookId) async {
    late final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/mingtai/books/$bookId/borrow',
            ),
            headers: _authHeaders(),
          )
          .timeout(_mingtaiTimeout);
    } on TimeoutException {
      throw Exception('借阅请求超时，请稍后重试');
    }

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('借阅明台书籍失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<void> recordMingtaiBookRead(String bookId) async {
    try {
      final res = await http
          .post(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/mingtai/books/$bookId/read',
            ),
            headers: _authHeaders(),
          )
          .timeout(_mingtaiTimeout);
      if (res.statusCode == 200) return;
      throw Exception('记录明台阅读失败 (HTTP ${res.statusCode}): ${res.body}');
    } on TimeoutException {
      throw Exception('记录明台阅读超时，请稍后重试');
    }
  }

  Future<Map<String, dynamic>> createMingtaiResonance({
    required String annotationId,
    String content = '',
  }) async {
    late final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/mingtai/annotations/$annotationId/resonance',
            ),
            headers: _authHeaders(),
            body: jsonEncode({'content': content}),
          )
          .timeout(_mingtaiTimeout);
    } on TimeoutException {
      throw Exception('共鸣发送超时，请稍后重试');
    }

    if (res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('发送共鸣失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> createMingtaiBookAnnotation({
    required String bookId,
    required int chapterIndex,
    required String source,
    required String originalText,
    String annotationText = '',
    String chapterTitle = '',
    Map<String, dynamic> positionJson = const {},
  }) async {
    late final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/mingtai/books/$bookId/annotations',
            ),
            headers: _authHeaders(),
            body: jsonEncode({
              'source': source,
              'chapter_index': chapterIndex.toString(),
              'chapter_title': chapterTitle,
              'original_text': originalText,
              'annotation_text': annotationText,
              'position_json': positionJson,
            }),
          )
          .timeout(_mingtaiTimeout);
    } on TimeoutException {
      throw Exception('公开批注发送超时，请稍后重试');
    }

    if (res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('公开批注失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> createMingtaiAnnotationComment({
    required String annotationId,
    required String content,
  }) async {
    late final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/mingtai/annotations/$annotationId/comments',
            ),
            headers: _authHeaders(),
            body: jsonEncode({'content': content}),
          )
          .timeout(_mingtaiTimeout);
    } on TimeoutException {
      throw Exception('评论发送超时，请稍后重试');
    }

    if (res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('发送评论失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>?> saveReadingProgress({
    required String bookId,
    required double progress,
    required String chapterIndex,
    required double scrollOffset,
    String? cfi,
  }) async {
    final res = await http
        .post(
          Uri.parse('${AppConstants.apiBaseUrl}/api/reading-progress'),
          headers: _authHeaders(),
          body: jsonEncode({
            'book_id': bookId,
            'progress': progress,
            'chapter_index': chapterIndex,
            'scroll_offset': scrollOffset,
            if (cfi != null && cfi.isNotEmpty) 'cfi': cfi,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['reading_progress'] as Map<String, dynamic>?;
    }
    throw Exception('保存阅读进度失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>?> getReadingProgress(String bookId) async {
    final res = await http
        .get(
          Uri.parse('${AppConstants.apiBaseUrl}/api/reading-progress/$bookId'),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['reading_progress'] as Map<String, dynamic>?;
    }
    if (res.statusCode == 404) return null;
    throw Exception('查询阅读进度失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  // ---- Internal ----

  Future<void> _saveSession({
    required String token,
    required String userId,
    required String email,
  }) async {
    _token = token;
    _userId = userId;
    _email = email;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_emailKey, email);
  }

  Map<String, String> _authHeaders({String contentType = 'application/json'}) {
    final token = _token?.trim() ?? '';
    return {
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (contentType.isNotEmpty) 'Content-Type': contentType,
    };
  }

  Future<http.Response> _postJsonWithRetry(
    Uri uri,
    Map<String, dynamic> body, {
    int retries = 1,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt += 1) {
      try {
        final res = await http
            .post(
              uri,
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'Connection': 'close',
              },
              body: jsonEncode(body),
            )
            .timeout(_authTimeout);

        if (res.statusCode >= 500 && attempt < retries) {
          await Future<void>.delayed(
            Duration(milliseconds: 450 * (attempt + 1)),
          );
          continue;
        }
        return res;
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }

      if (attempt < retries) {
        await Future<void>.delayed(Duration(milliseconds: 450 * (attempt + 1)));
      }
    }

    throw lastError ?? Exception('请求失败');
  }

  String _publicUrlOrEmpty(String? value) {
    final url = value?.trim() ?? '';
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return '';
  }

  String _fallbackSourceBookId({
    required String filePath,
    required String title,
  }) {
    final seed = filePath.trim().isNotEmpty
        ? filePath.trim()
        : '${title.trim()}:${DateTime.now().millisecondsSinceEpoch}';
    return 'local_${md5.convert(utf8.encode(seed))}';
  }

  String _tryDecodeError(String body, int statusCode) {
    try {
      final err = jsonDecode(body);
      return err['error']?.toString() ?? '请求失败 (HTTP $statusCode)';
    } catch (_) {
      final preview = body.length > 150 ? '${body.substring(0, 150)}...' : body;
      return '服务器返回异常 (HTTP $statusCode): $preview';
    }
  }

  String _friendlyError(dynamic e) {
    final s = e.toString();
    if (s.contains('Connection closed before full header') ||
        s.contains('Software caused connection abort') ||
        s.contains('Connection reset by peer') ||
        s.contains('ClientException') ||
        s.contains('SocketException') ||
        s.contains('HandshakeException')) {
      return '服务器连接被中断，请稍后重试；如果连续出现，请确认后端服务正在运行。';
    }
    if (s.contains('TimeoutException')) {
      return '连接超时，请检查网络或稍后重试。';
    }
    return s.length > 100 ? s.substring(0, 100) : s;
  }
}
