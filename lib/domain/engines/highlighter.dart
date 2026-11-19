import 'package:flutter/painting.dart';

import '../../core/constants.dart';

/// Colour set for the editor highlighter (values taken from the original CSS theme variables).
class HighlightColors {
  final Color header,
      variable,
      comment,
      constraint,
      key,
      string,
      number,
      keyword,
      punct,
      tag,
      attr,
      attrValue,
      mdHeader,
      mdCode,
      mdQuote,
      mdList,
      mdBold,
      mdLink;

  const HighlightColors.dark()
      : header = const Color(0xFFE8A33D),
        variable = const Color(0xFF5B8DEF),
        comment = const Color(0xFF454B56),
        constraint = const Color(0xFFE55A5A),
        key = const Color(0xFF5B8DEF),
        string = const Color(0xFF4FAE7A),
        number = const Color(0xFFE8A33D),
        keyword = const Color(0xFF9B7FE0),
        punct = const Color(0xFF6B7280),
        tag = const Color(0xFF5B8DEF),
        attr = const Color(0xFFE8A33D),
        attrValue = const Color(0xFF4FAE7A),
        mdHeader = const Color(0xFFE8A33D),
        mdCode = const Color(0xFF4FAE7A),
        mdQuote = const Color(0xFF6B7280),
        mdList = const Color(0xFF5B8DEF),
        mdBold = const Color(0xFFE7EAEE),
        mdLink = const Color(0xFF5B8DEF);

  const HighlightColors.light()
      : header = const Color(0xFFE8A33D),
        variable = const Color(0xFF5B8DEF),
        comment = const Color(0xFFB7BCC5),
        constraint = const Color(0xFFE55A5A),
        key = const Color(0xFF5B8DEF),
        string = const Color(0xFF4FAE7A),
        number = const Color(0xFFE8A33D),
        keyword = const Color(0xFF9B7FE0),
        punct = const Color(0xFF868D99),
        tag = const Color(0xFF5B8DEF),
        attr = const Color(0xFFE8A33D),
        attrValue = const Color(0xFF4FAE7A),
        mdHeader = const Color(0xFFE8A33D),
        mdCode = const Color(0xFF4FAE7A),
        mdQuote = const Color(0xFF868D99),
        mdList = const Color(0xFF5B8DEF),
        mdBold = const Color(0xFF1A1D23),
        mdLink = const Color(0xFF5B8DEF);
}

// Token classes (per character).
const int _kNone = 0;
const int _kHeader = 1;
const int _kVar = 2;
const int _kComment = 3;
const int _kConstraint = 4;
const int _kKey = 5;
const int _kString = 6;
const int _kNumber = 7;
const int _kKeyword = 8;
const int _kPunct = 9;
const int _kTag = 10;
const int _kAttr = 11;
const int _kAttrVal = 12;
const int _kMdHeader = 13;
const int _kMdCode = 14;
const int _kMdQuote = 15;
const int _kMdList = 16;
const int _kMdBold = 17;
const int _kMdItalic = 18;
const int _kMdLink = 19;
const int _kMdFence = 20;

/// Single-pass-style tokenisers (text, json, xml, markdown). Each tokeniser labels every
/// character of the input with a token class, then equal neighbours are merged into spans,
/// so the concatenated span text always equals the input exactly.
class PromptHighlighter {
  PromptHighlighter._();

  static TextSpan build(String text, String format, TextStyle base, HighlightColors colors) {
    if (text.isEmpty) return TextSpan(text: '', style: base);
    List<int> kinds;
    switch (format) {
      case 'json':
        kinds = _jsonKinds(text);
        break;
      case 'xml':
        kinds = _xmlKinds(text);
        break;
      case 'markdown':
        kinds = _markdownKinds(text);
        break;
      default:
        kinds = _textKinds(text);
        break;
    }
    final children = <InlineSpan>[];
    var start = 0;
    for (var i = 1; i <= text.length; i++) {
      if (i == text.length || kinds[i] != kinds[start]) {
        final chunk = text.substring(start, i);
        final style = _styleFor(kinds[start], colors);
        children.add(TextSpan(text: chunk, style: style));
        start = i;
      }
    }
    return TextSpan(style: base, children: children);
  }

