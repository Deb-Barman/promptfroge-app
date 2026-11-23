import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../core/constants.dart';
import '../../core/util.dart';
import '../../domain/engines/template_engine.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/pf_chrome.dart';
import '../widgets/common.dart';
import '../../data/vault/vault_repository.dart' show VaultData;

const List<List<Object>> _customColors = [
  ['Violet', 0xFF9B7FE0],
  ['Blue', 0xFF5B8DEF],
  ['Green', 0xFF4FAE7A],
  ['Amber', 0xFFE8A33D],
  ['Red', 0xFFE55A5A],
  ['Teal', 0xFF4FC3D9],
];

/// Visual Builder: ordered, labelled blocks composed into a prompt body.
/// Canvas state lives here (the shell keeps this branch alive), like the original app's session state.
class BuilderScreen extends ConsumerStatefulWidget {
  const BuilderScreen({super.key});

  @override
  ConsumerState<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends ConsumerState<BuilderScreen> {
  final List<PromptBlock> _blocks = [];
  final Map<String, TextEditingController> _ctrls = {};
  bool _builtinOpen = false;

  @override
  void initState() {
    super.initState();
    _resetToDefault();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(PromptBlock b) => _ctrls.putIfAbsent(b.id, () => TextEditingController(text: b.text));

  void _dropCtrl(String id) => _ctrls.remove(id)?.dispose();

  void _resetToDefault() {
    for (final id in _ctrls.keys.toList()) {
      _dropCtrl(id);
    }
    _blocks
      ..clear()
      ..addAll(kDefaultBuilderOrder.map((t) => PromptBlock(type: t)));
  }

  void _syncTexts() {
    for (final b in _blocks) {
      b.text = _ctrls[b.id]?.text ?? b.text;
    }
  }

  bool get _hasText => _blocks.any((b) => (_ctrls[b.id]?.text ?? b.text).trim().isNotEmpty);

  void _addBlock(PromptBlock b) => setState(() => _blocks.add(b));

  void _applyDefs(List<PromptBlock> defs) {
    for (final id in _ctrls.keys.toList()) {
      _dropCtrl(id);
    }
    setState(() {
      _blocks
        ..clear()
        ..addAll(defs.map((d) => PromptBlock(type: d.type, label: d.label, color: d.color)));
    });
  }

  List<_StructureRow> _structures(VaultData d) {
    final builtins = [
      for (final s in kBuilderPresets)
        _StructureRow(s.id, s.name, true, [for (final b in s.blocks) PromptBlock(type: b.type, label: b.label, color: b.color)]),
    ];
    final custom = d.builderStructures.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [...builtins, ...custom.map((s) => _StructureRow(s.id, s.name, false, s.blocks))];
  }

  Future<void> _structuresSheet() async {
    await showPfSheet<void>(
      context,
      title: 'Structures',
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => Consumer(builder: (c, r, _) {
        final rows = _structures(r.watch(vaultProvider).data);
        final custom = rows.where((x) => !x.builtin).toList();
        final builtin = rows.where((x) => x.builtin).toList();
        Widget tile(_StructureRow s) => ListTile(
              title: Text(s.name),
              subtitle: Text(s.blocks.map((b) => TemplateEngine.blockLabel(b)).join(' → '), maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: s.builtin
                  ? const StatusBadge('Built-in', Color(0xFF7A8290))
                  : IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await confirmDialog(context, title: 'Delete this structure?', message: 'This can’t be undone.', confirmLabel: 'Delete', destructive: true);
                        if (ok) await ref.read(vaultProvider.notifier).deleteStructure(s.id);
                      },
                    ),
              onTap: () async {
                Navigator.pop(ctx);
                if (_hasText) {
                  final ok = await confirmDialog(context,
                      title: 'Replace current canvas?', message: 'Applying "${s.name}" replaces the blocks on the canvas. Text you wrote in them will be lost.', confirmLabel: 'Replace', destructive: true);
                  if (!ok) return;
                }
                _applyDefs(s.blocks);
                if (mounted) toast(context, 'Applied "${s.name}"');
              },
            );
        return ListView(shrinkWrap: true, children: [
          if (custom.isNotEmpty) ...[const SectionTitle('Your structures'), ...custom.map(tile)],
          ListTile(
            title: Text('Built-in (${builtin.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
            trailing: Icon(_builtinOpen || custom.isEmpty ? Icons.expand_less : Icons.expand_more),
            onTap: () => setSheet(() => _builtinOpen = !_builtinOpen),
          ),
          if (_builtinOpen || custom.isEmpty) ...builtin.map(tile),
          const Divider(),
          ListTile(leading: const Icon(Icons.add), title: const Text('New structure…'), onTap: () {
            Navigator.pop(ctx);
            _newStructure(fromCanvas: false);
          }),
          ListTile(leading: const Icon(Icons.bookmark_add_outlined), title: const Text('Save current canvas as structure…'), onTap: () {
            Navigator.pop(ctx);
            _newStructure(fromCanvas: true);
          }),
        ]);
      })),
    );
  }

  Future<void> _applyStructure(_StructureRow s) async {
    if (_hasText) {
      final ok = await confirmDialog(context, title: 'Replace current canvas?', message: 'Applying "${s.name}" replaces the blocks on the canvas. Text you wrote in them will be lost.', confirmLabel: 'Replace', destructive: true);
      if (!ok) return;
    }
    _applyDefs(s.blocks);
    if (mounted) toast(context, 'Applied "${s.name}"');
  }

  Future<void> _newStructure({required bool fromCanvas}) async {
    _syncTexts();
    final prefill = fromCanvas ? _blocks.map((b) => PromptBlock(type: b.type, label: b.label, color: b.color)).toList() : <PromptBlock>[];
    await showPfSheet<void>(
      context,
      title: 'New structure',
      full: true,
      builder: (ctx) => _NewStructureSheet(prefill: prefill),
    );
  }

  Future<void> _addCustom() async {
    final nameCtrl = TextEditingController();
    var colorIdx = 0;
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Add your own section'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: nameCtrl, autofocus: true, maxLength: 60, decoration: const InputDecoration(labelText: 'Section name', hintText: 'e.g. Tone, Persona Backstory, Safety Notes')),
            const SizedBox(height: 8),
            Wrap(spacing: 10, children: [
              for (var i = 0; i < _customColors.length; i++)
                GestureDetector(
                  onTap: () => setD(() => colorIdx = i),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(color: Color(_customColors[i][1] as int), shape: BoxShape.circle, border: Border.all(color: colorIdx == i ? c.pf.text : Colors.transparent, width: 2)),
                  ),
                ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add section')),
          ],
        ),
      ),
    );
    final label = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (added == true) {
      if (label.isEmpty) {
        if (mounted) toast(context, 'Give the section a name first.');
        return;
      }
      _addBlock(PromptBlock(type: 'custom_${Utils.uid('')}', label: label, color: _customColors[colorIdx][1] as int));
    }
  }

  Future<void> _addBlockSheet() async {
    await showPfSheet<void>(
      context,
      title: 'Add a block',
      builder: (ctx) => ListView(shrinkWrap: true, children: [
        for (final bt in kBlockTypes)
          ListTile(
            leading: Container(width: 4, height: 28, color: pfColor(bt.color)),
            title: Text(bt.label),
            subtitle: Text(bt.placeholder, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              Navigator.pop(ctx);
              _addBlock(PromptBlock(type: bt.id));
            },
          ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Add your own section…'),
          onTap: () {
            Navigator.pop(ctx);
            _addCustom();
          },
        ),
      ]),
    );
  }

  Future<void> _clear() async {
    if (_hasText) {
      final ok = await confirmDialog(context, title: 'Clear canvas?', message: 'All block text will be removed.', confirmLabel: 'Clear', destructive: true);
      if (!ok) return;
    }
    for (final id in _ctrls.keys.toList()) {
      _dropCtrl(id);
    }
    setState(_blocks.clear);
  }

  void _compose() {
    _syncTexts();
    final composed = TemplateEngine.composeFromBlocks(_blocks);
    if (composed.trim().isEmpty) {
      toast(context, 'Add some content to your blocks first.');
      return;
    }
    openInEditor(context, ref, seedBody: composed, seedFormat: 'text', seedBlocks: _blocks.map((b) => b.clone()).toList());
    toast(context, 'Composed into the editor.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final rows = _structures(ref.watch(vaultProvider).data);

    Widget label(String t, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Row(children: [
            Expanded(child: Text(t, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.textSecondary))),
            if (trailing != null) trailing,
          ]),
        );

    Widget structureRow(_StructureRow r) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _applyStructure(r),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: p.borderSubtle)),
                child: Row(children: [
                  Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: r.builtin ? p.surface3 : p.green.withOpacity(0.15), borderRadius: BorderRadius.circular(999)),
                    child: Text(r.builtin ? 'BUILT-IN' : 'YOURS', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: r.builtin ? p.textTertiary : p.green)),
                  ),
                ]),
              ),
            ),
          ),
        );

    Widget blockTypeRow(BlockType bt) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _addBlock(PromptBlock(type: bt.id)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border(left: BorderSide(color: pfColor(bt.color), width: 3), top: BorderSide(color: p.borderSubtle), right: BorderSide(color: p.borderSubtle), bottom: BorderSide(color: p.borderSubtle)),
                ),
                child: Row(children: [
                  Expanded(child: Text(bt.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                  Icon(Icons.add, size: 17, color: p.textTertiary),
                ]),
              ),
            ),
          ),
        );

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PfPageHeader(
          title: 'Visual Builder',
          subtitle: 'Add blocks from the palette, reorder them, then compose into a prompt.',
          actions: [
            PfBtn(label: 'Clear canvas', onPressed: _clear),
            PfBtn(label: 'Send to Editor', icon: Icons.north_east, primary: true, onPressed: _compose),
          ],
        ),
        label('Structures', trailing: IconButton(visualDensity: VisualDensity.compact, tooltip: 'New structure', icon: const Icon(Icons.add), onPressed: () => _newStructure(fromCanvas: false))),
        for (final r in rows) structureRow(r),
        OutlinedButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('New structure…'), onPressed: () => _newStructure(fromCanvas: false)),
        label('Block types'),
        for (final bt in kBlockTypes) blockTypeRow(bt),
        OutlinedButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('Add your own section…'), onPressed: _addCustom),
        label('Canvas'),
        if (_blocks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
            child: Column(children: [
              Icon(Icons.view_agenda_outlined, size: 34, color: p.textTertiary.withOpacity(0.6)),
              const SizedBox(height: 8),
              Text('Canvas is empty', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.textSecondary)),
              const SizedBox(height: 4),
              Text('Tap a block type or a structure above to start.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: p.textTertiary)),
            ]),
          ),
        const SizedBox(height: 4),
      ]),
    );

    return Scaffold(
      backgroundColor: p.bg,
      body: ReorderableListView.builder(
        header: header,
        padding: const EdgeInsets.only(bottom: 32),
        buildDefaultDragHandles: false,
        itemCount: _blocks.length,
        footer: _blocks.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(children: [
                  Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.add), label: const Text('Add block'), onPressed: _addBlockSheet)),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.bookmark_add_outlined), label: const Text('Save structure'), onPressed: () => _newStructure(fromCanvas: true))),
                ]),
              ),
              onReorder: (oldI, newI) {
                setState(() {
                  if (newI > oldI) newI -= 1;
                  final b = _blocks.removeAt(oldI);
                  _blocks.insert(newI, b);
                });
              },
              itemBuilder: (c, i) {
                final b = _blocks[i];
                final color = pfColor(TemplateEngine.blockColor(b));
                final bt = blockTypeById(b.type);
                return Padding(
                  key: ValueKey(b.id),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: p.border),
                    ),
                    child: IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Container(width: 4, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)))),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 8, 10),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.drag_indicator, size: 20, color: p.textTertiary))),
                                Expanded(child: Text(TemplateEngine.blockLabel(b), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13))),
                                IconButton(
                                  tooltip: 'Duplicate',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                                  onPressed: () {
                                    _syncTexts();
                                    final copy = PromptBlock(type: b.type, text: b.text, label: b.label, color: b.color);
                                    setState(() => _blocks.insert(i + 1, copy));
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  onPressed: () {
                                    _dropCtrl(b.id);
                                    setState(() => _blocks.removeAt(i));
                                  },
                                ),
                              ]),
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: TextField(
                                  controller: _ctrl(b),
                                  minLines: 2,
                                  maxLines: 10,
                                  onChanged: (v) => b.text = v,
                                  decoration: InputDecoration(hintText: bt?.placeholder ?? 'Write this section…', isDense: true),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              },
      ),
    );
  }
}

