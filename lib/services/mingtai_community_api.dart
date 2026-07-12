import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../models/mingtai_community.dart';
import 'auth_service.dart';

class MingtaiCommunityApi {
  static const Duration _timeout = Duration(seconds: 20);
  static const String _root = '/api/mingtai/community';

  const MingtaiCommunityApi();

  Future<
    ({List<CommunityPost> posts, List<CommunityBook> books, bool requiresAuth})
  >
  getFeed(String tab) async {
    final data = await _get('$_root/feed?tab=$tab&limit=40');
    return (
      posts: _posts(data['posts']),
      books: _books(data['books']),
      requiresAuth: data['requires_auth'] == true,
    );
  }

  Future<({List<CommunityPost> posts, List<CommunityBook> books})> search(
    String query,
  ) async {
    final encoded = Uri.encodeQueryComponent(query.trim());
    final data = await _get('$_root/search?q=$encoded&limit=30');
    return (posts: _posts(data['posts']), books: _books(data['books']));
  }

  Future<CommunityBook> resolveBook({
    required String title,
    required String author,
    String coverUrl = '',
    String description = '',
  }) async {
    final data = await _send(
      'POST',
      '$_root/books/resolve',
      body: {
        'title': title,
        'author': author,
        'cover_url': coverUrl.startsWith('http') ? coverUrl : '',
        'description': description,
      },
      authRequired: true,
    );
    return CommunityBook.fromJson(
      Map<String, dynamic>.from(data['book'] as Map),
    );
  }

  Future<
    ({
      CommunityBook book,
      List<CommunityPost> posts,
      List<CommunityReader> readers,
    })
  >
  getBook(String id) async {
    final data = await _get('$_root/books/$id');
    return (
      book: CommunityBook.fromJson(
        Map<String, dynamic>.from(data['book'] as Map),
      ),
      posts: _posts(data['posts']),
      readers: (data['readers'] as List? ?? const [])
          .map(
            (item) => CommunityReader.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> setBookState(
    String bookId,
    String status, {
    bool isPrivate = false,
  }) async {
    await _send(
      'PUT',
      '$_root/books/$bookId/state',
      body: {'status': status, 'visibility': isPrivate ? 'private' : 'public'},
      authRequired: true,
    );
  }

  Future<CommunityPost> createPost({
    required String bookId,
    required String type,
    required String content,
    String quotedText = '',
    String chapterLabel = '',
  }) async {
    final data = await _send(
      'POST',
      '$_root/posts',
      body: {
        'book_id': bookId,
        'post_type': type,
        'content': content,
        'quoted_text': quotedText,
        'chapter_label': chapterLabel,
      },
      authRequired: true,
    );
    return CommunityPost.fromJson(
      Map<String, dynamic>.from(data['post'] as Map),
    );
  }

  Future<void> deletePost(String postId) async {
    await _send('DELETE', '$_root/posts/$postId', authRequired: true);
  }

  Future<List<CommunityComment>> getComments(String postId) async {
    final data = await _get('$_root/posts/$postId/comments');
    return (data['comments'] as List? ?? const [])
        .map(
          (item) =>
              CommunityComment.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<void> createComment(String postId, String content) async {
    await _send(
      'POST',
      '$_root/posts/$postId/comments',
      body: {'content': content},
      authRequired: true,
    );
  }

  Future<bool> toggleResonance(String postId) async {
    final data = await _send(
      'POST',
      '$_root/posts/$postId/resonance',
      authRequired: true,
    );
    return data['resonated'] == true;
  }

  Future<CommunityProfileData> getProfile(String userId) async {
    final data = await _get('$_root/profiles/$userId');
    return CommunityProfileData.fromJson(data);
  }

  Future<bool> setFollowing(String userId, bool following) async {
    final data = await _send(
      following ? 'POST' : 'DELETE',
      '$_root/profiles/$userId/follow',
      authRequired: true,
    );
    return data['following'] == true;
  }

  Future<List<CommunityNotification>> getNotifications() async {
    final data = await _get(
      '$_root/notifications?limit=60',
      authRequired: true,
    );
    return (data['notifications'] as List? ?? const [])
        .map(
          (item) => CommunityNotification.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> markNotificationsRead() async {
    await _send('PATCH', '$_root/notifications/read-all', authRequired: true);
  }

  Future<Map<String, dynamic>> _get(String path, {bool authRequired = false}) {
    return _send('GET', path, authRequired: authRequired);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authRequired = false,
  }) async {
    await AuthService.init();
    final token = AuthService.token?.trim() ?? '';
    if (authRequired && token.isEmpty) throw Exception('请先登录');
    final uri = Uri.parse('${AppConstants.apiBaseUrl}$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    late http.Response response;
    switch (method) {
      case 'POST':
        response = await http
            .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(_timeout);
        break;
      case 'PUT':
        response = await http
            .put(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(_timeout);
        break;
      case 'PATCH':
        response = await http
            .patch(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(_timeout);
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: headers).timeout(_timeout);
        break;
      default:
        response = await http.get(uri, headers: headers).timeout(_timeout);
        break;
    }
    Map<String, dynamic> data = const {};
    if (response.body.trim().isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message =
          data['error']?.toString() ?? '请求失败 (${response.statusCode})';
      throw Exception(message);
    }
    return data;
  }

  List<CommunityPost> _posts(dynamic value) {
    return (value as List? ?? const [])
        .map(
          (item) =>
              CommunityPost.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  List<CommunityBook> _books(dynamic value) {
    return (value as List? ?? const [])
        .map(
          (item) =>
              CommunityBook.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }
}
