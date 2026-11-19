import 'dart:convert';

import '../../core/util.dart';
import '../../data/vault/vault_repository.dart';
import '../models.dart';

class ExportItem {
  final String id;
  final String kind; // prompts | templates | patterns | chains | shortcuts | history
  final String kindLabel;
  final String title;
  final String body;
  final int updatedAt;
  final Map<String, Object?> meta;
  const ExportItem({
    required this.id,
    required this.kind,
    required this.kindLabel,
    required this.title,
    required this.body,
    required this.updatedAt,
    this.meta = const {},
  });
}

/// Export formats (CSV / HTML / Markdown / TXT / per-prompt files / full JSON backup).
class Exporter {
  Exporter._();

  static const List<String> allKinds = ['prompts', 'templates', 'patterns', 'chains', 'shortcuts', 'history'];

  static List<ExportItem> collect(VaultData d, Set<String> kinds, {Map<String, List<PromptVersion>> versions = const {}}) {
    final items = <ExportItem>[];
    final prompts = d.prompts.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (kinds.contains('prompts')) {
      for (final p in prompts) {
        items.add(ExportItem(
          id: p.id,
          kind: 'prompts',
          kindLabel: 'Prompt',
          title: p.displayTitle,
          body: p.body,
          updatedAt: p.updatedAt,
          meta: {
            'Category': p.category,
            'Tags': p.tags.join('; '),
            'Status': p.status,
            'Favorite': p.favorite ? 'yes' : '',
            'Archived': p.archived ? 'yes' : '',
            'Version': p.currentVersion,
          },
        ));
      }
    }
    if (kinds.contains('templates')) {
      for (final t in d.templates.values) {
        items.add(ExportItem(id: t.id, kind: 'templates', kindLabel: 'Template', title: t.displayName, body: t.body, updatedAt: t.updatedAt, meta: {'Category': t.category, 'Used': t.useCount}));
      }
    }
    if (kinds.contains('patterns')) {
      for (final p in d.customPatterns.values) {
        items.add(ExportItem(id: p.id, kind: 'patterns', kindLabel: 'Pattern', title: p.name, body: p.template, updatedAt: p.updatedAt, meta: {'Category': p.category, 'Purpose': p.purpose}));
      }
    }
    if (kinds.contains('chains')) {
      for (final c in d.chains.values) {
        final lines = <String>[];
        for (var i = 0; i < c.steps.length; i++) {
          final s = c.steps[i];
          final p = s.promptId == null ? null : d.prompts[s.promptId];
          lines.add('${i + 1}. ${p != null ? p.displayTitle : '(missing prompt)'}${s.note.isNotEmpty ? ' — ${s.note}' : ''}');
        }
        items.add(ExportItem(
            id: c.id,
            kind: 'chains',
            kindLabel: 'Chain',
            title: c.name.isEmpty ? 'Untitled chain' : c.name,
            body: [c.description, lines.join('\n')].where((e) => e.isNotEmpty).join('\n\n'),
            updatedAt: c.updatedAt,
            meta: {'Steps': c.steps.length}));
      }
    }
    if (kinds.contains('shortcuts')) {
      for (final s in d.snippets.values) {
        items.add(ExportItem(id: s.id, kind: 'shortcuts', kindLabel: 'Shortcut', title: s.trigger, body: s.body, updatedAt: s.updatedAt, meta: {'Used': s.useCount}));
      }
    }
    if (kinds.contains('history')) {
      for (final p in prompts) {
        for (final v in versions[p.id] ?? const <PromptVersion>[]) {
          items.add(ExportItem(
              id: v.id,
              kind: 'history',
              kindLabel: 'History',
              title: '${p.displayTitle} — v${v.versionNum}',
              body: v.body,
              updatedAt: v.createdAt,
              meta: {'Prompt': p.displayTitle, 'Version': v.versionNum, 'Note': v.note, 'Saved': Utils.formatDate(v.createdAt)}));
        }
      }
    }
    return items;
  }

  static String toMarkdown(List<ExportItem> items, {String coverNote = ''}) {
    final cover = coverNote.isNotEmpty ? '$coverNote\n\n---\n\n' : '';
    return cover + items.map((it) => '## ${it.title}\n\n*${it.kindLabel} · ${Utils.formatDate(it.updatedAt)}*\n\n${it.body}\n').join('\n---\n\n');
  }

  static String toTxt(List<ExportItem> items, {String coverNote = ''}) {
    final cover = coverNote.isNotEmpty ? '$coverNote\n\n' : '';
    return cover + items.map((it) => '${it.title}\n${'=' * it.title.length}\n\n${it.body}\n').join('\n\n');
  }