class _StructureRow {
  final String id;
  final String name;
  final bool builtin;
  final List<PromptBlock> blocks;
  _StructureRow(this.id, this.name, this.builtin, this.blocks);
}

// ------------------------------------------------------------ new structure

class _NewStructureSheet extends ConsumerStatefulWidget {
  final List<PromptBlock> prefill;
  const _NewStructureSheet({required this.prefill});

  @override
  ConsumerState<_NewStructureSheet> createState() => _NewStructureSheetState();
}

class _NewStructureSheetState extends ConsumerState<_NewStructureSheet> {
  final _name = TextEditingController();
  final _custom = TextEditingController();
  final _json = TextEditingController();
  bool _paste = false;
  final List<PromptBlock> _picked = []; // ordered

  @override
  void initState() {
    super.initState();
    _picked.addAll(widget.prefill.map((b) => PromptBlock(type: b.type, label: b.label, color: b.color)));
  }

  @override
  void dispose() {
    _name.dispose();
    _custom.dispose();
    _json.dispose();
    super.dispose();
  }

  bool _isPicked(String type) => _picked.any((b) => b.type == type);

  void _toggleBuiltin(BlockType bt) {
    setState(() {
      if (_isPicked(bt.id)) {
        _picked.removeWhere((b) => b.type == bt.id);
      } else {
        _picked.add(PromptBlock(type: bt.id));
      }
    });
  }

