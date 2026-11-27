import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../domain/engines/model_import.dart';
import '../../domain/engines/token_estimator.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../theme/app_theme.dart';
import 'common.dart';

String _price(ModelSpec m) {
  String f(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  if (m.priceIn == 0 && m.priceOut == 0) return 'free / not set';
  return '\$${f(m.priceIn)} in · \$${f(m.priceOut)} out';
}

String _ctx(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M ctx';
  if (n >= 1000) return '${(n / 1000).round()}K ctx';
  return '$n ctx';
}

Color _groupColor(PfPalette p, String group) {
  final colors = [p.amber, p.blue, p.green, p.violet, p.red, const Color(0xFF4FC3D9)];
  var h = 0;
  for (final c in group.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return colors[h % colors.length];
}

class _Group {
  final String name;
  final List<ModelSpec> models;
  final Set<String> customIds;
  _Group(this.name, this.models, this.customIds);
  int get customCount => models.where((m) => customIds.contains(m.id)).length;
}

List<_Group> _groups(VaultSettings s) {
  final customIds = {for (final m in s.customModels) m.id};
  final map = <String, List<ModelSpec>>{};
  for (final m in TokenEstimator.allModels(s.customModels)) {
    if (s.hideBuiltinModels && !customIds.contains(m.id)) continue;
    map.putIfAbsent(m.group, () => []).add(m);
  }
  final groups = [for (final e in map.entries) _Group(e.key, e.value, customIds)];
  groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return groups;
}

/// The "Models & tokens" card in Settings: models clustered by group (so 60 models are three tidy rows, not a
/// 60-row list), a hide-built-ins switch, and the Add model / Import entry points.
class ModelsSettingsCard extends ConsumerWidget {
  const ModelsSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pf;
    final vn = ref.read(vaultProvider.notifier);
    final s = ref.watch(vaultProvider).data.settings;
    final groups = _groups(s);
    final total = groups.fold<int>(0, (a, g) => a + g.models.length);

    Future<void> save(VaultSettings next) => vn.updateSettings(next);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'The models available everywhere in the app: the model picker, cost estimator and “Copy as…”. Add any model with its context window and per-1M-token price. Only OpenAI’s GPT-4/4o/3.5 family gets an exact token count; everything else uses a calibrated estimate.',
        style: TextStyle(color: p.textSecondary, fontSize: 12.5, height: 1.45),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => save(s.clone()..hideBuiltinModels = !s.hideBuiltinModels),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(width: 24, height: 24, child: Checkbox(value: s.hideBuiltinModels, onChanged: (v) => save(s.clone()..hideBuiltinModels = v ?? false))),
                const SizedBox(width: 10),
                Text('Hide built-in models', style: TextStyle(fontSize: 13.5, color: p.text)),
              ]),
            ),
          ),
        ),
        Text('$total model${total == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: p.textTertiary)),
      ]),
      const SizedBox(height: 6),
      for (final g in groups)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _GroupTile(group: g, onTap: () => _openGroup(context, ref, g.name)),
        ),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(child: FilledButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('Add model'), onPressed: () => showAddModelDialog(context, ref))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.data_object, size: 18), label: const Text('Import JSON'), onPressed: () => showAddModelDialog(context, ref, startTab: 1))),
      ]),
      if (s.customModels.length >= 2)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: Icon(Icons.delete_sweep_outlined, color: p.red, size: 19),
            label: Text('Remove all ${s.customModels.length} custom models', style: TextStyle(color: p.red)),
            onPressed: () async {
              final ok = await confirmDialog(context, title: 'Remove all custom models?', message: 'Prompts keep working; token estimates fall back to the generic model if one of these was selected.', confirmLabel: 'Remove all', destructive: true);
              if (!ok) return;
              final next = s.clone()..customModels.clear();
              if (!kModels.any((m) => m.id == next.selectedModel)) next.selectedModel = 'generic';
              await save(next);
            },
          ),
        ),
      const SizedBox(height: 8),
    ]);
  }

  void _openGroup(BuildContext context, WidgetRef ref, String name) {
    showPfSheet<void>(context, title: name, full: true, builder: (_) => _GroupSheet(name: name));
  }
}

class _GroupTile extends StatelessWidget {
  final _Group group;
  final VoidCallback onTap;
  const _GroupTile({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final color = _groupColor(p, group.name);
    final n = group.models.length;
    final custom = group.customCount;
    return Material(
      color: p.surface2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(11), border: Border.all(color: color.withValues(alpha: 0.4))),
              child: Text(group.name.isEmpty ? '?' : group.name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 16)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                  const SizedBox(width: 8),
                  Text('$n model${n == 1 ? '' : 's'}${custom > 0 ? ' · $custom custom' : ''}', style: TextStyle(fontSize: 12, color: p.textTertiary)),
                ]),
                const SizedBox(height: 3),
                Text(group.models.take(3).map((m) => m.label).join(', ') + (n > 3 ? ', …' : ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
              ]),
            ),
            Icon(Icons.chevron_right, color: p.textTertiary),
          ]),
        ),
      ),
    );
  }
}