  static TextStyle? _styleFor(int kind, HighlightColors c) {
    switch (kind) {
      case _kHeader:
        return TextStyle(color: c.header, fontWeight: FontWeight.w700);
      case _kVar:
        return TextStyle(color: c.variable, fontWeight: FontWeight.w600);
      case _kComment:
        return TextStyle(color: c.comment, fontStyle: FontStyle.italic);
      case _kConstraint:
        return TextStyle(color: c.constraint);
      case _kKey:
        return TextStyle(color: c.key, fontWeight: FontWeight.w600);
      case _kString:
        return TextStyle(color: c.string);
      case _kNumber:
        return TextStyle(color: c.number);
      case _kKeyword:
        return TextStyle(color: c.keyword, fontWeight: FontWeight.w600);
      case _kPunct:
        return TextStyle(color: c.punct);
      case _kTag:
        return TextStyle(color: c.tag, fontWeight: FontWeight.w600);
      case _kAttr:
        return TextStyle(color: c.attr);
      case _kAttrVal:
        return TextStyle(color: c.attrValue);
      case _kMdHeader:
        return TextStyle(color: c.mdHeader, fontWeight: FontWeight.w700);
      case _kMdCode:
        return TextStyle(color: c.mdCode);
      case _kMdQuote:
        return TextStyle(color: c.mdQuote, fontStyle: FontStyle.italic);
      case _kMdList:
        return TextStyle(color: c.mdList, fontWeight: FontWeight.w700);
      case _kMdBold:
        return TextStyle(color: c.mdBold, fontWeight: FontWeight.w700);
      case _kMdItalic:
        return TextStyle(color: c.mdBold, fontStyle: FontStyle.italic);
      case _kMdLink:
        return TextStyle(color: c.mdLink, decoration: TextDecoration.underline);
      case _kMdFence:
        return TextStyle(color: c.punct);
      default:
        return null;
    }
  }

  static void _fill(List<int> kinds, int from, int to, int kind) {
    for (var i = from; i < to && i < kinds.length; i++) {
      kinds[i] = kind;
    }
  }

  // ------------------------------------------------------------------ text

  static final RegExp _commentRe = RegExp(r'^(\s*#.*)$', multiLine: true);
  static final RegExp _varRe = RegExp(r'\{\{\s*[a-zA-Z0-9_]+\s*\}\}');
  static final RegExp _constraintRe = RegExp(r'\b(must not|never|do not|forbidden|avoid|no more than|at least|only use|shall not)\b', caseSensitive: false);

  static List<int> _textKinds(String text) {
    final kinds = List<int>.filled(text.length, _kNone);
    final headerNames = kBlockTypes.map((b) => b.label).join('|');
    final headerRe = RegExp('^(\\s*)($headerNames)(:)', multiLine: true);

    // Original order: comment, header, variable, constraint; later spans nest inside earlier
    // ones, so the later class wins on overlapping characters.
    final commentLines = <int>[];
    for (final m in _commentRe.allMatches(text)) {
      _fill(kinds, m.start, m.end, _kComment);
      commentLines.add(m.start);
    }
    for (final m in headerRe.allMatches(text)) {
      final s = m.start + m.group(1)!.length;
      // The original wraps the header after comment spans exist, so a header inside a comment line never matched.
      if (kinds.isNotEmpty && s < kinds.length && kinds[s] == _kComment) continue;
      _fill(kinds, s, m.end, _kHeader);
    }
    for (final m in _varRe.allMatches(text)) {
      _fill(kinds, m.start, m.end, _kVar);
    }
    for (final m in _constraintRe.allMatches(text)) {
      _fill(kinds, m.start, m.end, _kConstraint);
    }
    return kinds;
  }

  // ------------------------------------------------------------------ json

  static final RegExp _jsonNumber = RegExp(r'-?\d+\.?\d*(?:[eE][+-]?\d+)?');
  static final RegExp _jsonKeyword = RegExp(r'(true|false|null)\b');
  static final RegExp _wsChar = RegExp(r'\s');

  static List<int> _jsonKinds(String raw) {
    final n = raw.length;
    final kinds = List<int>.filled(n, _kNone);
    var i = 0;
    while (i < n) {
      final c = raw[i];
      if (c == '"') {
        var j = i + 1;
        while (j < n && raw[j] != '"') {
          if (raw[j] == '\\') j++;
          j++;
        }
        j = j + 1 < n ? j + 1 : n;
        var k = j;
        while (k < n && _wsChar.hasMatch(raw[k])) {
          k++;
        }
        final isKey = k < n && raw[k] == ':';
        _fill(kinds, i, j, isKey ? _kKey : _kString);
        i = j;
      } else if (c == '{' || c == '}' || c == '[' || c == ']' || c == ',' || c == ':') {
        kinds[i] = _kPunct;
        i++;
      } else if (c == '-' || (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57)) {
        final m = _jsonNumber.matchAsPrefix(raw, i);
        if (m != null && m.end > i) {
          _fill(kinds, i, m.end, _kNumber);
          i = m.end;
        } else {
          i++;
        }
      } else if (RegExp(r'[a-zA-Z]').hasMatch(c)) {
        final m = _jsonKeyword.matchAsPrefix(raw, i);
        if (m != null) {
          _fill(kinds, i, m.end, _kKeyword);
          i = m.end;
        } else {
          i++;
        }
      } else {
        i++;
      }
    }
    return kinds;
  }

