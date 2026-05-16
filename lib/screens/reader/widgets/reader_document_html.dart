import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import '../../../config/reader_paging_mode.dart';
import '../../../models/highlight.dart';
import '../../../providers/settings_provider.dart';

/// WebView reading page: vertical scroll or horizontal multi-column.
class ReaderDocumentHtml {
  ReaderDocumentHtml._();

  static String build({
    required String title,
    required String content,
    required SettingsProvider settings,
    required List<Highlight> highlights,
    required ReaderPagingMode pagingMode,
    List<Map<String, String>> nextChapters = const [],
  }) {
    final bgHex = _colorToHex(settings.backgroundColor);
    final textHex = _colorToHex(settings.textColor);
    final bodyHtml = _injectHighlights(_chapterBodyHtml(content), highlights);
    final safeTitle = _escapeHtml(title);
    final paging = pagingMode.storageValue;
    final nextBuf = StringBuffer();
    for (int i = 0; i < nextChapters.length; i++) {
      final nc = nextChapters[i];
      nextBuf.write('<div class="chapter-section-title" data-chapter="${i + 1}">');
      nextBuf.write('${_escapeHtml(nc['title'] ?? '')}</div>');
      nextBuf.write('<div class="chapter-body">${_chapterBodyHtml(nc['content'] ?? '')}</div>');
    }

    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
  :root {
    --font-size: ${settings.fontSize}px;
    --line-height: ${settings.lineHeight};
    --bg-color: $bgHex;
    --text-color: $textHex;
    --page-pad-x: 18px;
    --page-pad-y: 16px;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body {
    width: 100%; height: 100%;
    background: var(--bg-color);
    color: var(--text-color);
    font-size: var(--font-size);
    line-height: var(--line-height);
    font-family: -apple-system, "Microsoft YaHei", "PingFang SC", sans-serif;
    -webkit-text-size-adjust: 100%;
    -webkit-touch-callout: none;
    -webkit-user-select: text;
    user-select: text;
    overflow: hidden;
  }
  #readSurface {
    width: 100%; height: 100%;
    padding: var(--page-pad-y) var(--page-pad-x) 32px;
    -webkit-overflow-scrolling: touch;
  }
  #readSurface[data-paging="vertical"] {
    overflow-x: hidden;
    overflow-y: auto;
    touch-action: pan-y;
  }
  #readSurface[data-paging="horizontal"] {
    overflow-x: auto;
    overflow-y: hidden;
    touch-action: pan-x;
    column-width: calc(100vw - 2 * var(--page-pad-x));
    column-gap: 28px;
    scroll-snap-type: x proximity;
  }
  .chapter-title {
    font-size: calc(var(--font-size) + 4px);
    font-weight: bold;
    text-align: center;
    margin-bottom: 20px;
    break-after: avoid;
  }
  .chapter-body img { max-width: 100%; height: auto; display: block; margin: 12px auto; border-radius: 4px; }
  .chapter-body h1, .chapter-body h2, .chapter-body h3 { margin: 16px 0 8px; }
  .chapter-body p { margin: 8px 0; text-indent: 2em; }
  .chapter-body blockquote {
    border-left: 3px solid #B39DDB;
    padding-left: 12px;
    margin: 12px 0;
    color: #888;
    font-style: italic;
  }
  ::selection { background-color: rgba(179, 157, 219, 0.35); }
  .ai-reader-highlight { border-radius: 2px; }
  .chapter-section-title {
    font-size: calc(var(--font-size) + 2px);
    font-weight: bold;
    text-align: center;
    margin: 32px 0 16px;
    padding-top: 20px;
    border-top: 1px solid rgba(128,128,128,0.2);
    break-before: column;
  }