/// Every model of one group: search, edit, delete, select several and delete them together.
class _GroupSheet extends ConsumerStatefulWidget {
  final String name;
  const _GroupSheet({required this.name});

  @override
  ConsumerState<_GroupSheet> createState() => _GroupSheetState();
}

class _GroupSheetState extends ConsumerState<_GroupSheet> {
  final _q = TextEditingController();
  bool _selecting = false;
  final Set<String> _picked = {};

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final vn = ref.read(vaultProvider.notifier);
    final s = ref.watch(vaultProvider).data.settings;
    final customIds = {for (final m in s.customModels) m.id};
    final g = _groups(s).where((x) => x.name == widget.name).toList();
    final all = g.isEmpty ? <ModelSpec>[] : g.first.models;
    final q = _q.text.trim().toLowerCase();
    final shown = q.isEmpty ? all : all.where((m) => m.label.toLowerCase().contains(q) || m.vendor.toLowerCase().contains(q)).toList();
    final customShown = shown.where((m) => customIds.contains(m.id)).toList();

    Future<void> deleteIds(Set<String> ids) async {
      final ok = await confirmDialog(context, title: 'Delete ${ids.length} model${ids.length == 1 ? '' : 's'}?', message: 'They are removed from every model list.', confirmLabel: 'Delete', destructive: true);
      if (!ok) return;
      final next = s.clone()..customModels.removeWhere((m) => ids.contains(m.id));
      if (ids.contains(next.selectedModel)) next.selectedModel = 'generic';
      await vn.updateSettings(next);
      if (mounted) setState(() => _picked.removeAll(ids));
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          Expanded(child: SearchField(controller: _q, hint: 'Search ${all.length} models…', onChanged: (_) => setState(() {}))),
          if (customShown.isNotEmpty) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 14)),
              onPressed: () => setState(() {
                _selecting = !_selecting;
                _picked.clear();
              }),
              child: Text(_selecting ? 'Done' : 'Select'),
            ),
          ],
        ]),
      ),
      if (_selecting)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(children: [
            TextButton(onPressed: () => setState(() => _picked.addAll(customShown.map((m) => m.id))), child: Text('Select all ${customShown.length}')),
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: p.red, foregroundColor: Colors.white, minimumSize: const Size(0, 38)),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text('Delete ${_picked.length}'),
              onPressed: _picked.isEmpty ? null : () => deleteIds({..._picked}),
            ),
          ]),
        ),
      Flexible(
        child: shown.isEmpty
            ? const Padding(padding: EdgeInsets.all(28), child: Text('No models match.'))
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: shown.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: p.borderSubtle),
                itemBuilder: (c, i) {
                  final m = shown[i];
                  final custom = customIds.contains(m.id);
                  final on = _picked.contains(m.id);
                  return InkWell(
                    onTap: _selecting && custom ? () => setState(() => on ? _picked.remove(m.id) : _picked.add(m.id)) : (custom ? () => showAddModelDialog(context, ref, existing: s.customModels.firstWhere((x) => x.id == m.id)) : null),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        if (_selecting && custom) Padding(padding: const EdgeInsets.only(right: 10), child: Icon(on ? Icons.check_circle : Icons.radio_button_unchecked, color: on ? p.amber : p.textTertiary, size: 22)),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(m.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                            const SizedBox(height: 2),
                            Text('${_ctx(m.contextWindow)} · ${_price(m)}', style: TextStyle(fontSize: 12, color: p.textTertiary)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(custom ? 'Custom' : 'Built-in', custom ? p.green : p.textTertiary),
                        if (custom && !_selecting) ...[
                          IconButton(visualDensity: VisualDensity.compact, tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 19), onPressed: () => showAddModelDialog(context, ref, existing: s.customModels.firstWhere((x) => x.id == m.id))),
                          IconButton(visualDensity: VisualDensity.compact, tooltip: 'Delete', icon: Icon(Icons.delete_outline, size: 19, color: p.red), onPressed: () => deleteIds({m.id})),
                        ],
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

/// Adds or edits a model. New models can be filled in by hand, pasted as JSON or loaded from a .json file; an
/// existing model opens straight on the form.
Future<void> showAddModelDialog(BuildContext context, WidgetRef ref, {CustomModel? existing, int startTab = 0}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AddModelDialog(existing: existing, startTab: startTab),
  );
}

class _AddModelDialog extends ConsumerStatefulWidget {
  final CustomModel? existing;
  final int startTab;
  const _AddModelDialog({this.existing, this.startTab = 0});

  @override
  ConsumerState<_AddModelDialog> createState() => _AddModelDialogState();
}

class _AddModelDialogState extends ConsumerState<_AddModelDialog> {
  late int _tab = widget.existing != null ? 0 : widget.startTab;
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late final _vendor = TextEditingController(text: widget.existing?.vendor ?? '');
  late final _group = TextEditingController(text: widget.existing?.group ?? '');
  late final _ctx = TextEditingController(text: '${widget.existing?.contextWindow ?? 128000}');
  late final _pin = TextEditingController(text: _num(widget.existing?.priceIn ?? 0));
  late final _pout = TextEditingController(text: _num(widget.existing?.priceOut ?? 0));
  late final _note = TextEditingController(text: widget.existing?.priceNote ?? 'per 1M tokens');
  late final _cpt = TextEditingController(text: _num(widget.existing?.charsPerToken ?? 4.0));
  final _json = TextEditingController();
  String? _error;
  String? _fileName;
  String _fileText = '';

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    for (final c in [_label, _vendor, _group, _ctx, _pin, _pout, _note, _cpt, _json]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['json'], withData: true);
      if (r == null || r.files.isEmpty) return;
      final f = r.files.first;
      final text = f.bytes != null ? utf8.decode(f.bytes!, allowMalformed: true) : (f.path != null ? await File(f.path!).readAsString() : '');
      setState(() {
        _fileName = f.name;
        _fileText = text;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not read that file ($e).');
    }
  }

  Future<void> _submit() async {
    final vn = ref.read(vaultProvider.notifier);
    final s = ref.read(vaultProvider).data.settings.clone();
    if (_tab == 0) {
      final label = _label.text.trim();
      final ctx = int.tryParse(_ctx.text.trim().replaceAll(',', ''));
      if (label.isEmpty) return setState(() => _error = 'Give the model a name.');
      if (ctx == null || ctx <= 0) return setState(() => _error = 'Enter the context window as a positive number of tokens.');
      final cpt = double.tryParse(_cpt.text.trim()) ?? 4.0;
      final m = CustomModel(
        id: widget.existing?.id,
        label: label,
        vendor: _vendor.text.trim().isEmpty ? 'Custom' : _vendor.text.trim(),
        group: _group.text.trim(),
        contextWindow: ctx,
        charsPerToken: cpt > 0 ? cpt : 4.0,
        priceIn: (double.tryParse(_pin.text.trim()) ?? 0).clamp(0, double.infinity).toDouble(),
        priceOut: (double.tryParse(_pout.text.trim()) ?? 0).clamp(0, double.infinity).toDouble(),
        priceNote: _note.text.trim().isEmpty ? 'per 1M tokens' : _note.text.trim(),
      );
      final i = s.customModels.indexWhere((x) => x.id == m.id);
      if (i >= 0) {
        s.customModels[i] = m;
      } else {
        s.customModels.add(m);
      }
      await vn.updateSettings(s);
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, widget.existing == null ? 'Added “$label”' : 'Saved “$label”');
      return;
    }
    final raw = _tab == 1 ? _json.text : _fileText;
    final r = ModelImport.parse(_tab == 2 && _fileName == null ? '' : raw);
    if (r.models.isEmpty) return setState(() => _error = r.problems.isEmpty ? 'No models found.' : r.problems.first);
    var added = 0, updated = 0;
    for (final m in r.models) {
      final i = s.customModels.indexWhere((x) => x.label.toLowerCase() == m.label.toLowerCase() && x.vendor.toLowerCase() == m.vendor.toLowerCase());
      if (i >= 0) {
        m.id = s.customModels[i].id;
        s.customModels[i] = m;
        updated++;
      } else {
        s.customModels.add(m);
        added++;
      }
    }
    await vn.updateSettings(s);
    if (!mounted) return;
    final skipped = r.problems.length;
    Navigator.pop(context);
    toast(context, [if (added > 0) 'Added $added', if (updated > 0) 'updated $updated', if (skipped > 0) '$skipped skipped'].join(' · '));
  }

  Widget _field(String label, TextEditingController c, {String? hint, TextInputType? type, String? helper}) {
    final p = context.pf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(height: 6),
        TextField(controller: c, keyboardType: type, onChanged: (_) => setState(() => _error = null), decoration: InputDecoration(hintText: hint, isDense: true)),
        if (helper != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(helper, style: TextStyle(fontSize: 12, height: 1.4, color: p.textTertiary))),
      ]),
    );
  }

  Widget _manual() {
    final p = context.pf;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _field('Model name', _label, hint: 'e.g. Gemini 3'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _field('Vendor', _vendor, hint: 'e.g. Google')),
        const SizedBox(width: 12),
        Expanded(child: _field('Group', _group, hint: 'e.g. Gemini')),
      ]),
      Padding(
        padding: const EdgeInsets.only(bottom: 14, top: 0),
        child: Text('Models sharing a Group are clustered together in the model lists, e.g. all your GPT models under one “GPT” heading. Leave blank to use the vendor name.', style: TextStyle(fontSize: 12, height: 1.4, color: p.textTertiary)),
      ),
      _field('Context window (tokens)', _ctx, type: TextInputType.number, helper: 'e.g. Gemini 1.5 Pro — 1,000,000'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _field('Price in (\$ / 1M tok)', _pin, type: const TextInputType.numberWithOptions(decimal: true))),
        const SizedBox(width: 12),
        Expanded(child: _field('Price out (\$ / 1M tok)', _pout, type: const TextInputType.numberWithOptions(decimal: true))),
      ]),
      _field('Pricing note (optional)', _note),
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text('Advanced', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.textSecondary)),
          children: [_field('Characters per token', _cpt, type: const TextInputType.numberWithOptions(decimal: true), helper: 'Used for the token estimate. 4 is right for most English text.')],
        ),
      ),
    ]);
  }

  Widget _paste() {
    final p = context.pf;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Paste JSON', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
      const SizedBox(height: 6),
      TextField(
        controller: _json,
        minLines: 7,
        maxLines: 12,
        onChanged: (_) => setState(() => _error = null),
        style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 12.5),
        decoration: const InputDecoration(hintText: 'Paste a JSON object or array here…'),
      ),
      const SizedBox(height: 8),
      _example(),
    ]);
  }

  Widget _example() {
    final p = context.pf;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text('Example JSON format', style: TextStyle(fontSize: 13.5, color: p.textSecondary)),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.editorBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
            child: SelectableText(ModelImport.example, style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 12, height: 1.5, color: p.textSecondary)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() {
                _tab = 1;
                _json.text = ModelImport.example;
              }),
              child: const Text('Use this example'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _upload() {
    final p = context.pf;
    final preview = _fileName == null ? null : ModelImport.parse(_fileText);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Upload a .json file', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
      const SizedBox(height: 8),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _pickFile,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _fileName == null ? p.border : p.green.withValues(alpha: 0.6)), color: p.surface2),
          child: Column(children: [
            Icon(_fileName == null ? Icons.upload_file : Icons.task_alt, size: 30, color: _fileName == null ? p.textTertiary : p.green),
            const SizedBox(height: 8),
            Text(_fileName ?? 'Choose a .json file', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (preview != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(preview.models.isEmpty ? 'No models found in this file' : '${preview.models.length} model${preview.models.length == 1 ? '' : 's'} found${preview.problems.isEmpty ? '' : ' · ${preview.problems.length} will be skipped'}', style: TextStyle(fontSize: 12.5, color: preview.models.isEmpty ? p.red : p.textSecondary)),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      _example(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final editing = widget.existing != null;
    final canImport = _tab == 1 ? _json.text.trim().isNotEmpty : (_tab == 2 ? _fileName != null : true);
    final tabs = const ['Fill in manually', 'Paste JSON', 'Upload JSON file'];
    final maxH = MediaQuery.of(context).size.height * 0.88;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: p.border)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH, maxWidth: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 10, 12),
            child: Row(children: [
              Expanded(child: Text(editing ? 'Edit Model' : 'Add Model', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.2))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Divider(height: 1, color: p.border),
          if (!editing)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() {
                        _tab = i;
                        _error = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab == i ? p.amber : p.borderSubtle, width: _tab == i ? 2.4 : 1))),
                        child: Text(tabs[i], textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, height: 1.2, fontWeight: FontWeight.w700, color: _tab == i ? p.amber : p.textTertiary)),
                      ),
                    ),
                  ),
              ]),
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AnimatedSwitcher(duration: const Duration(milliseconds: 160), child: KeyedSubtree(key: ValueKey(_tab), child: _tab == 0 ? _manual() : (_tab == 1 ? _paste() : _upload()))),
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: p.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: p.red.withValues(alpha: 0.4))),
                    child: Row(children: [Icon(Icons.error_outline, size: 18, color: p.red), const SizedBox(width: 8), Expanded(child: Text(_error!, style: TextStyle(fontSize: 12.5, color: p.red)))]),
                  ),
                Text('Token counts for custom models use a calibrated estimate — only OpenAI’s GPT-4/4o/3.5 family gets the real, exact tokenizer built into this app.', style: TextStyle(fontSize: 12, height: 1.45, color: p.textTertiary)),
              ]),
            ),
          ),
          Divider(height: 1, color: p.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 20, 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(onPressed: canImport ? _submit : null, child: Text(_tab == 0 ? (editing ? 'Save model' : 'Add model') : 'Import')),
            ]),
          ),
        ]),
      ),
    );
  }
}