  void _addCustom() {
    final label = _custom.text.trim();
    if (label.isEmpty) {
      toast(context, 'Name the section first.');
      return;
    }
    setState(() {
      _picked.add(PromptBlock(type: 'custom_${Utils.uid('')}', label: label, color: _customColors[0][1] as int));
      _custom.clear();
    });
  }

  Future<void> _save() async {
    final vault = ref.read(vaultProvider.notifier);
    if (!_paste) {
      final name = _name.text.trim();
      if (name.isEmpty) return toast(context, 'Give the structure a name.');
      if (_picked.isEmpty) return toast(context, 'Pick at least one block.');
      await vault.saveStructure(BuilderStructure(name: name, blocks: _picked.map((b) => PromptBlock(type: b.type, label: b.label, color: b.color)).toList()));
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, '"$name" saved — pick it from Structures anytime.');
      return;
    }
    try {
      final records = _parseStructures(_json.text);
      if (records.isEmpty) return toast(context, 'No structures to import.');
      for (final r in records) {
        await vault.saveStructure(r);
      }
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, 'Added ${records.length} structure${records.length == 1 ? '' : 's'}.');
    } on FormatException catch (e) {
      toast(context, 'Invalid JSON: ${e.message}');
    }
  }

  /// Accepts `{name, blocks}` or an array of them. Blocks may be strings (a built-in id or label,
  /// otherwise a custom section) or `{type, label, color}`.
  static List<BuilderStructure> _parseStructures(String raw) {
    final decoded = jsonDecode(raw.trim().isEmpty ? '[]' : raw);
    final list = decoded is List ? decoded : [decoded];
    final out = <BuilderStructure>[];
    for (final item in list) {
      if (item is! Map) continue;
      final name = '${item['name'] ?? ''}'.trim();
      final blocksRaw = item['blocks'];
      if (name.isEmpty || blocksRaw is! List) continue;
      final blocks = <PromptBlock>[];
      for (final b in blocksRaw) {
        if (b is String) {
          final key = b.trim().toLowerCase();
          BlockType? bt;
          for (final t in kBlockTypes) {
            if (t.id == key || t.label.toLowerCase() == key) bt = t;
          }
          blocks.add(bt != null ? PromptBlock(type: bt.id) : PromptBlock(type: 'custom_${Utils.slug(b)}', label: b.trim(), color: _customColors[0][1] as int));
        } else if (b is Map) {
          final type = '${b['type'] ?? ''}'.trim();
          if (type.isEmpty) continue;
          final label = b['label'] == null ? null : '${b['label']}';
          final color = b['color'] is int ? b['color'] as int : (type.startsWith('custom_') ? _customColors[0][1] as int : null);
          blocks.add(PromptBlock(type: type, label: label, color: color));
        }
      }
      if (blocks.isNotEmpty) out.add(BuilderStructure(name: name, blocks: blocks));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ListView(shrinkWrap: true, children: [
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('Fill in')), ButtonSegment(value: true, label: Text('Paste JSON'))],
          selected: {_paste},
          onSelectionChanged: (s) => setState(() => _paste = s.first),
        ),
        const SizedBox(height: 12),
        if (!_paste) ...[
          TextField(controller: _name, maxLength: 80, decoration: const InputDecoration(labelText: 'Structure name', hintText: 'e.g. Image (Character + Background + Style)')),
          const SectionTitle('Blocks — tap in the order you want'),
          for (final bt in kBlockTypes)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _isPicked(bt.id),
              secondary: CircleAvatar(radius: 5, backgroundColor: pfColor(bt.color)),
              title: Text(bt.label),
              onChanged: (_) => _toggleBuiltin(bt),
            ),
          for (final b in _picked.where((b) => b.type.startsWith('custom_')))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 5, backgroundColor: pfColor(b.color ?? 0xFF9B7FE0)),
              title: Text(b.label ?? 'Section'),
              trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _picked.remove(b))),
            ),
          Row(children: [
            Expanded(child: TextField(controller: _custom, decoration: const InputDecoration(hintText: 'Custom section name, e.g. Character'), onSubmitted: (_) => _addCustom())),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _addCustom, child: const Text('Add')),
          ]),
          if (_picked.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Order: ${_picked.map((b) => TemplateEngine.blockLabel(b)).join(' → ')}', style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
            ),
        ] else ...[
          TextField(
            controller: _json,
            minLines: 8,
            maxLines: 14,
            style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 12.5),
            decoration: const InputDecoration(
              hintText: '[\n  { "name": "Basic", "blocks": ["Role", "Context", "Action", "Style"] },\n  { "name": "Image", "blocks": [{ "type": "custom_character", "label": "Character" }] }\n]',
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: Text(_paste ? 'Import' : 'Save structure')),
      ]),
    );
  }
}
