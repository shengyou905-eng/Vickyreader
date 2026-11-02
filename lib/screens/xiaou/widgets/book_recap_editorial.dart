import 'package:flutter/material.dart';

/// Presentation only. Callers own the revocable data and all evidence actions.
class RecapEditorialStyle {
  final BuildContext context;
  const RecapEditorialStyle(this.context);
  bool get dark => Theme.of(context).brightness == Brightness.dark;
  Color get ink =>
      dark ? Theme.of(context).colorScheme.onSurface : const Color(0xFF292D32);
  Color get muted => dark
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : const Color(0xFF657077);
  Color get link => dark ? const Color(0xFF89CFF0) : const Color(0xFF3E7187);
  Color get purple => dark ? const Color(0xFFD8C6E3) : const Color(0xFF706079);
  Color get line => ink.withValues(alpha: .14);
  TextStyle text(
    double size, {
    bool note = false,
    Color? color,
    double height = 1.85,
  }) => TextStyle(
    fontFamily: note ? 'LXGWWenKaiLite' : 'SourceHanSerifCN',
    fontSize: size,
    height: height,
    letterSpacing: 0,
    fontWeight: FontWeight.w400,
    color: color ?? ink,
  );
  TextStyle label({Color? color}) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
        fontSize: 12,
        height: 1.8,
        letterSpacing: 0,
        color: color ?? muted,
      );
}

class RecapEditorialSection extends StatelessWidget {
  final String number, title, subtitle;
  const RecapEditorialSection({
    super.key,
    required this.number,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) {
    final s = RecapEditorialStyle(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: s.line)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: SizedBox(
                  width: 34,
                  child: Text(number, style: s.text(16, color: s.link)),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: s.text(22, height: 1.5)),
                    ),
                    const SizedBox(height: 5),
                    Text(subtitle, style: s.label()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RecapEditorialQuote extends StatelessWidget {
  final String text, label;
  final bool userVoice, historicalAi;
  const RecapEditorialQuote({
    super.key,
    required this.text,
    required this.label,
    this.userVoice = false,
    this.historicalAi = false,
  });
  @override
  Widget build(BuildContext context) {
    final s = RecapEditorialStyle(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
      decoration: BoxDecoration(
        color: userVoice
            ? (s.dark ? const Color(0xFF302B37) : const Color(0xFFF1F0F4))
            : null,
        border: Border(
          left: BorderSide(
            width: 2,
            color: userVoice
                ? const Color(0xFFB6A9C5)
                : historicalAi
                ? s.muted
                : const Color(0xFF89CFF0),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: s.label(color: userVoice ? s.purple : s.muted)),
          const SizedBox(height: 10),
          Text(text, style: s.text(userVoice ? 19 : 17, note: userVoice)),
          if (historicalAi) ...[
            const SizedBox(height: 10),
            Text('这是讨论记录，不是书籍证据。', style: s.label()),
          ],
        ],
      ),
    );
  }
}
