import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/book_service.dart';
import 'widgets/mingtai_card.dart';

class MingtaiScreen extends StatefulWidget {
  const MingtaiScreen({super.key});

  @override
  State<MingtaiScreen> createState() => _MingtaiScreenState();
}

class _MingtaiScreenState extends State<MingtaiScreen> {
  List<Map<String, dynamic>> _items = [];
  List<String> _allTags = [];
  String? _selectedTag;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await BookService.getMingtaiItems(tag: _selectedTag);
      final tags = await BookService.getMingtaiTags();
      if (mounted) setState(() {
        _items = items;
        _allTags = tags;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onTagTap(String? tag) {
    setState(() => _selectedTag = _selectedTag == tag ? null : tag);
    _load();
  }

  Future<void> _deleteItem(String id) async {
    await BookService.deleteMingtaiItem(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('明台'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _buildEmpty()
              : _buildContent(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lightbulb_outline, size: 64, color: AppTheme.primaryLight),
          const SizedBox(height: 16),
          const Text('你的 AI 知识中枢',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          const Text('划线、想法和 AI 解释会自动进入这里', style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        // AI Insight card
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF7E57C2), Color(0xFF9575CD)]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white70, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _items.length >= 3
                      ? '最近你摘录了 ${_items.length} 条内容，涉及 ${_allTags.length} 个主题'
                      : '继续阅读，积累你的思想碎片',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        // Tag chips
        if (_allTags.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _TagChip(label: '全部', selected: _selectedTag == null, onTap: () => _onTagTap(null)),
                ..._allTags.map((t) => _TagChip(
                  label: t, selected: _selectedTag == t, onTap: () => _onTagTap(t),
                )),
              ],
            ),
          ),
        const SizedBox(height: 8),
        // Card list
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final item = _items[i];
                return MingtaiCard(
                  originalText: (item['original_text'] as String?) ?? '',
                  userNote: (item['user_note'] as String?) ?? '',
                  aiTags: (item['ai_tags'] as String?) ?? '',
                  aiUnderstanding: (item['ai_understanding'] as String?) ?? '',
                  bookTitle: (item['book_title'] as String?) ?? '',
                  onDelete: () => _deleteItem((item['id'] as String?) ?? ''),
                );
              },
            ),
          ),
        ),
      ],
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
