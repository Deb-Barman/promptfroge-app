import 'dart:convert';

import 'package:xml/xml.dart';

import '../../core/constants.dart';
import '../../core/util.dart';
import 'engine_util.dart';
import 'template_engine.dart';

class Section {
  final String label;
  final String content;
  const Section(this.label, this.content);
}

/// Converts between text / markdown / json / xml via an intermediate list of sections.
class FormatConverter {
  FormatConverter._();

  static List<Section> _fromText(String? text) {
    final raw = text ?? '';
    final names = kBlockTypes.map((b) => RegExp.escape(b.label)).join('|');
    final re = RegExp('^($names)\\s*:\\s*\\n?', multiLine: true);
    final sections = <Section>[];
    var last = 0;
    String? pendingLabel;
    var first = true;
    for (final m in re.allMatches(raw)) {
      final chunk = raw.substring(last, m.start);
      if (first) {
        if (chunk.trim().isNotEmpty) sections.add(Section('Notes', chunk.trim()));
        first = false;
      } else if (pendingLabel != null) {
        sections.add(Section(pendingLabel, chunk.trim()));
      }
      pendingLabel = m.group(1);
      last = m.end;
    }
    if (pendingLabel != null) {
      sections.add(Section(pendingLabel, raw.substring(last).trim()));
    } else if (first) {
      // no headers at all
      if (raw.trim().isNotEmpty) sections.add(Section('Notes', raw.trim()));
    }
    return sections.isEmpty ? [Section('Notes', raw.trim())] : sections;
  }

  static List<Section> _fromMarkdown(String? text) {
    final raw = text ?? '';
    final lines = raw.split('\n');
    final sections = <_MutSection>[];
    _MutSection? current;
    final header = RegExp(r'^#{1,3}\s+(.+)');
    for (final line in lines) {
      final m = header.firstMatch(line);
      if (m != null) {
        if (current != null) sections.add(current);
        current = _MutSection(m.group(1)!.trim(), '');
      } else if (current != null) {
        current.content += (current.content.isNotEmpty ? '\n' : '') + line;
      } else if (line.trim().isNotEmpty) {
        if (sections.isEmpty || sections.last.label != 'Notes') {
          sections.add(_MutSection('Notes', line));
        } else {
          sections.last.content += '\n$line';
        }
      }
    }
    if (current != null) sections.add(current);
    final out = sections.map((s) => Section(s.label, s.content.trim())).toList();
    return out.isEmpty ? [Section('Notes', raw.trim())] : out;
  }

  static List<Section> _fromJson(String? text) {
    try {
      final obj = jsonDecode((text == null || text.isEmpty) ? '{}' : text);
      if (obj is! Map) return [Section('Notes', (text ?? '').trim())];
      return obj.entries
          .map((e) => Section(TemplateEngine.humanizeVarName(e.key.toString()), e.value is String ? e.value as String : jsonStringify(e.value, indent: 2)))
          .toList();
    } catch (_) {
      return [Section('Notes', (text ?? '').trim())];
    }
  }

  static List<Section> _fromXml(String? text) {
    try {
      final doc = XmlDocument.parse((text == null || text.isEmpty) ? '<root></root>' : text);
      final root = doc.rootElement;
      final sections = <Section>[];
      for (final child in root.childElements) {
        sections.add(Section(TemplateEngine.humanizeVarName(child.name.local), child.innerText.trim()));
      }
      if (sections.isEmpty && root.innerText.trim().isNotEmpty) {
        sections.add(Section(TemplateEngine.humanizeVarName(root.name.local), root.innerText.trim()));
      }
      return sections.isEmpty ? [Section('Notes', (text ?? '').trim())] : sections;
    } catch (_) {
      return [Section('Notes', (text ?? '').trim())];
    }
  }

  static List<Section> extractSections(String? text, String fromFormat) {
    switch (fromFormat) {
      case 'json':
        return _fromJson(text);
      case 'xml':
        return _fromXml(text);
      case 'markdown':
        return _fromMarkdown(text);
      default:
        return _fromText(text);
    }
  }

  static String slugify(String label) {
    final v = label.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return v.isEmpty ? 'field' : v;
  }

  static String toText(List<Section> s) => s.map((x) => '${x.label}:\n${x.content}').join('\n\n');
  static String toMarkdown(List<Section> s) => s.map((x) => '## ${x.label}\n${x.content}').join('\n\n');
  static String toJson(List<Section> s) {
    final obj = <String, String>{};
    for (final x in s) {
      obj[slugify(x.label)] = x.content;
    }
    return jsonStringify(obj, indent: 2);
  }

  static String toXml(List<Section> s) {
    final body = s.map((x) {
      final tag = slugify(x.label);
      return '  <$tag>${Utils.escapeHtml(x.content)}</$tag>';
    }).join('\n');
    return '<prompt>\n$body\n</prompt>';
  }

  static String convert(String? text, String fromFormat, String toFormat) {
    if (fromFormat == toFormat) return text ?? '';
    final sections = extractSections(text, fromFormat);
    switch (toFormat) {
      case 'json':
        return toJson(sections);
      case 'xml':
        return toXml(sections);
      case 'markdown':
        return toMarkdown(sections);
      default:
        return toText(sections);
    }
  }
}

class _MutSection {
  final String label;
  String content;
  _MutSection(this.label, this.content);
}
