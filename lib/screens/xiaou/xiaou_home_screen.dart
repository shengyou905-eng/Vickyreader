import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/book_service.dart';
import 'topic_screen.dart';
import 'widgets/xiaou_card.dart';
import 'xiaou_chat_screen.dart';

class XiaouHomeScreen extends StatefulWidget {
  final int refreshSignal;
  final bool autoLoad;

  const XiaouHomeScreen({
    super.key,
    this.refreshSignal = 0,
    this.autoLoad = true,
  });

  @override
  State<XiaouHomeScreen> createState() => _XiaouHomeScreenState();
}

class _XiaouHomeScreenState extends State<XiaouHomeScreen> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _allItems = [];
  List<String> _allTags = [];
  Map<int, MingtaiInsight> _insights = {};
  String? _selectedTag;
  int _insightDays = 7;
  bool _loading = true;
  bool _hasLoadedOnce = false;
  bool _refreshing = false;
  bool _loadInFlight = false;
  bool _reloadAfterCurrent = false;
  String? _answeringQuestionId;
  final Set<String> _deletingIds = {};
  final Set<String> _publishingIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant XiaouHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != oldWidget.refreshSignal) {
      _load();
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (_loadInFlight) {
      _reloadAfterCurrent = true;
      return;
    }
    _loadInFlight = true;
    final requestTag = _selectedTag;
    final firstLoad = !_hasLoadedOnce;
    final cached = BookService.cachedMingtaiOverview(tag: requestTag);
    setState(() {
      if (firstLoad && cached != null) {
        _items = cached.items;
        _allItems = cached.allItems;
        _allTags = cached.tags;
        _insights = cached.insights;
        _hasLoadedOnce = true;
      }
      _loading = firstLoad && cached == null;
      _refreshing = !firstLoad || cached != null;
    });
    try {
      final overview = await BookService.getMingtaiOverview(
        tag: requestTag,
        forceRefresh: forceRefresh,
      );
      if (requestTag != _selectedTag) return;
      if (mounted) setState(() {
        _items = overview.items;
        _allItems = overview.allItems;
        _allTags = overview.tags;
        _insights = overview.insights;
        _hasLoadedOnce = true;
        _loading = false;
        _refreshing = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasLoadedOnce = true;
          _loading = false;
          _refreshing = false;
        });
      }
    } finally {
      _loadInFlight = false;
      if (_reloadAfterCurrent && mounted) {
        _reloadAfterCurrent = false;
        _load();
      }
    }
  }

  void _onTagTap(String? tag) {
    if (tag != null && tag.isNotEmpty) {
      _openTopic(tag);
      return;
    }
    setState(() => _selectedTag = _selectedTag == tag ? null : tag);
    _load();
  }

  void _openTopic(String tag) {
    final sourceItems = _allItems.isNotEmpty ? _allItems : _items;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => XiaouTopicScreen(
          tag: tag,
          items: sourceItems,
        ),
      ),
    );
  }

  Future<void> _deleteItem(String id) async {
    if (id.isEmpty || _deletingIds.contains(id)) return;
    setState(() => _deletingIds.add(id));
    try {
      await BookService.deleteMingtaiItem(id);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((item) => item['id'] == id);
        _allItems.removeWhere((item) => item['id'] == id);
        _deletingIds.remove(id);
      });
      await _load(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingIds.remove(id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _publishItem(String id) async {
    if (id.isEmpty || _publishingIds.contains(id)) return;
    setState(() => _publishingIds.add(id));
    try {
      await BookService.publishEntryToMingtai(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已公开到明台'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('公开失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _publishingIds.remove(id));
    }
  }

  Future<void> _askQuestion(_InsightQuestion question) async {
    if (_answeringQuestionId != null) return;
    setState(() => _answeringQuestionId = question.id);
    try {
      final answer = await BookService.answerMingtaiQuestion(question.id);
      if (!mounted) return;
      _showQuestionAnswer(answer);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('生成失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _answeringQuestionId = null);
    }
  }

  void _showQuestionAnswer(MingtaiQuestionAnswer answer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QuestionAnswerSheet(answer: answer),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('小U'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_refreshing)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: _buildContent(),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const XiaouChatScreen()),
          );
        },
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('和小U聊聊'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildEmpty() {
    return SizedBox(
      height: 280,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lightbulb_outline, size: 64, color: AppTheme.primaryLight),
          const SizedBox(height: 16),
          const Text('小U知识中枢',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          const Text('划线、想法和小U解释会自动进入这里', style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final insight = _insights[_insightDays] ?? MingtaiInsight.empty(_insightDays);
    return Column(
      children: [
        _buildInsightCard(insight),
        _buildQuestionCards(),
        const SizedBox(height: 12),
        if (_allTags.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _TagChip(label: '全部', selected: _selectedTag == null, onTap: () => _onTagTap(null)),
                ..._allTags.map((t) => _TagChip(
                  label: t, selected: false, onTap: () => _onTagTap(t),
                )),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [_buildEmpty()],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final item = _items[i];
                      return XiaouCard(
                        originalText: (item['original_text'] as String?) ?? '',
                        userNote: (item['user_note'] as String?) ?? '',
                        aiTags: (item['ai_tags'] as String?) ?? '',
                        aiUnderstanding: (item['ai_understanding'] as String?) ?? '',
                        bookTitle: (item['book_title'] as String?) ?? '',
                        onTagTap: _openTopic,
                        onPublish: _publishingIds.contains((item['id'] as String?) ?? '')
                            ? null
                            : () => _publishItem((item['id'] as String?) ?? ''),
                        onDelete: _deletingIds.contains((item['id'] as String?) ?? '')
                            ? null
                            : () => _deleteItem((item['id'] as String?) ?? ''),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildInsightCard(MingtaiInsight insight) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF8FB), Color(0xFFF1ECFF)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withAlpha(180)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDark.withAlpha(18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppTheme.primaryDark, size: 18),
              const SizedBox(width: 8),
              const Text(
                '最近回顾',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              _InsightRangeSwitch(
                selectedDays: _insightDays,
                onChanged: (days) => setState(() => _insightDays = days),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            insight.summary,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _buildInsightMeta(insight),
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _buildInsightMeta(MingtaiInsight insight) {
    if (insight.entryCount == 0) {
      return '等待新的划线、想法和小U解释';
    }

    final parts = <String>['${insight.entryCount} 条记录'];
    if (insight.topSource.isNotEmpty) {
      parts.add('主要来自${BookService.mingtaiSourceLabel(insight.topSource)}');
    }
    if (insight.topBooks.isNotEmpty) {
      parts.add('《${insight.topBooks.first}》');
    }
    return parts.join(' · ');
  }

  Widget _buildQuestionCards() {
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _insightQuestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final question = _insightQuestions[index];
          final loading = _answeringQuestionId == question.id;
          return _InsightQuestionCard(
            question: question,
            loading: loading,
            onTap: () => _askQuestion(question),
          );
        },
      ),
    );
  }
}

class _InsightQuestion {
  final String id;
  final String title;
  final IconData icon;

  const _InsightQuestion({
    required this.id,
    required this.title,
    required this.icon,
  });
}

const _insightQuestions = [
  _InsightQuestion(
    id: 'recent_focus',
    title: '我最近在关注什么？',
    icon: Icons.lightbulb_outline,
  ),
  _InsightQuestion(
    id: 'freedom_books',
    title: '我在哪些书里反复提到"自由"？',
    icon: Icons.menu_book_outlined,
  ),
  _InsightQuestion(
    id: 'weekly_summary',
    title: '本周阅读摘要',
    icon: Icons.calendar_today_outlined,
  ),
  _InsightQuestion(
    id: 'top_highlight_themes',
    title: '我最常划线的主题',
    icon: Icons.format_quote,
  ),
  _InsightQuestion(
    id: 'touching_recently',
    title: '最近哪些内容最触动我？',
    icon: Icons.favorite_border,
  ),
];

class _InsightQuestionCard extends StatelessWidget {
  final _InsightQuestion question;
  final bool loading;
  final VoidCallback onTap;

  const _InsightQuestionCard({
    required this.question,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: loading ? null : onTap,
      child: Container(
        width: 184,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(230),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.dividerColor.withAlpha(120)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(question.icon, size: 18, color: AppTheme.primary),
                const Spacer(),
                if (loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              question.title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '让小U回看我的记录',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionAnswerSheet extends StatelessWidget {
  final MingtaiQuestionAnswer answer;

  const _QuestionAnswerSheet({required this.answer});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 22,
          right: 22,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 22,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.dividerColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '小U回顾',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                answer.question,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withAlpha(20),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  answer.answer,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    height: 1.65,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('收起'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightRangeSwitch extends StatelessWidget {
  final int selectedDays;
  final ValueChanged<int> onChanged;

  const _InsightRangeSwitch({
    required this.selectedDays,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(130),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(160)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RangeButton(
            label: '7天',
            selected: selectedDays == 7,
            onTap: () => onChanged(7),
          ),
          _RangeButton(
            label: '30天',
            selected: selectedDays == 30,
            onTap: () => onChanged(30),
          ),
        ],
      ),
    );
  }
}

class _RangeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RangeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: selected ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withAlpha(220) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTheme.primaryDark : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TagChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppTheme.textPrimary)),
        selected: selected,
        selectedColor: AppTheme.primary,
        backgroundColor: AppTheme.dividerColor.withAlpha(80),
        onSelected: (_) => onTap(),
      ),
    );
  }
}
