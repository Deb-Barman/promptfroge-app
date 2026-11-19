import 'dart:convert';

/// Minimal YAML-frontmatter reader/writer (Obsidian-compatible subset).
///
/// Written form: one `key: <JSON value>` line per field. JSON scalars, arrays and
/// objects on one line are valid YAML flow syntax, so Obsidian and other tools can
/// read the files. When reading, hand-edited files are tolerated too:
///   key: plain text
///   key: [a, b]            (flow list of bare words)
///   key:
///     - a
///     - b
class ParsedNote {
  final Map<String, dynamic> meta;
  final String body;
  const ParsedNote(this.meta, this.body);
}

class Frontmatter {
  Frontmatter._();

  static String serialize(Map<String, dynamic> meta, String body) {
    final sb = StringBuffer('---\n');
    meta.forEach((k, v) {
      sb.write('$k: ${jsonEncode(v)}\n');
    });
    sb.write('---\n');
    sb.write(body);
    sb.write('\n'); // always exactly one trailing newline so parse() is lossless
    return sb.toString();
  }

  static ParsedNote parse(String content) {
    final text = content.replaceAll('\r\n', '\n');
    if (!text.startsWith('---\n')) return ParsedNote(<String, dynamic>{}, text);
    final end = text.indexOf('\n---', 4);
    if (end == -1) return ParsedNote(<String, dynamic>{}, text);
    final header = text.substring(4, end);
    var rest = text.substring(end + 4);
    if (rest.startsWith('\n')) rest = rest.substring(1);
    // Serialization always appends a trailing newline; remove exactly one.
    if (rest.endsWith('\n')) rest = rest.substring(0, rest.length - 1);
    return ParsedNote(_parseHeader(header), rest);
  }

  static Map<String, dynamic> _parseHeader(String header) {
    final meta = <String, dynamic>{};
    final lines = header.split('\n');
    String? listKey;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      if (listKey != null && RegExp(r'^\s+-\s').hasMatch(line)) {
        (meta[listKey] as List).add(_scalar(line.replaceFirst(RegExp(r'^\s+-\s'), '').trim()));
        continue;
      }
      listKey = null;
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      final raw = line.substring(idx + 1).trim();
      if (raw.isEmpty) {
        meta[key] = <dynamic>[];
        listKey = key;
        continue;
      }
      meta[key] = _value(raw);
    }
    return meta;
  }

  static dynamic _value(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      if (raw.startsWith('[') && raw.endsWith(']')) {
        final inner = raw.substring(1, raw.length - 1).trim();
        if (inner.isEmpty) return <dynamic>[];
        return inner.split(',').map((e) => _scalar(e.trim())).toList();
      }
      return _scalar(raw);
    }
  }

  static dynamic _scalar(String s) {
    if (s.length >= 2 && ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1);
    }
    if (s == 'true') return true;
    if (s == 'false') return false;
    final n = num.tryParse(s);
    return n ?? s;
  }
}
