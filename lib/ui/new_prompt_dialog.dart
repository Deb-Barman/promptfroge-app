import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/shell.dart';
import '../core/constants.dart';
import '../domain/engines/importer.dart';
import '../domain/models.dart';
import '../state/vault_notifier.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';
import 'widgets/pf_chrome.dart';

/// The web app's "New Prompt" dialog: fill in manually · paste JSON · upload a JSON file.
Future<void> showNewPromptDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(context: context, builder: (_) => _NewPromptDialog(parentContext: context, ref: ref));
}

const String _example = '''[
  {
    "Title": "Example title",
    "Category": "coding",
    "Tags": "python, api",
    "Prompt": "You are a Python expert. ..."
  }
]''';

class _NewPromptDialog extends StatefulWidget {
  final BuildContext parentContext;
  final WidgetRef ref;
  const _NewPromptDialog({required this.parentContext, required this.ref});

  @override
  State<_NewPromptDialog> createState() => _NewPromptDialogState();
}

class _NewPromptDialogState extends State<_NewPromptDialog> {
  int _tab = 0;
  final _title = TextEditingController();
  final _tags = TextEditingController();
  final _paste = TextEditingController();
  String _category = 'custom';
  String? _fileName;
  String? _fileText;
  bool _showExample = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _tags.dispose();
    _paste.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    final tags = _tags.text.split(',').map((t) => t.trim().replaceFirst(RegExp(r'^#'), '')).where((t) => t.isNotEmpty).toList();
    final saved = await widget.ref.read(vaultProvider.notifier).savePrompt(Prompt(title: _title.text.trim(), category: _category, tags: tags));
    if (!mounted) return;
    final ctx = widget.parentContext;
    Navigator.of(context).pop();
    if (ctx.mounted) openInEditor(ctx, widget.ref, promptId: saved.id);
  }

  Future<void> _import(String raw) async {
    if (raw.trim().isEmpty) {
      setState(() => _error = 'Nothing to import yet.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final recs = JsonImporter.parse(raw, 'prompt');
      final n = await widget.ref.read(vaultProvider.notifier).importRecords(prompts: recs.map(JsonImporter.toPrompt).toList());
      if (!mounted) return;
      final ctx = widget.parentContext;
      Navigator.of(context).pop();
      if (ctx.mounted) toast(ctx, 'Imported $n prompt${n == 1 ? '' : 's'}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['json'], withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final text = f.bytes != null ? utf8.decode(f.bytes!, allowMalformed: true) : (f.path != null ? await File(f.path!).readAsString() : '');
    setState(() {
      _fileName = f.name;
      _fileText = text;
      _error = null;
    });
  }

  Widget _tabBtn(PfPalette p, int i, String label) {
    final on = _tab == i;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _tab = i;
          _error = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? p.amber : Colors.transparent, width: 2))),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.25, color: on ? p.amber : p.textTertiary)),
        ),
      ),
    );
  }

  Widget _label(PfPalette p, String t, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 14),
        child: Row(children: [
          Expanded(child: Text(t, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.textSecondary))),
          if (hint != null) Text(hint, style: TextStyle(fontSize: 12, color: p.textTertiary)),
        ]),
      );

  Widget _example_(PfPalette p) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 14),
        InkWell(
          onTap: () => setState(() => _showExample = !_showExample),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('${_showExample ? '▾' : '▸'} Example JSON format', style: TextStyle(fontSize: 13, color: p.textTertiary)),
          ),
        ),
        if (_showExample)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.borderSubtle)),
            child: Text(_example, style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 12, height: 1.45, color: p.textSecondary)),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    Widget body;
    List<Widget> actions;
    if (_tab == 0) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(p, 'Title', hint: 'optional'),
        TextField(controller: _title, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Untitled prompt')),
        _label(p, 'Category'),
        PfSelect<String>(value: _category, options: [for (final c in kCategories) MapEntry(c.id, c.label)], onChanged: (v) => setState(() => _category = v)),
        _label(p, 'Tags', hint: 'comma-separated, optional'),
        TextField(controller: _tags, decoration: const InputDecoration(hintText: 'e.g. onboarding, internal')),
      ]);
      actions = [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancel', style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w600))),
        const SizedBox(width: 8),
        FilledButton(onPressed: _busy ? null : _start, child: const Text('Start writing')),
      ];
    } else if (_tab == 1) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(p, 'Paste JSON'),
        TextField(
          controller: _paste,
          minLines: 9,
          maxLines: 12,
          autocorrect: false,
          style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 13),
          decoration: const InputDecoration(hintText: 'Paste a JSON object or array here…'),
        ),
        _example_(p),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: p.red, fontSize: 12.5))),
      ]);
      actions = [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancel', style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w600))),
        const SizedBox(width: 8),
        FilledButton(onPressed: _busy ? null : () => _import(_paste.text), child: const Text('Import')),
      ];
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(p, 'Upload a .json file'),
        InkWell(
          onTap: _pickFile,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: p.surface3, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.border)),
                child: const Text('Choose File', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(_fileName ?? 'No file chosen', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: _fileName == null ? p.textTertiary : p.text))),
            ]),
          ),
        ),
        _example_(p),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: p.red, fontSize: 12.5))),
      ]);
      actions = [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancel', style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w600))),
        const SizedBox(width: 8),
        FilledButton(onPressed: _busy || _fileText == null ? null : () => _import(_fileText!), child: const Text('Import')),
      ];
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 12, 14),
            child: Row(children: [
              const Expanded(child: Text('New Prompt', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
            ]),
          ),
          Divider(height: 1, color: p.borderSubtle),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 10),
                Row(children: [_tabBtn(p, 0, 'Fill in\nmanually'), _tabBtn(p, 1, 'Paste\nJSON'), _tabBtn(p, 2, 'Upload JSON\nfile')]),
                Divider(height: 1, color: p.borderSubtle),
                body,
                const SizedBox(height: 8),
              ]),
            ),
          ),
          Divider(height: 1, color: p.borderSubtle),
          Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 14), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions)),
        ]),
      ),
    );
  }
}
