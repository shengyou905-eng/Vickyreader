import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import '../../../config/reader_paging_mode.dart';
import '../../../models/highlight.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/reader_font_service.dart';

class ReaderChapterMarkup {
  final String titleHtml;
  final String bodyHtml;
  final String continuationHtml;

  const ReaderChapterMarkup({
    required this.titleHtml,
    required this.bodyHtml,
    this.continuationHtml = '',
  });

  String get surfaceHtml =>
      '<h1 class="chapter-title">$titleHtml</h1>'
      '<div class="chapter-body">$bodyHtml</div>'
      '$continuationHtml';
}

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
    ReaderChapterMarkup? preparedChapter,
  }) {
    final bgHex = _colorToHex(settings.backgroundColor);
    final textHex = _colorToHex(settings.textColor);
    final chapterMarkup =
        preparedChapter ??
        prepareChapter(
          title: title,
          content: content,
          highlights: highlights,
          nextChapters: nextChapters,
        );
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
    final fontFaceFamily = readerFontAsset?.cssFamily ?? '';
    final fontFaceStyle = readerFontAsset == null
        ? ''
        : '<style id="reader-font-face" '
              'data-family="${_escapeHtml(readerFontAsset.cssFamily)}" '
              'data-url="${_escapeHtml(readerFontAsset.uri)}">'
              '$fontFace</style>';

    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
$fontFaceStyle
<style>
  :root {
    --font-size: ${settings.fontSize}px;
    --line-height: ${settings.lineHeight};
    --reader-font-family: ${settings.readerFontFamily.cssStack};
    --bg-color: $bgHex;
    --text-color: $textHex;
    --page-pad-x: ${settings.pageMargin}px;
    --page-pad-y: 16px;
    /* Updated from #readSurface.clientWidth once WebKit has laid out the page. */
    --reader-viewport-width: 100vw;
    --horizontal-page-step: calc(var(--reader-viewport-width) - 8px);
    --horizontal-column-width: calc(var(--horizontal-page-step) - 28px);
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
    /* Do not use 100vw directly here. On some iOS WKWebView sizes it can
       describe the layout viewport instead of this reading surface. */
    column-width: var(--horizontal-column-width);
    column-gap: 28px;
    column-fill: auto;
    scrollbar-width: none;
  }
  #readSurface[data-paging="horizontal"]::-webkit-scrollbar { display: none; }
  .chapter-title {
    font-family: var(--reader-font-family) !important;
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
    font-family: var(--reader-font-family) !important;
    text-align: justify;
    text-justify: inter-ideograph;
    overflow-wrap: anywhere;
  }
  .chapter-body * {
    font-family: var(--reader-font-family) !important;
    max-width: 100% !important;
    box-sizing: border-box;
  }
  .chapter-body pre,
  .chapter-body pre *,
  .chapter-body code,
  .chapter-body code *,
  .chapter-body kbd,
  .chapter-body samp {
    font-family: ui-monospace, "SFMono-Regular", Consolas, "Liberation Mono", monospace !important;
  }
  .chapter-body img { max-width: 100%; height: auto; display: block; margin: 12px auto; border-radius: 4px; }
  .chapter-body h1, .chapter-body h2, .chapter-body h3 { margin: 16px 0 8px; }
  .chapter-body p, .chapter-body li {
    text-align: justify !important;
    text-justify: inter-ideograph;
    width: auto !important;
    margin-left: 0 !important;
    margin-right: 0 !important;
  }
  .chapter-body div, .chapter-body section, .chapter-body article {
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
  .reader-thought-marker {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    min-width: 20px;
    height: 18px;
    margin-left: 5px;
    padding: 0 4px;
    vertical-align: baseline;
    color: var(--text-color);
    opacity: 0.56;
    background: transparent;
    border: 0;
    border-radius: 9px;
    font: 500 10px/1 -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
    cursor: pointer;
    -webkit-user-select: none;
    user-select: none;
    -webkit-tap-highlight-color: transparent;
    touch-action: manipulation;
  }
  .reader-thought-marker:active { opacity: 0.88; }
  .reader-thought-marker__bubble {
    display: inline-block;
    position: relative;
    width: 13px;
    height: 10px;
    border: 1px solid currentColor;
    border-radius: 5px;
  }
  .reader-thought-marker__bubble::after {
    content: '';
    position: absolute;
    left: 2px;
    bottom: -4px;
    width: 4px;
    height: 4px;
    border-left: 1px solid currentColor;
    border-bottom: 1px solid currentColor;
    transform: skewY(-32deg);
    background: var(--bg-color);
  }
  .chapter-section-title {
    font-family: var(--reader-font-family) !important;
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
    ${chapterMarkup.surfaceHtml}
  </div>
  <script>
    (function() {
      var s = document.getElementById('readSurface');
      window.readerFontFaceFamily = ${jsonEncode(fontFaceFamily)};
${_readerRuntimeScriptTail()}
''';
  }

  static ReaderChapterMarkup prepareChapter({
    required String title,
    required String content,
    required List<Highlight> highlights,
    List<Map<String, String>> nextChapters = const [],
  }) {
    final bodyHtml = _injectHighlights(_chapterBodyHtml(content), highlights);
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
    return ReaderChapterMarkup(
      titleHtml: _escapeHtml(title),
      bodyHtml: bodyHtml,
      continuationHtml: nextBuf.toString(),
    );
  }

  static String buildUpdateScript({
    required ReaderChapterMarkup chapter,
    required int requestId,
    required ReaderPagingMode pagingMode,
    bool scrollToEnd = false,
  }) {
    final payload = jsonEncode({
      'requestId': requestId,
      'surfaceHtml': chapter.surfaceHtml,
      'paging': pagingMode.storageValue,
      'scrollToEnd': scrollToEnd,
    });
    return 'window.readerReplaceChapter && window.readerReplaceChapter($payload);';
  }

  static String _readerRuntimeScriptTail() => '''
      var _currentCh = 0; // 0 = current chapter, 1+ = next-chapter offset
      var _selectionActive = false;
      var _activeAiSelectionMark = null;
      var _aiInteractionLocked = false;
      var _suppressClickUntil = 0;
      function isHorizontal() {
        return s && s.getAttribute('data-paging') === 'horizontal';
      }
      var _readerViewportWidth = 0;
      function syncReadingViewport(preservePosition) {
        if (!s) return 0;
        // WKWebView can retain a smaller layout viewport after a safe-area or
        // orientation change. visualViewport tracks the width the reader is
        // actually painting into on modern iOS.
        var visualWidth = window.visualViewport ? window.visualViewport.width : 0;
        var width = Math.max(
          1,
          Math.round(Math.max(s.clientWidth || 0, visualWidth || 0, window.innerWidth || 0))
        );
        if (width === _readerViewportWidth) return width;
        var ratio = preservePosition && isHorizontal() ? scrollRatio() : null;
        _readerViewportWidth = width;
        document.documentElement.style.setProperty('--reader-viewport-width', width + 'px');
        if (ratio !== null) {
          requestAnimationFrame(function() { window.scrollToRatio && window.scrollToRatio(ratio); });
        }
        return width;
      }
      window.readerSyncViewport = function(preservePosition) {
        return syncReadingViewport(!!preservePosition);
      };
      function hasSelection() {
        var sel = window.getSelection();
        return !!(sel && sel.toString().trim());
      }
      function pageStep() {
        return Math.max(1, syncReadingViewport(false) - 8);
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

      function postPerf(stage, requestId) {
        FlutterBridge.postMessage('PERF|' + stage + '|' + requestId);
      }

      var _readerThoughtMarkers = [];
      function readerParagraphBlocks() {
        if (!s) return [];
        var root = s.querySelector('.chapter-body');
        if (!root) return [];
        var blocks = Array.prototype.slice.call(
          root.querySelectorAll('p, li, blockquote')
        );
        if (!blocks.length) {
          blocks = Array.prototype.slice.call(root.querySelectorAll('div'));
        }
        return blocks.filter(function(block) {
          return (block.textContent || '').replace(/\\s+/g, ' ').trim().length > 0;
        });
      }

      function assignReaderParagraphIndexes() {
        var blocks = readerParagraphBlocks();
        blocks.forEach(function(block, index) {
          block.setAttribute('data-reader-paragraph-index', String(index));
        });
        return blocks;
      }

      function readerBlockForNode(node) {
        var root = s && s.querySelector('.chapter-body');
        var element = node && node.nodeType === Node.ELEMENT_NODE
          ? node
          : (node ? node.parentElement : null);
        while (element && root && element !== root) {
          if (element.hasAttribute('data-reader-paragraph-index')) return element;
          element = element.parentElement;
        }
        return null;
      }

      window.readerSelectionAnchor = function() {
        var selection = window.getSelection();
        if (!selection || !selection.rangeCount || !selection.toString().trim()) {
          return '';
        }
        assignReaderParagraphIndexes();
        var range = selection.getRangeAt(0);
        var block = readerBlockForNode(range.startContainer);
        if (!block) return '';
        return JSON.stringify({
          paragraphIndex: Number(block.getAttribute('data-reader-paragraph-index')),
          paragraphText: (block.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 600)
        });
      };

      window.readerSetThoughtMarkers = function(markers) {
        _readerThoughtMarkers = Array.isArray(markers) ? markers : [];
        assignReaderParagraphIndexes();
        var oldMarkers = s ? s.querySelectorAll('.reader-thought-marker') : [];
        oldMarkers.forEach(function(marker) { marker.remove(); });
        if (!s) return;
        _readerThoughtMarkers.forEach(function(item) {
          var index = Number(item && item.paragraphIndex);
          var count = Number(item && item.count);
          if (!Number.isFinite(index) || !Number.isFinite(count) || count < 1) return;
          var block = s.querySelector('[data-reader-paragraph-index="' + index + '"]');
          if (!block) return;
          var marker = document.createElement('button');
          marker.type = 'button';
          marker.className = 'reader-thought-marker';
          marker.setAttribute('aria-label', count + ' thoughts on this paragraph');
          marker.innerHTML = '<span class="reader-thought-marker__bubble"></span><span>' + count + '</span>';
          marker.addEventListener('click', function(event) {
            event.preventDefault();
            event.stopPropagation();
            _suppressClickUntil = Date.now() + 420;
            FlutterBridge.postMessage('THOUGHT_MARKER|' + index);
          });
          block.appendChild(marker);
        });
      };

      function reportFontAvailable(requestId) {
        var family = window.readerFontFaceFamily || '';
        if (!family || !document.fonts || !document.fonts.load) {
          postPerf('FONT_AVAILABLE', requestId);
          return;
        }
        document.fonts.load('1em "' + family + '"').then(function(faces) {
          postPerf(
            (faces && faces.length) ? 'FONT_AVAILABLE' : 'FONT_FALLBACK',
            requestId
          );
        }, function() {
          postPerf('FONT_FALLBACK', requestId);
        });
      }

      window.readerReportInitialReady = function(requestId) {
        postPerf('HTML_INJECTED', requestId);
        reportFontAvailable(requestId);
        requestAnimationFrame(function() {
          requestAnimationFrame(function() {
            postPerf('BODY_VISIBLE', requestId);
          });
        });
      };

      window.readerReplaceChapter = function(payload) {
        if (!s || !payload) return false;
        releaseAiSelection();
        var selection = window.getSelection();
        if (selection) selection.removeAllRanges();
        _selectionActive = false;
        _aiInteractionLocked = false;
        _currentCh = 0;
        _boundaryUntil = Date.now() + 220;
        if (_chObserver) _chObserver.disconnect();
        clearTimeout(_chDebounce);

        s.setAttribute('data-paging', payload.paging || 'vertical');
        syncReadingViewport(false);
        _readerThoughtMarkers = [];
        s.innerHTML = payload.surfaceHtml || '';
        window.readerSetThoughtMarkers(_readerThoughtMarkers);
        s.scrollLeft = 0;
        s.scrollTop = 0;
        setupChapterObserver();
        postPerf('HTML_INJECTED', payload.requestId);
        reportFontAvailable(payload.requestId);

        requestAnimationFrame(function() {
          if (payload.scrollToEnd) {
            if (isHorizontal()) s.scrollLeft = maxScroll();
            else s.scrollTop = maxScroll();
          }
          requestAnimationFrame(function() {
            postPerf('BODY_VISIBLE', payload.requestId);
          });
        });
        return true;
      };

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

      if (window.ResizeObserver && s) {
        new ResizeObserver(function() { syncReadingViewport(true); }).observe(s);
      } else {
        window.addEventListener('resize', function() { syncReadingViewport(true); });
      }
      if (window.visualViewport) {
        window.visualViewport.addEventListener('resize', function() {
          syncReadingViewport(true);
        });
      }
      syncReadingViewport(false);

      document.addEventListener('click', function(e) {
        if (_aiInteractionLocked) return;
        var thoughtMarker = e.target && e.target.closest
          ? e.target.closest('.reader-thought-marker')
          : null;
        if (thoughtMarker) return;
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

      window.readerSetThoughtMarkers(_readerThoughtMarkers);

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

      window.readerVisibleText = function() {
        if (!s) return '';
        var surfaceRect = s.getBoundingClientRect();
        var root = s.querySelector('.chapter-body') || s;
        var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        var parts = [];
        var total = 0;
        while (walker.nextNode() && total < 7000) {
          var node = walker.currentNode;
          var value = (node.nodeValue || '').replace(/\\s+/g, ' ').trim();
          if (!value) continue;
          var range = document.createRange();
          range.selectNodeContents(node);
          var rects = range.getClientRects();
          var visible = false;
          for (var i = 0; i < rects.length; i++) {
            var rect = rects[i];
            if (rect.right > surfaceRect.left &&
                rect.left < surfaceRect.right &&
                rect.bottom > surfaceRect.top &&
                rect.top < surfaceRect.bottom) {
              visible = true;
              break;
            }
          }
          if (!visible) continue;
          parts.push(value);
          total += value.length;
        }
        return parts.join(' ').slice(0, 7000);
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
