import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/engines/exporter.dart';
import '../../domain/engines/importer.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../export_helpers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Import, export and backup. Everything stays in the vault folder (`Exports/`) or goes through the
/// system share sheet; nothing is uploaded anywhere by this app.
class DataScreen extends ConsumerStatefulWidget {
  const DataScreen({super.key});

  @override
  ConsumerState<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends ConsumerState<DataScreen> {
  final Set<String> _kinds = {'prompts'};
  String _format = 'md';
  final _cover = TextEditingController();
  bool _busy = false;

  static const _kindLabels = {
    'prompts': 'Prompts',
    'templates': 'Templates',
    'patterns': 'My patterns',
    'chains': 'Chains',
    'shortcuts': 'Snippets',
    'history': 'Version history',
  };

  @override
  void dispose() {
    _cover.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } on ImportException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAndShare(String name, String content) async {
    final root = ref.read(vaultProvider).rootPath;
    if (root == null) throw StateError('No vault folder is open');
    final file = await saveExportFile(root, name, content);
    if (mounted) toast(context, 'Saved to Exports/$name');
    await shareFilePath(file.path);
  }

  Future<void> _export() => _run(() async {
        final vn = ref.read(vaultProvider.notifier);
        final d = ref.read(vaultProvider).data;
        final versions = _kinds.contains('history') ? await vn.allVersions() : const <String, List<PromptVersion>>{};
        final items = Exporter.collect(d, _kinds, versions: versions);
        if (items.isEmpty) {
          if (mounted) toast(context, 'Nothing to export for that selection.');
          return;
        }
        final cover = _cover.text.trim();
        final String out;
        switch (_format) {
          case 'txt':
            out = Exporter.toTxt(items, coverNote: cover);
          case 'csv':
            out = Exporter.toCsv(items);
          case 'html':
            out = Exporter.toHtml(items, coverNote: cover);
          default:
            out = Exporter.toMarkdown(items, coverNote: cover);
        }
        final ext = _format == 'md' ? 'md' : _format;
        await _saveAndShare('export-${items.length}items-${exportStamp()}.$ext', out);
      });

  Future<void> _backup() => _run(() async {
        final json = await ref.read(vaultProvider.notifier).exportFullBackup();
        await _saveAndShare('prompt-forge-backup-${exportStamp()}.json', json);
      });

  Future<String?> _pickText(List<String> exts) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: exts, withData: true);
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    if (f.bytes != null) return utf8.decode(f.bytes!, allowMalformed: true);
    if (f.path != null) return File(f.path!).readAsString();
    return null;
  }

  Future<String?> _pasteDialog(String title, String hint) async {
    return textPrompt(context, title: title, label: hint, confirmLabel: 'Import', maxLines: 8);
  }

  Future<void> _restore({required bool fromPaste}) => _run(() async {
        final raw = fromPaste ? await _pasteDialog('Paste backup JSON', 'Paste the full backup file contents') : await _pickText(['json']);
        if (raw == null || raw.trim().isEmpty) return;
        final c = BackupParser.parse(raw);
        if (c == null || c.counts.values.fold<int>(0, (a, b) => a + b) == 0) throw ImportException('That backup contains nothing to restore.');
        if (!mounted) return;
        final summary = c.counts.entries.where((e) => e.value > 0).map((e) => '${e.value} ${e.key}').join(', ');
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore backup'),
            content: Text('This backup contains $summary.\n\nMerge adds items and overwrites ones with the same id. Replace first removes your existing prompts, templates, patterns, snippets and chains from the folder.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: Text('Replace', style: TextStyle(color: ctx.pf.red))),
              FilledButton(onPressed: () => Navigator.pop(ctx, 'merge'), child: const Text('Merge')),
            ],
          ),
        );
        if (choice == null) return;
        await ref.read(vaultProvider.notifier).restoreBackup(c, replace: choice == 'replace');
        if (mounted) toast(context, 'Backup restored into your folder');
      });

  Future<void> _importRecords(String kind, {required bool fromPaste}) => _run(() async {
        final raw = fromPaste ? await _pasteDialog('Paste $kind JSON', 'A JSON object or array') : await _pickText(['json']);
        if (raw == null || raw.trim().isEmpty) return;
        final recs = JsonImporter.parse(raw, kind);
        final vn = ref.read(vaultProvider.notifier);
        final n = switch (kind) {
          'prompt' => await vn.importRecords(prompts: recs.map(JsonImporter.toPrompt).toList()),
          'template' => await vn.importRecords(templates: recs.map(JsonImporter.toTemplate).toList()),
          _ => await vn.importRecords(patterns: recs.map(JsonImporter.toPattern).toList()),
        };
        if (mounted) toast(context, 'Imported $n ${kind}${n == 1 ? '' : 's'}');
      });

  Future<void> _importMarkdownFiles() => _run(() async {
        final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['md', 'markdown', 'txt'], allowMultiple: true, withData: true);
        if (res == null || res.files.isEmpty) return;
        final vn = ref.read(vaultProvider.notifier);
        final prompts = <Prompt>[];
        for (final f in res.files) {
          final text = f.bytes != null ? utf8.decode(f.bytes!, allowMalformed: true) : (f.path != null ? await File(f.path!).readAsString() : '');
          if (text.trim().isEmpty) continue;
          final base = f.name.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
          prompts.add(Prompt(title: base, body: text.trim(), format: f.name.endsWith('.md') || f.name.endsWith('.markdown') ? 'markdown' : 'text'));
        }
        final n = await vn.importRecords(prompts: prompts);
        if (mounted) toast(context, 'Imported $n file${n == 1 ? '' : 's'} as prompts');
      });

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final d = ref.watch(vaultProvider).data;
    final counts = {
      'prompts': d.prompts.length,
      'templates': d.templates.length,
      'patterns': d.customPatterns.length,
      'chains': d.chains.length,
      'shortcuts': d.snippets.length,
      'history': null,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Import & export')),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          Text('Your prompts already live as Markdown files in your vault folder. These tools make copies for sharing or moving between devices.', style: TextStyle(color: p.textSecondary, fontSize: 13)),
          const SectionTitle('Export selection'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in Exporter.allKinds)
              FilterChip(
                label: Text('${_kindLabels[k]}${counts[k] == null ? '' : ' ${counts[k]}'}'),
                selected: _kinds.contains(k),
                onSelected: (v) => setState(() => v ? _kinds.add(k) : _kinds.remove(k)),
              ),
          ]),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'md', label: Text('MD')), ButtonSegment(value: 'txt', label: Text('TXT')), ButtonSegment(value: 'csv', label: Text('CSV')), ButtonSegment(value: 'html', label: Text('HTML'))],
            selected: {_format},
            onSelectionChanged: (s) => setState(() => _format = s.first),
          ),
          const SizedBox(height: 12),
          if (_format != 'csv') TextField(controller: _cover, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Cover note (optional)')),
          const SizedBox(height: 12),
          FilledButton.icon(icon: const Icon(Icons.ios_share, size: 18), label: const Text('Export & share'), onPressed: _kinds.isEmpty || _busy ? null : _export),
          const SectionTitle('Full backup (JSON)'),
          Text('Everything — prompts, templates, patterns, chains, snippets, groups, saved searches, structures and version history — in one file. Compatible with backups from the original Prompt Forge web app.', style: TextStyle(color: p.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          OutlinedButton.icon(icon: const Icon(Icons.backup_outlined, size: 18), label: const Text('Create backup'), onPressed: _busy ? null : _backup),
          const SectionTitle('Restore a backup'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(icon: const Icon(Icons.upload_file, size: 18), label: const Text('Choose file…'), onPressed: _busy ? null : () => _restore(fromPaste: false)),
            OutlinedButton.icon(icon: const Icon(Icons.content_paste, size: 18), label: const Text('Paste JSON…'), onPressed: _busy ? null : () => _restore(fromPaste: true)),
          ]),
          const SectionTitle('Import records'),
          Text('Add prompts, templates or patterns from a JSON file. Common field names are recognised.', style: TextStyle(color: p.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in const ['prompt', 'template', 'pattern'])
              PopupMenuButton<bool>(
                enabled: !_busy,
                onSelected: (paste) => _importRecords(k, fromPaste: paste),
                itemBuilder: (_) => const [PopupMenuItem(value: false, child: Text('From file…')), PopupMenuItem(value: true, child: Text('Paste JSON…'))],
                child: Chip(avatar: const Icon(Icons.add, size: 16), label: Text('${k[0].toUpperCase()}${k.substring(1)}s')),
              ),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(icon: const Icon(Icons.description_outlined, size: 18), label: const Text('Import Markdown / text files as prompts'), onPressed: _busy ? null : _importMarkdownFiles),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Tip: you can also copy .md files straight into the vault folder with any file manager, then pull down to refresh the Library.', style: TextStyle(color: p.textTertiary, fontSize: 11.5)),
          ),
        ]),
        if (_busy) const Positioned.fill(child: ColoredBox(color: Color(0x66000000), child: Center(child: CircularProgressIndicator()))),
      ]),
    );
  }
}
