import '../../core/constants.dart';
import '../models.dart';
import 'engine_util.dart';

/// One `{{variable}}` descriptor: name, type (text|number|multiline|select),
/// default value and (for select) the options.
class VarSpec {
  final String name;
  final String type;
  final String defaultValue;
  final List<String> options;
  const VarSpec(this.name, {this.type = 'text', this.defaultValue = '', this.options = const <String>[]});
}

/// A literal in a finished prompt that looks like something worth turning into a variable.
class SpanCandidate {
  final String text;

  /// quoted | number | phrase
  final String kind;
  final int index;
  const SpanCandidate({required this.text, required this.kind, required this.index});
}

class VarReplacement {
  final String text;
  final String varName;
  const VarReplacement(this.text, this.varName);
}

/// Port of the original `TemplateEngine` object.
class TemplateEngine {
  TemplateEngine._();

  /// Original bare-name pattern `{{name}}`.
  static final RegExp varRe = RegExp(r'\{\{\s*([a-zA-Z0-9_]+)\s*\}\}');

  /// `{{name}}`, `{{name:type}}`, `{{name:select:a|b|c}}`, `{{name=default}}`, `{{name:type=default}}`.
  static final RegExp varSpecRe = RegExp(r'\{\{\s*([a-zA-Z0-9_]+)(?::([a-zA-Z]+)(?::([^=}]+))?)?(?:=([^}]*))?\s*\}\}');

  static VarSpec _parseSpec(String name, String? type, String? optionsRaw, String? defaultVal) {
    var t = (type == null || type.isEmpty ? 'text' : type).toLowerCase();
    final def = defaultVal ?? '';
    var options = <String>[];
    if (t == 'select') {
      if (optionsRaw != null && optionsRaw.isNotEmpty) {
        options = optionsRaw.split('|').map((o) => o.trim()).where((o) => o.isNotEmpty).toList();
      }
      if (options.isEmpty) t = 'text'; // malformed :select with no options
    }
    if (t != 'text' && t != 'number' && t != 'multiline' && t != 'select') t = 'text';
    return VarSpec(name, type: t, defaultValue: def, options: t == 'select' ? options : const <String>[]);
  }

  /// De-duplicated by name, first-seen order.
  static List<VarSpec> extractVariableSpecs(String? body) {
    if (body == null || body.isEmpty) return <VarSpec>[];
    final seen = <String>{};
    final out = <VarSpec>[];
    for (final m in varSpecRe.allMatches(body)) {
      final name = m.group(1)!;
      if (seen.add(name)) {
        out.add(_parseSpec(name, m.group(2), m.group(3), m.group(4)));
      }
    }
    return out;
  }

  static List<String> extractVariables(String? body) => extractVariableSpecs(body).map((s) => s.name).toList();

  /// Replaces every `{{...}}` with the supplied value, else the spec default, else leaves it untouched.
  static String render(String? body, Map<String, String> values) {
    if (body == null || body.isEmpty) return '';
    return body.replaceAllMapped(varSpecRe, (m) {
      final name = m.group(1)!;
      final v = values[name];
      if (v != null && v.isNotEmpty) return v;
      final def = m.group(4);
      if (def != null && def.isNotEmpty) return def;
      return m.group(0)!;
    });
  }

  /// True when the body contains a bare `{{name}}` placeholder (typed ones are not counted, like the original).
  static bool hasUnfilledVariables(String? body) => varRe.hasMatch(body ?? '');

  static String humanizeVarName(String name) {
    return name.replaceAll('_', ' ').replaceAllMapped(RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());
  }

  static String _builtinLabel(String type) {
    final bt = blockTypeById(type);
    return bt == null ? '' : bt.label;
  }

  /// Label used by [composeFromBlocks]: block.label, else the built-in label, else the type id.
  static String _composeLabel(PromptBlock b) {
    final own = b.label;
    if (own != null && own.isNotEmpty) return own;
    final built = _builtinLabel(b.type);
    if (built.isNotEmpty) return built;
    return b.type;
  }

  /// Composes a prompt body from ordered blocks; empty blocks are skipped.
  static String composeFromBlocks(List<PromptBlock> blocks) {
    final parts = <String>[];
    for (final b in blocks) {
      if (b.text.trim().isEmpty) continue;
      parts.add('${_composeLabel(b)}:\n${b.text.trim()}');
    }
    return parts.join('\n\n');
  }

  /// Display label of a block (custom blocks carry their own label).
  static String blockLabel(PromptBlock b) {
    final own = b.label;
    if (own != null && own.isNotEmpty) return own;
    if (b.type.startsWith('custom_')) return 'Custom Section';
    final built = _builtinLabel(b.type);
    if (built.isNotEmpty) return built;
    return b.type;
  }

  /// Display colour (ARGB) of a block.
  static int blockColor(PromptBlock b) {
    if (b.type.startsWith('custom_')) return b.color ?? 0xFF9B7FE0;
    final bt = blockTypeById(b.type);
    if (bt != null) return bt.color;
    return b.color ?? kBlockTypes.last.color;
  }

  // "Extract variables": heuristic candidates for turning a finished prompt into a template.
  static final RegExp _quoteRe = RegExp(r'"([^"\n]{2,60})"' r"|'([^'\n]{2,60})'");
  static final RegExp _numRe = RegExp(r'\b\d{2,}\b');
  static final RegExp _capRe = RegExp(r'(?<!^|\. )\b([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+){0,3})\b', multiLine: true);

  static List<SpanCandidate> detectParameterizableSpans(String? body) {
    if (body == null || body.trim().isEmpty) return <SpanCandidate>[];
    final seen = <String>{};
    final candidates = <SpanCandidate>[];

    for (final m in _quoteRe.allMatches(body)) {
      final val = m.group(1) ?? m.group(2) ?? '';
      final key = val.toLowerCase();
      if (!seen.contains(key) && val.trim().isNotEmpty) {
        seen.add(key);
        candidates.add(SpanCandidate(text: val, kind: 'quoted', index: m.start));
      }
    }

    for (final m in _numRe.allMatches(body)) {
      final val = m.group(0)!;
      final key = val.toLowerCase();
      if (!seen.contains(key)) {
        seen.add(key);
        candidates.add(SpanCandidate(text: val, kind: 'number', index: m.start));
      }
    }

    final headerWords = kBlockTypes.map((b) => b.label.toLowerCase()).toSet();
    final splitWs = RegExp(r'\s+');
    for (final m in _capRe.allMatches(body)) {
      final val = m.group(1)!;
      final key = val.toLowerCase();
      final firstWord = val.split(splitWs)[0].toLowerCase();
      if (seen.contains(key) || headerWords.contains(firstWord)) continue;
      seen.add(key);
      candidates.add(SpanCandidate(text: val, kind: 'phrase', index: m.start));
    }

    return stableSorted<SpanCandidate>(candidates, (a, b) => a.index.compareTo(b.index));
  }

  /// Turns each literal occurrence of `text` into `{{varName}}` (all occurrences).
  static String applyExtractedVariables(String body, List<VarReplacement> replacements) {
    var result = body;
    for (final r in replacements) {
      if (r.text.isEmpty || r.varName.isEmpty) continue;
      result = result.replaceAll(r.text, '{{' + r.varName + '}}');
    }
    return result;
  }
}