  // ------------------------------------------------------------------- xml

  static final RegExp _xmlName = RegExp(r'<\/?\s*([a-zA-Z_][\w:.-]*)');
  static final RegExp _xmlAttr = RegExp('([a-zA-Z_][\\w:.-]*)(\\s*=\\s*)("[^"]*"|\'[^\']*\')');

  static List<int> _xmlKinds(String raw) {
    final n = raw.length;
    final kinds = List<int>.filled(n, _kNone);
    var i = 0;
    while (i < n) {
      if (raw.startsWith('<!--', i)) {
        var end = raw.indexOf('-->', i);
        end = end == -1 ? n : end + 3;
        _fill(kinds, i, end, _kComment);
        i = end;
        continue;
      }
      if (raw[i] == '<') {
        var end = raw.indexOf('>', i);
        end = end == -1 ? n : end + 1;
        final tag = raw.substring(i, end);
        final isSelfClose = tag.endsWith('/>');
        final nameMatch = _xmlName.firstMatch(tag);
        if (nameMatch != null && nameMatch.start == 0) {
          final nameGroupStart = nameMatch.start + nameMatch.group(0)!.length - nameMatch.group(1)!.length;
          _fill(kinds, i + nameGroupStart, i + nameMatch.end, _kTag);
          final afterName = nameMatch.end;
          final trailingLen = isSelfClose ? 2 : (tag.endsWith('>') ? 1 : 0);
          final regionEnd = tag.length - trailingLen;
          if (regionEnd > afterName) {
            final region = tag.substring(afterName, regionEnd);
            for (final am in _xmlAttr.allMatches(region)) {
              final nameStart = i + afterName + am.start;
              final nameLen = am.group(1)!.length;
              _fill(kinds, nameStart, nameStart + nameLen, _kAttr);
              final valStart = nameStart + nameLen + am.group(2)!.length;
              _fill(kinds, valStart, valStart + am.group(3)!.length, _kAttrVal);
            }
          }
        }
        i = end;
        continue;
      }
      var next = raw.indexOf('<', i);
      next = next == -1 ? n : next;
      if (next == i) next = i + 1;
      i = next;
    }
    return kinds;
  }

  // -------------------------------------------------------------- markdown

  static final RegExp _mdFence = RegExp(r'^```');
  static final RegExp _mdHeaderRe = RegExp(r'^#{1,6}\s');
  static final RegExp _mdQuoteRe = RegExp(r'^>\s?');
  static final RegExp _mdListRe = RegExp(r'^(\s*)([-*+]|\d+\.)(\s)');
  static final RegExp _mdCodeRe = RegExp(r'`([^`]+)`');
  static final RegExp _mdBoldRe = RegExp(r'\*\*([^*]+)\*\*');
  static final RegExp _mdItalicRe = RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)');
  static final RegExp _mdLinkRe = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');

  static List<int> _markdownKinds(String raw) {
    final kinds = List<int>.filled(raw.length, _kNone);
    var inFence = false;
    var offset = 0;
    for (final line in raw.split('\n')) {
      final end = offset + line.length;
      if (_mdFence.hasMatch(line)) {
        inFence = !inFence;
        _fill(kinds, offset, end, _kMdFence);
      } else if (inFence) {
        _fill(kinds, offset, end, _kMdCode);
      } else if (_mdHeaderRe.hasMatch(line)) {
        _fill(kinds, offset, end, _kMdHeader);
      } else if (_mdQuoteRe.hasMatch(line)) {
        _fill(kinds, offset, end, _kMdQuote);
      } else {
        // Original applies list, code, bold, italic, link in that order and each later
        // wrapper ends up outside the earlier ones, so earlier classes win on overlap.
        for (final m in _mdLinkRe.allMatches(line)) {
          _fill(kinds, offset + m.start, offset + m.end, _kMdLink);
        }
        for (final m in _mdItalicRe.allMatches(line)) {
          _fill(kinds, offset + m.start, offset + m.end, _kMdItalic);
        }
        for (final m in _mdBoldRe.allMatches(line)) {
          _fill(kinds, offset + m.start, offset + m.end, _kMdBold);
        }
        for (final m in _mdCodeRe.allMatches(line)) {
          _fill(kinds, offset + m.start, offset + m.end, _kMdCode);
        }
        final lm = _mdListRe.firstMatch(line);
        if (lm != null) {
          final s = offset + lm.group(1)!.length;
          _fill(kinds, s, s + lm.group(2)!.length, _kMdList);
        }
      }
      offset = end + 1; // + the '\n' separator
    }
    return kinds;
  }
}
