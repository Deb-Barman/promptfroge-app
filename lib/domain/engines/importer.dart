import 'dart:convert';

import '../../core/constants.dart';
import '../../core/util.dart';
import '../../data/vault/vault_repository.dart';
import '../models.dart';

class ImportException implements Exception {
  final String message;
  ImportException(this.message);
  @override
  String toString() => message;
}

/// Tolerant JSON import of a pasted/picked file into prompt / template / pattern records.
class JsonImporter {
  JsonImporter._();

  static const Map<String, List<String>> _promptAliases = {
    'title': ['title', 'name'],
    'category': ['category', 'cat'],
    'tags': ['tags', 'tag'],
    'body': ['prompt', 'body', 'text', 'content'],
  };
  static const Map<String, List<String>> _templateAliases = {
    'name': ['title', 'name'],
    'category': ['category', 'cat'],
    'body': ['prompt', 'body', 'text', 'template', 'content'],
  };
  static const Map<String, List<String>> _patternAliases = {
    'name': ['title', 'name'],
    'category': ['category', 'cat'],
    'purpose': ['purpose', 'description', 'desc'],
    'when': ['when', 'when_to_use', 'whentouse'],
    'template': ['prompt', 'body', 'text', 'template', 'content'],
    'example': ['example', 'sample'],
  };

  /// Returns normalized field maps. [kind]: prompt | template | pattern.
  static List<Map<String, dynamic>> parse(String text, String kind) {
    dynamic data;
    try {
      data = jsonDecode(text);
    } catch (_) {
      throw ImportException("That doesn't look like valid JSON — check for a missing comma, bracket, or quote.");
    }
    final records = data is List ? data : [data];
    if (records.isEmpty) throw ImportException('No records found in that JSON.');
    final aliases = kind == 'prompt' ? _promptAliases : kind == 'template' ? _templateAliases : kind == 'pattern' ? _patternAliases : null;
    if (aliases == null) throw ImportException('Unknown import kind: $kind');

    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < records.length; i++) {
      final rec = records[i];
      if (rec is! Map) throw ImportException("Record ${i + 1} isn't a JSON object — each entry in the array must be { ... }.");
      final norm = <String, dynamic>{};
      rec.forEach((k, v) => norm[k.toString().trim().toLowerCase()] = v);
      final item = <String, dynamic>{};
      aliases.forEach((field, list) {
        dynamic v = '';
        for (final a in list) {
          if (norm[a] != null) {
            v = norm[a];
            break;
          }
        }
        item[field] = v;
      });
      if (item.containsKey('tags')) {
        final t = item['tags'];
        if (t is List) {
          item['tags'] = t.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        } else if (t is String) {
          item['tags'] = t.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        } else {
          item['tags'] = <String>[];
        }
      }
      out.add(item);
    }
    return out;
  }

  static Prompt toPrompt(Map<String, dynamic> m) => Prompt(
        title: Utils.truncate(m['title']?.toString() ?? '', 200),
        body: m['body']?.toString() ?? '',
        category: kCategories.any((c) => c.id == m['category']) ? m['category'] as String : 'custom',
        tags: (m['tags'] as List?)?.map((e) => e.toString()).toList() ?? <String>[],
      );

  static Template toTemplate(Map<String, dynamic> m) => Template(
        name: m['name']?.toString() ?? '',
        body: m['body']?.toString() ?? '',
        category: kCategories.any((c) => c.id == m['category']) ? m['category'] as String : 'custom',
      );

  static PromptPattern toPattern(Map<String, dynamic> m) => PromptPattern(
        name: m['name']?.toString() ?? '',
        category: m['category']?.toString().isNotEmpty == true ? m['category'].toString() : 'Custom',
        purpose: m['purpose']?.toString() ?? '',
        when: m['when']?.toString() ?? '',
        template: m['template']?.toString() ?? '',
        example: m['example']?.toString() ?? '',
        variables: RegExp(r'\{\{\s*([a-zA-Z0-9_]+)').allMatches(m['template']?.toString() ?? '').map((x) => x.group(1)!).toSet().toList(),
      );
}

class BackupContents {
  final VaultData data;
  final List<PromptVersion> versions;
  final Map<String, int> counts;
  final int? exportedAt;
  const BackupContents(this.data, this.versions, this.counts, this.exportedAt);
}

/// Reads a full backup JSON (the HTML app's `exportAll()` shape, or this app's own).
class BackupParser {
  BackupParser._();

  static List<Map<String, dynamic>> _list(dynamic v) =>
      v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

  /// Returns null if [raw] is valid JSON but contains no recognisable data; throws [ImportException] on bad JSON.
  static BackupContents? parse(String raw) {
    dynamic obj;
    try {
      obj = jsonDecode(raw);
    } catch (_) {
      throw ImportException("Couldn't read this as valid JSON — check it's the full, unmodified contents of a backup file.");
    }
    if (obj is! Map) throw ImportException("This doesn't look like a Prompt Forge backup — expected a JSON object with sections like \"prompts\".");
    final m = Map<String, dynamic>.from(obj);
    final d = VaultData();
    final counts = <String, int>{};

    for (final r in _list(m['prompts'])) {
      final p = Prompt.fromMap(r);
      d.prompts[p.id] = p;
    }
    for (final r in _list(m['templates'])) {
      final t = Template.fromMap(r);
      d.templates[t.id] = t;
    }
    for (final r in _list(m['snippets'])) {
      final s = Snippet.fromMap(r);
      d.snippets[s.id] = s;
    }
    for (final r in _list(m['customPatterns'])) {
      final p = PromptPattern.fromMap(r);
      d.customPatterns[p.id] = p;
    }
    for (final r in _list(m['chains'])) {
      final c = Chain.fromMap(r);
      d.chains[c.id] = c;
    }
    for (final r in _list(m['groups'])) {
      final g = Group.fromMap(r);
      d.groups[g.id] = g;
    }
    for (final r in _list(m['savedSearches'])) {
      final s = SavedSearch.fromMap(r);
      d.savedSearches[s.id] = s;
    }
    for (final r in _list(m['builderStructures'])) {
      final b = BuilderStructure.fromMap(r);
      d.builderStructures[b.id] = b;
    }
    final versions = _list(m['versions']).map((r) => PromptVersion.fromMap(r)).where((v) => v.promptId.isNotEmpty).toList();

    VaultSettings settings = VaultSettings();
    var hasSettings = false;
    if (m['_settings'] is Map) {
      settings = VaultSettings.fromMap(Map<String, dynamic>.from(m['_settings'] as Map));
      hasSettings = true;
    }

    counts['prompts'] = d.prompts.length;
    counts['templates'] = d.templates.length;
    counts['snippets'] = d.snippets.length;
    counts['patterns'] = d.customPatterns.length;
    counts['chains'] = d.chains.length;
    counts['groups'] = d.groups.length;
    counts['versions'] = versions.length;
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0 && !hasSettings) return null;

    final exportedAt = (m['_meta'] is Map && (m['_meta'] as Map)['exportedAt'] is num) ? ((m['_meta'] as Map)['exportedAt'] as num).toInt() : null;
    return BackupContents(d.copyWith(settings: settings), versions, counts, exportedAt);
  }
}