  static String toCsv(List<ExportItem> items) {
    final metaKeys = <String>[];
    for (final it in items) {
      for (final k in it.meta.keys) {
        if (!metaKeys.contains(k)) metaKeys.add(k);
      }
    }
    final rows = <List<Object?>>[
      ['Type', 'Title', 'Words', 'Updated', ...metaKeys]
    ];
    for (final it in items) {
      rows.add([
        it.kindLabel,
        it.title,
        Utils.countWords(it.body),
        DateTime.fromMillisecondsSinceEpoch(it.updatedAt, isUtc: true).toIso8601String(),
        ...metaKeys.map((k) => it.meta[k] ?? ''),
      ]);
    }
    return rows.map((r) => r.map(Utils.csvEscape).join(',')).join('\n');
  }

  static const String _css =
      'body{font-family:system-ui,sans-serif;max-width:800px;margin:40px auto;padding:0 20px;line-height:1.6;color:#222}h2{margin-top:2em;border-bottom:1px solid #ddd;padding-bottom:6px}.meta{color:#888;font-size:.85em}pre{white-space:pre-wrap;background:#f6f6f6;padding:14px;border-radius:8px;font-size:.9em}';

  static String toHtml(List<ExportItem> items, {String coverNote = ''}) {
    final cover = coverNote.isNotEmpty
        ? '<p style="font-size:1.05em;color:#444;border-left:3px solid #ddd;padding-left:14px;margin:20px 0">${Utils.escapeHtml(coverNote)}</p>'
        : '';
    final body = items
        .map((it) => '<h2>${Utils.escapeHtml(it.title)}</h2><div class="meta">${Utils.escapeHtml(it.kindLabel)} &middot; ${Utils.escapeHtml(Utils.formatDate(it.updatedAt))}</div><pre>${Utils.escapeHtml(it.body)}</pre>')
        .join('\n');
    return '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Prompt Forge Export</title><style>$_css</style></head><body><h1>Prompt Forge Export</h1>$cover$body</body></html>';
  }

  /// One prompt as a standalone file. [format]: txt | md | json | html
  static String promptToFormat(Prompt p, String format) {
    final title = p.displayTitle;
    switch (format) {
      case 'json':
        return const JsonEncoder.withIndent('  ').convert({
          'title': title,
          'body': p.body,
          'category': p.category,
          'tags': p.tags,
          'updatedAt': p.updatedAt,
          'createdAt': p.createdAt,
        });
      case 'md':
        final tags = p.tags.isNotEmpty ? '${p.tags.map((t) => '`#$t`').join(' ')}\n\n' : '';
        return '# $title\n\n$tags${p.body}\n';
      case 'html':
        return '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>${Utils.escapeHtml(title)}</title><style>$_css</style></head><body><h1>${Utils.escapeHtml(title)}</h1><pre>${Utils.escapeHtml(p.body)}</pre></body></html>';
      default:
        return p.body;
    }
  }

  static String fileExt(String format) => format == 'md' ? 'md' : format == 'html' ? 'html' : format == 'json' ? 'json' : 'txt';

  /// Same top-level shape as the HTML app's `StorageManager.exportAll()`, so backups are interchangeable.
  static String fullBackupJson(VaultData d, List<PromptVersion> versions) {
    final dump = <String, Object?>{
      'prompts': d.prompts.values.map((p) => p.toMap()).toList(),
      'templates': d.templates.values.map((t) => t.toMap()).toList(),
      'snippets': d.snippets.values.map((s) => s.toMap()).toList(),
      'history': <Object?>[],
      'versions': versions.map((v) => v.toMap()).toList(),
      'customPatterns': d.customPatterns.values.map((p) => p.toMap()).toList(),
      'chains': d.chains.values.map((c) => c.toMap()).toList(),
      'savedSearches': d.savedSearches.values.map((s) => s.toMap()).toList(),
      'groups': d.groups.values.map((g) => g.toMap()).toList(),
      'builderStructures': d.builderStructures.values.map((b) => b.toMap()).toList(),
      '_settings': {
        'selectedModel': d.settings.selectedModel,
        'scoringProfile': d.settings.scoringProfile,
        'customModels': d.settings.customModels.map((m) => m.toMap()).toList(),
        // Same shape the HTML app writes ({solved, score, answer, attemptedAt}), so either app can import it.
        'challengeProgress': {
          for (final id in {...d.settings.challengeProgress.keys, ...d.settings.challengeAttempts.keys})
            id: (d.settings.challengeAttempts[id] ??
                    ChallengeAttempt(solved: d.settings.challengeProgress[id] == true, score: d.settings.challengeProgress[id] == true ? 100 : 0, answer: '', attemptedAt: 0))
                .toMap(),
        },
        'volumeCallsPerMonth': d.settings.volumeCallsPerMonth,
        'defaultCategory': d.settings.defaultCategory,
      },
      '_meta': {'exportedAt': Utils.nowMs(), 'version': 1, 'app': 'prompt-forge'},
    };
    return const JsonEncoder.withIndent('  ').convert(dump);
  }
}
