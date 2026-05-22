import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class BmobApi {
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'auth_user_id';
  static const _emailKey = 'auth_email';

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

  bool get isLoggedIn => _token != null;
  String? get userId => _userId;
  String? get email => _email;
  String? get token => _token;

  // ---- Auth ----

  Future<Map<String, dynamic>?> signUp(String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 15));

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
      final res = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 15));

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

    final uri = Uri.parse('${AppConstants.apiBaseUrl}/api/classes/$table')
        .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    final res = await http
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['results'] ?? []);
    }
    throw Exception('查询失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>?> create(String table, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/api/classes/$table'),
      headers: _authHeaders(),
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('创建失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<bool> update(String table, String objectId, Map<String, dynamic> body) async {
    final res = await http.put(
      Uri.parse('${AppConstants.apiBaseUrl}/api/classes/$table/$objectId'),
      headers: _authHeaders(),
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return true;
    throw Exception('更新失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<bool> delete(String table, String objectId) async {
    final res = await http.delete(
      Uri.parse('${AppConstants.apiBaseUrl}/api/classes/$table/$objectId'),
      headers: _authHeaders(),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return true;
    throw Exception('删除失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>?> createUserEntry(Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/api/entries'),
      headers: _authHeaders(),
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 10));
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

    final uri = Uri.parse('${AppConstants.apiBaseUrl}/api/entries')
        .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

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
      final res = await http.delete(
        Uri.parse('${AppConstants.apiBaseUrl}/api/entries/$id'),
        headers: _authHeaders(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 204) return true;
      if (res.statusCode == 404) return false;
      throw Exception('删除 user_entry 失败 (HTTP ${res.statusCode}): ${res.body}');
    } on TimeoutException {
      throw Exception('删除接口超时：请确认线上后端已部署 DELETE /api/entries/:id');
    }
  }

  Future<Map<String, dynamic>> answerInsightQuestion(String questionId) async {
    final res = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/api/insights/questions/$questionId/answer'),
      headers: _authHeaders(),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('生成小U回答失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<List<Map<String, dynamic>>> publishMingtaiAnnotations(
    List<String> entryIds,
  ) async {
    final res = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/api/mingtai/publish'),
      headers: _authHeaders(),
      body: jsonEncode({'entry_ids': entryIds}),
    ).timeout(const Duration(seconds: 10));

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
    String? author,
    String? coverUrl,
    String? description,
    List<String> entryIds = const [],
  }) async {
    final res = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/api/mingtai/publish-book'),
      headers: _authHeaders(),
      body: jsonEncode({
        'source_book_id': sourceBookId,
        'title': title,
        'author': author ?? '',
        'cover_url': coverUrl ?? '',
        'description': description ?? '',
        'copyright_status': copyrightStatus,
        'entry_ids': entryIds,
      }),
    ).timeout(const Duration(seconds: 12));

    if (res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('发布书籍到明台失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<List<Map<String, dynamic>>> listMingtaiBooks({int limit = 50}) async {
    final uri = Uri.parse('${AppConstants.apiBaseUrl}/api/mingtai/books')
        .replace(queryParameters: {'limit': limit.toString()});
    final res = await http
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 8));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['books'] ?? []);
    }
    throw Exception('读取明台书库失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> getMingtaiBook(String bookId) async {
    final res = await http
        .get(
          Uri.parse('${AppConstants.apiBaseUrl}/api/mingtai/books/$bookId'),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('读取明台书籍失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> borrowMingtaiBook(String bookId) async {
    final res = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/api/mingtai/books/$bookId/borrow'),
      headers: _authHeaders(),
    ).timeout(const Duration(seconds: 8));

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('借阅明台书籍失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>> createMingtaiResonance({
    required String annotationId,
    required String content,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/api/mingtai/annotations/$annotationId/resonances'),
      headers: _authHeaders(),
      body: jsonEncode({'content': content}),
    ).timeout(const Duration(seconds: 8));

    if (res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('发送共鸣失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<List<Map<String, dynamic>>> listMingtaiFeed({int limit = 50}) async {
    final uri = Uri.parse('${AppConstants.apiBaseUrl}/api/mingtai/feed')
        .replace(queryParameters: {'limit': limit.toString()});

    debugPrint('[MingtaiFeed] GET $uri');
    try {
      final res = await http
          .get(uri, headers: _authHeaders())
          .timeout(const Duration(seconds: 8));

      debugPrint('[MingtaiFeed] statusCode=${res.statusCode}');
      debugPrint('[MingtaiFeed] response.body=${res.body}');

      Map<String, dynamic> data;
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[MingtaiFeed] parsed json error=$e');
        throw Exception('明台返回不是 JSON (HTTP ${res.statusCode})');
      }

      debugPrint('[MingtaiFeed] parsed json=${jsonEncode(data)}');

      if (res.statusCode == 200) {
        final annotations = data['annotations'];
        if (annotations is List) {
          debugPrint('[MingtaiFeed] annotations.length=${annotations.length}');
          return List<Map<String, dynamic>>.from(annotations);
        }
        debugPrint('[MingtaiFeed] annotations missing or not list, fallback=[]');
        return [];
      }

      throw Exception(
        data['error']?.toString() ??
            '读取明台失败 (HTTP ${res.statusCode}): ${res.body}',
      );
    } on TimeoutException catch (e) {
      debugPrint('[MingtaiFeed] timeout=$e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> saveReadingProgress({
    required String bookId,
    required double progress,
    required String chapterIndex,
    required double scrollOffset,
    String? cfi,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/api/reading-progress'),
      headers: _authHeaders(),
      body: jsonEncode({
        'book_id': bookId,
        'progress': progress,
        'chapter_index': chapterIndex,
        'scroll_offset': scrollOffset,
        if (cfi != null && cfi.isNotEmpty) 'cfi': cfi,
      }),
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['reading_progress'] as Map<String, dynamic>?;
    }
    throw Exception('保存阅读进度失败 (HTTP ${res.statusCode}): ${res.body}');
  }

  Future<Map<String, dynamic>?> getReadingProgress(String bookId) async {
    final res = await http.get(
      Uri.parse('${AppConstants.apiBaseUrl}/api/reading-progress/$bookId'),
      headers: _authHeaders(),
    ).timeout(const Duration(seconds: 10));

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

  Map<String, String> _authHeaders() => {
    if (_token != null) 'Authorization': 'Bearer $_token',
    'Content-Type': 'application/json',
  };

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
    if (s.contains('HandshakeException') || s.contains('SocketException')) {
      return '无法连接服务器：${s.length > 80 ? s.substring(0, 80) : s}';
    }
    if (s.contains('TimeoutException')) {
      return '连接超时，请检查网络';
    }
    return s.length > 100 ? s.substring(0, 100) : s;
  }
}