</style>
</head>
<body>
  <div id="readSurface" data-paging="$paging">
    <h1 class="chapter-title">$safeTitle</h1>
    <div class="chapter-body">$bodyHtml</div>
    $nextBuf
  </div>
  <script>
    (function() {
      var s = document.getElementById('readSurface');
      var _currentCh = 0; // 0 = current chapter, 1+ = next-chapter offset
      function isHorizontal() {
        return s && s.getAttribute('data-paging') === 'horizontal';
      }
      function postScroll() {
        if (!s) return;
        var v = isHorizontal() ? s.scrollLeft : s.scrollTop;
        FlutterBridge.postMessage('SCROLL|' + v);
      }
      if (s) s.addEventListener('scroll', postScroll, { passive: true });

      // Chapter boundary detection via IntersectionObserver (debounced)
      var _chObserver;
      var _chDebounce;
      function setupChapterObserver() {
        var titles = document.querySelectorAll('.chapter-section-title');
        if (!titles.length) return;
        if (_chObserver) _chObserver.disconnect();
        _chObserver = new IntersectionObserver(function(entries) {
          var latestOffset = _currentCh;
          entries.forEach(function(entry) {
            if (entry.isIntersecting) {
              latestOffset = parseInt(entry.target.getAttribute('data-chapter') || '0');
            }
          });
          if (latestOffset !== _currentCh) {
            clearTimeout(_chDebounce);
            _chDebounce = setTimeout(function() {
              if (latestOffset !== _currentCh) {
                _currentCh = latestOffset;
                FlutterBridge.postMessage('CHAPTER|' + latestOffset);
              }
            }, 300);
          }
        }, { root: s, threshold: 0.5 });
        titles.forEach(function(t) { _chObserver.observe(t); });
      }
      setTimeout(setupChapterObserver, 100);

      // Snap to nearest column on scroll end
      var _snapT;
      if (s) s.addEventListener('scroll', function() {
        if (!isHorizontal()) return;
        clearTimeout(_snapT);
        _snapT = setTimeout(function() {
          var colW = window.innerWidth - 8;
          var nearest = Math.round(s.scrollLeft / colW) * colW;
          if (Math.abs(s.scrollLeft - nearest) > 3) {
            s.scrollTo({left: nearest, behavior: 'auto'});
          }
        }, 150);
      }, { passive: true });

      document.addEventListener('click', function(e) {
        var a = e.target && e.target.closest ? e.target.closest('a') : null;
        if (a) {
          e.preventDefault();
          FlutterBridge.postMessage('NAV|' + (a.getAttribute('href') || ''));
          return;
        }
        var w = window.innerWidth, x = e.clientX;
        if (isHorizontal()) {
          var step = window.innerWidth - 8;
          if (x < w * 0.22) {
            s.scrollLeft = Math.max(0, s.scrollLeft - step);
          } else if (x > w * 0.78) {
            s.scrollLeft = Math.min(s.scrollWidth - s.clientWidth, s.scrollLeft + step);
          } else if (x > w * 0.32 && x < w * 0.68) {
            FlutterBridge.postMessage('TAP|');
          }
        } else {
          if (x > w * 0.32 && x < w * 0.68) FlutterBridge.postMessage('TAP|');
        }
      }, true);

      var t;
      document.addEventListener('selectionchange', function() {
        clearTimeout(t);
        t = setTimeout(function() {
          var sel = window.getSelection();
          var text = sel ? sel.toString().trim() : '';
          if (text) FlutterBridge.postMessage('SELECT|' + text);
        }, 280);
      });

      window.scrollToText = function(text) {
        if (!s || !text) return;
        var wk = document.createTreeWalker(s, NodeFilter.SHOW_TEXT, null, false);
        while (wk.nextNode()) {
          var node = wk.currentNode, i = node.textContent.indexOf(text);
          if (i === -1) continue;
          var r = document.createRange();
          r.setStart(node, i);
          r.setEnd(node, Math.min(i + text.length, node.textContent.length));
          var tr = r.getBoundingClientRect(), sr = s.getBoundingClientRect();
          if (isHorizontal()) {
            s.scrollLeft += (tr.left - sr.left - 24);
          } else {
            s.scrollTop += (tr.top - sr.top - 48);
          }
          var sel = window.getSelection();
          sel.removeAllRanges();
          sel.addRange(r);
          break;
        }
      };

      window.wrapSelection = function(color) {
        var sel = window.getSelection();
        if (!sel || !sel.rangeCount) return;
        var range = sel.getRangeAt(0);
        var span = document.createElement('span');
        span.style.backgroundColor = color;
        span.style.borderRadius = '2px';
        span.className = 'ai-reader-highlight';
        try { range.surroundContents(span); }
        catch (e) {
          span.textContent = range.toString();
          range.deleteContents();
          range.insertNode(span);
        }
        sel.removeAllRanges();
      };

      document.body.addEventListener('error', function(e) {
        if (e.target && e.target.tagName === 'IMG') e.target.style.display = 'none';
      }, true);
    })();
  </script>
</body>
</html>''';
  }

  static String _chapterBodyHtml(String content) {
    final t = content.trim();
    if (t.startsWith(RegExp(r'<!DOCTYPE', caseSensitive: false)) ||
        RegExp(r'<html[\s>]', caseSensitive: false).hasMatch(t)) {
      final doc = html_parser.parse(content);
      // Extract <style> blocks from <head>
      final headStyles = StringBuffer();
      final head = doc.head;
      if (head != null) {
        for (final style in head.querySelectorAll('style')) {
          headStyles.write(style.outerHtml);
        }
      }
      var body = (doc.body?.innerHtml ?? '').trim();
      // Fall back to raw content if body is empty after parsing
      if (body.isEmpty) body = content;
      // Strip leading <h1 class="chapter-title">...</h1> from TXT imports
      final trimmed = body.trimLeft();
      if (trimmed.startsWith('<h1 class="chapter-title">')) {
        final endIdx = body.indexOf('</h1>');
        if (endIdx > 0) body = body.substring(endIdx + 5);
      }
      return '$headStyles$body';
    }
    return content;
  }

  static String _injectHighlights(String html, List<Highlight> highlights) {
    if (highlights.isEmpty) return html;
    var result = html;
    final tagRe = RegExp(r'<[^>]*>');
    for (final h in highlights) {
      final search = h.selectedText;
      if (search.isEmpty) continue;
      final replacement =
          '<span class="ai-reader-highlight" style="background-color:${h.color};border-radius:2px">$search</span>';
      final buf = StringBuffer();
      var pos = 0;
      for (final m in tagRe.allMatches(result)) {
        buf.write(result.substring(pos, m.start).replaceAll(search, replacement));
        buf.write(m.group(0));
        pos = m.end;
      }
      buf.write(result.substring(pos).replaceAll(search, replacement));
      result = buf.toString();
    }
    return result;
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static String _colorToHex(Color color) {
    final r = (color.r * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }
}
