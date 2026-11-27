import 'dart:convert';

import '../models.dart';

/// Result of reading model definitions from JSON: the models that were understood, plus a readable note for
/// every entry that was skipped (so the dialog can say exactly what was wrong).
class ModelImportResult {
  final List<CustomModel> models;
  final List<String> problems;
  const ModelImportResult(this.models, this.problems);
}

/// Reads custom models from JSON, in the same shape the web app uses:
/// `{ "label": "Gemini 3", "vendor": "Google", "group": "Gemini", "contextWindow": 2000000,
///    "priceIn": 2, "priceOut": 8, "priceNote": "per 1M tokens" }`
/// as one object, an array of them, or `{ "models": [...] }`. Only `label` is required.
class ModelImport {
  ModelImport._();

  static const String example = '[\n'
      '  {\n'
      '    "label": "Gemini 3",\n'
      '    "vendor": "Google",\n'
      '    "group": "Gemini",\n'
      '    "contextWindow": 2000000,\n'
      '    "priceIn": 2,\n'
      '    "priceOut": 8,\n'
      '    "priceNote": "per 1M tokens"\n'
      '  }\n'
      ']';

  static ModelImportResult parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const ModelImportResult([], ['Nothing to import — paste a JSON object or array.']);
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      return ModelImportResult(const [], ['That is not valid JSON (${e.message}).']);
    }
    List<Object?> items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map && decoded['models'] is List) {
      items = decoded['models'] as List<Object?>;
    } else {
      items = [decoded];
    }
    final models = <CustomModel>[];
    final problems = <String>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final where = items.length == 1 ? 'The model' : 'Entry ${i + 1}';
      if (it is! Map) {
        problems.add('$where is not an object.');
        continue;
      }
      final label = _str(it['label'] ?? it['name']).trim();
      if (label.isEmpty) {
        problems.add('$where has no "label".');
        continue;
      }
      final vendor = _str(it['vendor']).trim();
      final group = _str(it['group']).trim();
      final ctx = _num(it['contextWindow'] ?? it['context'])?.round();
      final cpt = _num(it['charsPerToken']);
      models.add(CustomModel(
        label: label,
        vendor: vendor.isEmpty ? 'Custom' : vendor,
        group: group,
        contextWindow: ctx != null && ctx > 0 ? ctx : 128000,
        charsPerToken: cpt != null && cpt > 0 ? cpt : 4.0,
        priceIn: _clamp(_num(it['priceIn'])),
        priceOut: _clamp(_num(it['priceOut'])),
        priceNote: _str(it['priceNote'], 'per 1M tokens').trim().isEmpty ? 'per 1M tokens' : _str(it['priceNote'], 'per 1M tokens').trim(),
      ));
    }
    return ModelImportResult(models, problems);
  }

  static String _str(Object? v, [String d = '']) => v == null ? d : '$v';

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim().replaceAll(',', ''));
    return null;
  }

  static double _clamp(double? v) => v == null || v.isNaN || v < 0 ? 0 : v;
}
