import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import '../../../config/reader_paging_mode.dart';
import '../../../models/highlight.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/reader_font_service.dart';

/// WebView reading page: vertical scroll or horizontal multi-column.
class ReaderDocumentHtml {
  ReaderDocumentHtml._();

  static String build({
    required String title,
    required String content,
    required SettingsProvider settings,
    required List<Highlight> highlights,
    required ReaderPagingMode pagingMode,
    double topInset = 16,
    double bottomInset = 32,
    List<Map<String, String>> nextChapters = const [],
    ReaderFontAsset? readerFontAsset,
  }) {
    final bgHex = _colorToHex(settings.backgroundColor);
    final textHex = _colorToHex(settings.textColor);
    final bodyHtml = _injectHighlights(_chapterBodyHtml(content), highlights);
    final safeTitle = _escapeHtml(title);
    final paging = pagingMode.storageValue;
    final fontFace = readerFontAsset == null
        ? ''
        : '''
  @font-face {
    font-family: "${_escapeCssString(readerFontAsset.cssFamily)}";
    src: url("${_escapeCssUrl(readerFontAsset.uri)}") format("${_escapeCssString(readerFontAsset.format)}");
    font-weight: 400;
    font-style: normal;
    font-display: swap;
  }
''';
    final nextBuf = StringBuffer();
    for (int i = 0; i < nextChapters.length; i++) {
      final nc = nextChapters[i];
      nextBuf.write(
        '<div class="chapter-section-title" data-chapter="${i + 1}">',
      );
      nextBuf.write('${_escapeHtml(nc['title'] ?? '')}</div>');
      nextBuf.write(
        '<div class="chapter-body">${_chapterBodyHtml(nc['content'] ?? '')}</div>',
      );
    }

    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
$fontFace
  :root {
    --font-size: ${settings.fontSize}px;
    --line-height: ${settings.lineHeight};
    --reader-font-family: ${settings.readerFontFamily.cssStack};
    --bg-color: $bgHex;
    --text-color: $textHex;
    --page-pad-x: ${settings.pageMargin}px;
    --page-pad-y: 16px;
    --reader-top-inset: ${topInset.toStringAsFixed(0)}px;
    --reader-bottom-inset: ${bottomInset.toStringAsFixed(0)}px;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body {
    width: 100%; height: 100%;
    background: var(--bg-color);
    color: var(--text-color);
    font-size: var(--font-size);
    line-height: var(--line-height);
    font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif;
    -webkit-text-size-adjust: 100%;
    -webkit-touch-callout: none;
    -webkit-user-select: text;
    user-select: text;
    overflow: hidden;
  }
  #readSurface {
    width: 100%; height: 100%;
    padding: var(--reader-top-inset) var(--page-pad-x) var(--reader-bottom-inset);
    -webkit-overflow-scrolling: touch;
    overscroll-behavior: contain;
  }
  #readSurface[data-paging="vertical"] {
    overflow-x: hidden;
    overflow-y: auto;
    touch-action: pan-y;
  }
  #readSurface[data-paging="horizontal"] {
    overflow-x: hidden;
    overflow-y: hidden;
    touch-action: pan-y;
    column-width: calc(100vw - 2 * var(--page-pad-x));
    column-gap: 28px;
    scrollbar-width: none;
  }
  #readSurface[data-paging="horizontal"]::-webkit-scrollbar { display: none; }
  .chapter-title {
    font-size: calc(var(--font-size) + 4px);
    font-weight: bold;
    text-align: center;
    line-height: 1.35;
    margin: 0 0 20px;
    break-after: avoid;
  }
  .chapter-body {
    width: 100%;
    max-width: 760px;
    margin: 0 auto;
    font-family: var(--reader-font-family);
    text-align: start;
    overflow-wrap: anywhere;
  }
  .chapter-body * {
    max-width: 100% !important;
    box-sizing: border-box;
  }
  .chapter-body img { max-width: 100%; height: auto; display: block; margin: 12px auto; border-radius: 4px; }
  .chapter-body h1, .chapter-body h2, .chapter-body h3 { margin: 16px 0 8px; }
  .chapter-body p, .chapter-body div, .chapter-body section, .chapter-body article, .chapter-body li {
    text-align: start !important;
    width: auto !important;
    margin-left: 0 !important;
    margin-right: 0 !important;
  }
  .chapter-body p { margin: 8px 0; text-indent: 2em; }
  .chapter-body table {
    width: 100% !important;
    table-layout: auto;
    border-collapse: collapse;
  }
  .chapter-body blockquote {
    border-left: 3px solid #B39DDB;
    padding-left: 12px;
    margin: 12px 0;
    color: #888;
    font-style: italic;
  }
  ::selection { background-color: rgba(179, 157, 219, 0.35); }
  ::highlight(ai-reader-selection) { background-color: rgba(137, 207, 240, 0.34); }
  .ai-reader-highlight { border-radius: 2px; }
  .ai-reader-active-selection {
    background-color: rgba(137, 207, 240, 0.34);
    border-radius: 3px;
    box-decoration-break: clone;
    -webkit-box-decoration-break: clone;
  }
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
      var _selectionActive = false;
      var _activeAiSelectionMark = null;
      var _aiInteractionLocked = false;
      var _suppressClickUntil = 0;
      function isHorizontal() {
        return s && s.getAttribute('data-paging') === 'horizontal';
      }
      function hasSelection() {
        var sel = window.getSelection();
        return !!(sel && sel.toString().trim());
      }
      function pageStep() {
        return window.innerWidth - 8;
      }
      function maxScroll() {
        if (!s) return 0;
        return isHorizontal()
          ? Math.max(0, s.scrollWidth - s.clientWidth)
          : Math.max(0, s.scrollHeight - s.clientHeight);
      }
      function currentScroll() {
        if (!s) return 0;
        return isHorizontal() ? s.scrollLeft : s.scrollTop;
      }
      function scrollRatio() {
        var max = maxScroll();
        if (max <= 0) return 0;
        return Math.max(0, Math.min(1, currentScroll() / max));
      }
      function atStart(edge) {
        return currentScroll() <= (edge || 10);
      }
      function atEnd(edge) {
        return currentScroll() >= maxScroll() - (edge || 10);
      }
      var _boundaryUntil = 0;
      function requestBoundary(direction) {
        if (!s || _aiInteractionLocked || hasSelection() || _selectionActive) return;
        var now = Date.now();
        if (now < _boundaryUntil) return;
        _boundaryUntil = now + 520;
        _suppressClickUntil = now + 260;
        FlutterBridge.postMessage('BOUNDARY|' + direction);
      }
      function scrollPage(direction) {
        if (!s || _aiInteractionLocked || !isHorizontal() || hasSelection() || _selectionActive) return;
        scrollOnePageFrom(s.scrollLeft, direction);
      }
      function scrollOnePageFrom(startScroll, direction) {
        if (!s || !isHorizontal()) return;
        var step = pageStep();
        var base = Math.round(startScroll / step) * step;
        if (direction < 0) {
          if (base <= 12) {
            requestBoundary('prev');
            return;
          }
          s.scrollTo({ left: Math.max(0, base - step), behavior: 'auto' });
        } else {
          if (base >= maxScroll() - 12) {
            requestBoundary('next');
            return;
          }
          s.scrollTo({ left: Math.min(maxScroll(), base + step), behavior: 'auto' });
        }
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
          var colW = pageStep();
          var nearest = Math.round(s.scrollLeft / colW) * colW;
          if (Math.abs(s.scrollLeft - nearest) > 3) {
            s.scrollTo({left: nearest, behavior: 'auto'});
          }
        }, 150);
      }, { passive: true });

      document.addEventListener('click', function(e) {
        if (_aiInteractionLocked) return;
        var a = e.target && e.target.closest ? e.target.closest('a') : null;
        if (a) {
          e.preventDefault();
          FlutterBridge.postMessage('NAV|' + (a.getAttribute('href') || ''));
          return;
        }
        if (Date.now() < _suppressClickUntil) return;
        if (hasSelection() || _selectionActive) return;
        var w = window.innerWidth, x = e.clientX;
        if (isHorizontal() && x < w * 0.30) {
          scrollPage(-1);
        } else if (isHorizontal() && x > w * 0.70) {
          scrollPage(1);
        } else if (x > w * 0.30 && x < w * 0.70) {
          FlutterBridge.postMessage('TAP|');
        }
      }, true);

      var _touchStartX = 0;
      var _touchStartY = 0;
      var _touchStartScroll = 0;
      var _touchStartAt = 0;
      var _horizontalTouch = false;
      var _swipeHandled = false;
      if (s) {
        s.addEventListener('touchstart', function(e) {
          if (!e.touches || !e.touches.length) return;
          _touchStartX = e.touches[0].clientX;
          _touchStartY = e.touches[0].clientY;
          _touchStartScroll = currentScroll();
          _touchStartAt = Date.now();
          _horizontalTouch = false;
          _swipeHandled = false;
        }, { passive: true });

        s.addEventListener('touchmove', function(e) {
          if (!isHorizontal() || !e.touches || !e.touches.length) return;
          if (_aiInteractionLocked || hasSelection() || _selectionActive) return;
          var dx = e.touches[0].clientX - _touchStartX;
          var dy = e.touches[0].clientY - _touchStartY;
          if (_horizontalTouch || (Math.abs(dx) > 14 && Math.abs(dx) > Math.abs(dy) * 1.15)) {
            _horizontalTouch = true;
            e.preventDefault();
          }
        }, { passive: false });

        s.addEventListener('touchend', function(e) {
          if (!e.changedTouches || !e.changedTouches.length) return;
          if (_aiInteractionLocked || hasSelection() || _selectionActive) return;
          if (_swipeHandled) return;
          var dx = e.changedTouches[0].clientX - _touchStartX;
          var dy = e.changedTouches[0].clientY - _touchStartY;
          var elapsed = Date.now() - _touchStartAt;
          if (isHorizontal()) {
            if (elapsed > 900) return;
            if (Math.abs(dx) < 72 || Math.abs(dx) < Math.abs(dy) * 1.35) return;
            _swipeHandled = true;
            scrollOnePageFrom(_touchStartScroll, dx > 0 ? -1 : 1);
            _suppressClickUntil = Date.now() + 180;
            return;
          }
          if (elapsed > 1200) return;
          if (Math.abs(dy) < 118 || Math.abs(dy) < Math.abs(dx) * 1.5) return;
          var startedNearTop = _touchStartScroll <= 18;
          var endedNearTop = atStart(18);
          var startedNearBottom = _touchStartScroll >= maxScroll() - 18;
          var endedNearBottom = atEnd(18);
          if (dy > 0 && (startedNearTop || endedNearTop)) {
            requestBoundary('prev');
          } else if (dy < 0 && (startedNearBottom || endedNearBottom)) {
            requestBoundary('next');
          }
        }, { passive: false });

        s.addEventListener('wheel', function(e) {
          if (_aiInteractionLocked || hasSelection() || _selectionActive) return;
          if (isHorizontal()) return;
          if (Math.abs(e.deltaY) < 72) return;
          if (e.deltaY < 0 && atStart(8)) {
            requestBoundary('prev');
          } else if (e.deltaY > 0 && atEnd(8)) {
            requestBoundary('next');
          }
        }, { passive: true });
      }

      var t;
      document.addEventListener('selectionchange', function() {
        if (_aiInteractionLocked) return;
        clearTimeout(t);
        t = setTimeout(function() {
          var sel = window.getSelection();
          var text = sel ? sel.toString().trim() : '';
          _selectionActive = !!text;
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

      window.scrollToAnchor = function(anchor) {
        if (!s || !anchor) return;
        var id = anchor;
        try { id = decodeURIComponent(anchor); } catch (e) {}
        var target = document.getElementById(id);
        if (!target && window.CSS && CSS.escape) {
          target = document.querySelector('[name="' + CSS.escape(id) + '"]');
        }
        if (!target) return;
        var tr = target.getBoundingClientRect(), sr = s.getBoundingClientRect();
        if (isHorizontal()) {
          s.scrollLeft += (tr.left - sr.left - 24);
        } else {
          s.scrollTop += (tr.top - sr.top - 48);
        }
      };

      window.readerPositionRatio = function() {
        return scrollRatio();
      };

      window.scrollToRatio = function(ratio) {
        if (!s) return;
        var r = Math.max(0, Math.min(1, Number(ratio) || 0));
        var target = Math.round(maxScroll() * r);
        if (isHorizontal()) {
          var step = pageStep();
          target = Math.round(target / step) * step;
          s.scrollLeft = Math.max(0, Math.min(maxScroll(), target));
        } else {
          s.scrollTop = Math.max(0, Math.min(maxScroll(), target));
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
        _selectionActive = false;
      };

      function releaseAiSelection() {
        if (window.CSS && CSS.highlights) {
          CSS.highlights.delete('ai-reader-selection');
        }
        var mark = _activeAiSelectionMark;
        if (mark && mark.parentNode) {
          var parent = mark.parentNode;
          while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
          parent.removeChild(mark);
          parent.normalize();
        }
        _activeAiSelectionMark = null;
        _aiInteractionLocked = false;
      }

      window.freezeSelectionForAi = function() {
        var sel = window.getSelection();
        if (!sel || !sel.rangeCount || !sel.toString().trim()) return false;
        releaseAiSelection();
        var range = sel.getRangeAt(0).cloneRange();
        if (window.CSS && CSS.highlights && typeof Highlight !== 'undefined') {
          CSS.highlights.set('ai-reader-selection', new Highlight(range));
        } else {
          var mark = document.createElement('span');
          mark.className = 'ai-reader-active-selection';
          try {
            var fragment = range.extractContents();
            mark.appendChild(fragment);
            range.insertNode(mark);
            _activeAiSelectionMark = mark;
          } catch (e) {}
        }
        sel.removeAllRanges();
        _selectionActive = false;
        _aiInteractionLocked = true;
        return true;
      };

      window.releaseAiSelection = function() {
        releaseAiSelection();
      };

      window.clearSelection = function() {
        var sel = window.getSelection();
        if (sel) sel.removeAllRanges();
        _selectionActive = false;
        releaseAiSelection();
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
      final chapterBody =
          doc.querySelector('#readSurface > .chapter-body') ??
          doc.querySelector('.chapter-body');
      var body = (chapterBody?.innerHtml ?? doc.body?.innerHtml ?? '').trim();
      // Fall back to raw content if body is empty after parsing
      if (body.isEmpty) body = content;
      body = body.replaceAll(
        RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false),
        '',
      );
      // Strip leading <h1 class="chapter-title">...</h1> from TXT imports
      final trimmed = body.trimLeft();
      if (trimmed.startsWith('<h1 class="chapter-title">')) {
        final endIdx = body.indexOf('</h1>');
        if (endIdx > 0) body = body.substring(endIdx + 5);
      }
      return body;
    }
    return content;
  }

  static String _escapeCssUrl(String value) {
    return value
        .replaceAll('\\', '%5C')
        .replaceAll('"', '%22')
        .replaceAll("'", '%27')
        .replaceAll('\n', '')
        .replaceAll('\r', '');
  }

  static String _escapeCssString(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
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
        buf.write(
          result.substring(pos, m.start).replaceAll(search, replacement),
        );
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
    final r = (color.r * 255)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    final g = (color.g * 255)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    final b = (color.b * 255)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    return '#$r$g$b';
  }
}
