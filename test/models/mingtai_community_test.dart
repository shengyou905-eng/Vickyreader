import 'package:ai_reader/models/mingtai_community.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Mingtai community models', () {
    test('post preserves reader context and favorite state', () {
      final post = CommunityPost.fromJson({
        'id': 'post-1',
        'user_id': 'user-1',
        'book_id': 'book-1',
        'post_type': 'fragment_thought',
        'content': '这里最残酷的地方，是惩罚在死亡之前便开始制造地狱。',
        'quoted_text': '永恒的受难提前开始。',
        'chapter_label': '第一章',
        'reading_position': '0:126.500',
        'reading_progress': '0.28',
        'source': 'reader_selection',
        'source_entry_id': 'entry-1',
        'topic_tags': ['权力', '惩罚'],
        'book_title': '规训与惩罚',
        'book_author': '米歇尔·福柯',
        'book_cover_url': '',
        'nickname': '读者甲',
        'avatar_url': '',
        'comment_count': 2,
        'resonance_count': 0,
        'viewer_resonated': false,
        'favorite_count': 3,
        'viewer_favorited': true,
        'created_at': '2026-07-13T08:00:00Z',
      });

      expect(post.postType, 'fragment_thought');
      expect(post.readingPosition, '0:126.500');
      expect(post.readingProgress, 0.28);
      expect(post.source, 'reader_selection');
      expect(post.topicTags, ['权力', '惩罚']);
      expect(post.favoriteCount, 3);
      expect(post.viewerFavorited, isTrue);
    });

    test('comment preserves quoted reply relationship', () {
      final comment = CommunityComment.fromJson({
        'id': 'reply-2',
        'user_id': 'user-2',
        'nickname': '读者乙',
        'avatar_url': '',
        'content': '我觉得这里还涉及公众如何被纳入权力展示之中。',
        'quoted_text': '刑罚同时也是一种权力表演。',
        'parent_reply_id': 'reply-1',
        'created_at': '2026-07-13T08:10:00Z',
      });

      expect(comment.quotedText, '刑罚同时也是一种权力表演。');
      expect(comment.parentReplyId, 'reply-1');
    });

    test('notification keeps the post and book deep-link ids', () {
      final notification = CommunityNotification.fromJson({
        'id': 'notification-1',
        'event_type': 'post_quote_reply',
        'post_id': 'post-1',
        'book_id': 'book-1',
        'preview': '我有另一种理解。',
        'actor_nickname': '读者乙',
        'actor_avatar_url': '',
        'created_at': '2026-07-13T08:20:00Z',
      });

      expect(notification.eventType, 'post_quote_reply');
      expect(notification.postId, 'post-1');
      expect(notification.bookId, 'book-1');
    });
  });
}
