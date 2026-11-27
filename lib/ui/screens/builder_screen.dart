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

  Future<void> _editStructure(BuilderStructure st) async {
    await showPfSheet<void>(
      context,
      title: 'Edit structure',
      full: true,
      builder: (ctx) => _NewStructureSheet(prefill: st.blocks, existing: st),
    );
  }

  Future<void> _duplicateStructure(_StructureRow r) async {
    final copy = BuilderStructure(name: r.builtin ? r.name : '${r.name} (copy)', blocks: [for (final b in r.blocks) PromptBlock(type: b.type, label: b.label, color: b.color)]);
    await ref.read(vaultProvider.notifier).saveStructure(copy);
    if (mounted) toast(context, 'Saved “${copy.name}” to your structures');
  }

  Future<void> _manageStructures() async {
    await showPfSheet<void>(
      context,
      title: 'Manage structures',
      full: true,
      builder: (ctx) => _StructuresManager(
        onApply: (r) {
          Navigator.pop(ctx);
          _applyStructure(r);
        },
        onEdit: (st) {
          Navigator.pop(ctx);
          _editStructure(st);
        },
        onDuplicate: _duplicateStructure,
        onNew: () {
          Navigator.pop(ctx);
          _newStructure(fromCanvas: false);
        },
      ),
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
    final rows = _buildStructureRows(ref.watch(vaultProvider).data);

    Widget label(String t, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Row(children: [
            Expanded(child: Text(t, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.textSecondary))),
            if (trailing != null) trailing,
          ]),
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
        label('Structures', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: p.surface3, borderRadius: BorderRadius.circular(10)),
            child: Text('${rows.length}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.textTertiary)),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.tune, size: 17),
            label: const Text('Manage'),
            onPressed: _manageStructures,
          ),
          IconButton(visualDensity: VisualDensity.compact, tooltip: 'New structure', icon: const Icon(Icons.add), onPressed: () => _newStructure(fromCanvas: false)),
        ])),
        SizedBox(
          height: 98,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              for (final r in (() {
                // yours first (newest first), then the built-ins; the carousel is capped, Manage shows everything
                final mine = rows.where((x) => !x.builtin).toList();
                final built = rows.where((x) => x.builtin).toList();
                return [...mine, ...built].take(14);
              })())
                _StructureCard(row: r, onTap: () => _applyStructure(r), onLong: _manageStructures),
              if (rows.length > 14) _MoreCard(count: rows.length - 14, onTap: _manageStructures),
            ],
          ),
        ),
        label('Block palette', trailing: Text('tap to add', style: TextStyle(fontSize: 12, color: p.textTertiary))),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final bt in kBlockTypes) _PalettePill(label: bt.label, color: pfColor(bt.color), onTap: () => _addBlock(PromptBlock(type: bt.id))),
            _PalettePill(label: 'Your own', color: p.textSecondary, icon: Icons.add, onTap: _addCustom),
          ]),
        ),
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

List<_StructureRow> _buildStructureRows(VaultData d) {
  final builtins = [
    for (final s in kBuilderPresets) _StructureRow(s.id, s.name, true, [for (final b in s.blocks) PromptBlock(type: b.type, label: b.label, color: b.color)]),
  ];
  final custom = d.builderStructures.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return [...builtins, ...custom.map((s) => _StructureRow(s.id, s.name, false, s.blocks))];
}

// ------------------------------------------------------------- small widgets

class _StructureCard extends StatelessWidget {
  final _StructureRow row;
  final VoidCallback onTap;
  final VoidCallback onLong;
  const _StructureCard({required this.row, required this.onTap, required this.onLong});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final colors = [for (final b in row.blocks.take(8)) pfColor(TemplateEngine.blockColor(b))];
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 176,
        child: Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            onLongPress: onLong,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: row.builtin ? p.borderSubtle : p.green.withValues(alpha: 0.45))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(row.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.25))),
                Row(children: [
                  for (final c in colors) Container(width: 9, height: 9, margin: const EdgeInsets.only(right: 3), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                  const Spacer(),
                  Text('${row.blocks.length}', style: TextStyle(fontSize: 11.5, color: p.textTertiary, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: row.builtin ? p.surface3 : p.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                    child: Text(row.builtin ? 'BUILT-IN' : 'YOURS', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: row.builtin ? p.textTertiary : p.green)),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreCard extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _MoreCard({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return SizedBox(
      width: 120,
      child: Material(
        color: p.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.amber.withValues(alpha: 0.5))),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('+$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.amber)),
              Text('View all', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.amber)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PalettePill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final VoidCallback onTap;
  const _PalettePill({required this.label, required this.color, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.55))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon ?? Icons.add, size: 15, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ manager

/// All structures in one searchable list: apply, edit, duplicate or delete them, or select several to delete at
/// once. Built for dozens of structures: it scrolls inside the sheet and takes no room on the builder page.
class _StructuresManager extends ConsumerStatefulWidget {
  final ValueChanged<_StructureRow> onApply;
  final ValueChanged<BuilderStructure> onEdit;
  final ValueChanged<_StructureRow> onDuplicate;
  final VoidCallback onNew;
  const _StructuresManager({required this.onApply, required this.onEdit, required this.onDuplicate, required this.onNew});

  @override
  ConsumerState<_StructuresManager> createState() => _StructuresManagerState();
}

class _StructuresManagerState extends ConsumerState<_StructuresManager> {
  final _q = TextEditingController();
  String _filter = 'all'; // all | yours | builtin
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
    final d = ref.watch(vaultProvider).data;
    final all = _buildStructureRows(d);
    final mine = all.where((r) => !r.builtin).length;
    final q = _q.text.trim().toLowerCase();
    final shown = [
      for (final r in all)
        if ((_filter == 'all' || (_filter == 'yours' && !r.builtin) || (_filter == 'builtin' && r.builtin)) && (q.isEmpty || r.name.toLowerCase().contains(q) || r.blocks.any((b) => TemplateEngine.blockLabel(b).toLowerCase().contains(q)))) r,
    ]..sort((a, b) => a.builtin == b.builtin ? 0 : (a.builtin ? 1 : -1));

    Future<void> delete(Set<String> ids) async {
      final ok = await confirmDialog(context, title: 'Delete ${ids.length} structure${ids.length == 1 ? '' : 's'}?', message: 'This can’t be undone.', confirmLabel: 'Delete', destructive: true);
      if (!ok) return;
      for (final id in ids) {
        await ref.read(vaultProvider.notifier).deleteStructure(id);
      }
      if (mounted) setState(() => _picked.removeAll(ids));
    }

    Widget filterChip(String id, String label, int n) {
      final on = _filter == id;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _filter = id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(color: on ? p.amber.withValues(alpha: 0.16) : p.surface2, borderRadius: BorderRadius.circular(18), border: Border.all(color: on ? p.amber : p.border)),
            child: Text('$label · $n', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? p.amber : p.textSecondary)),
          ),
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          Expanded(child: SearchField(controller: _q, hint: 'Search ${all.length} structures…', onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 14)), icon: const Icon(Icons.add, size: 18), label: const Text('New'), onPressed: widget.onNew),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          filterChip('all', 'All', all.length),
          filterChip('yours', 'Yours', mine),
          filterChip('builtin', 'Built-in', all.length - mine),
          const Spacer(),
          if (mine > 0)
            TextButton(
              onPressed: () => setState(() {
                _selecting = !_selecting;
                _picked.clear();
              }),
              child: Text(_selecting ? 'Done' : 'Select'),
            ),
        ]),
      ),
      if (_selecting)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            TextButton(onPressed: () => setState(() => _picked.addAll(shown.where((r) => !r.builtin).map((r) => r.id))), child: const Text('Select all yours')),
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: p.red, foregroundColor: Colors.white, minimumSize: const Size(0, 38)),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text('Delete ${_picked.length}'),
              onPressed: _picked.isEmpty ? null : () => delete({..._picked}),
            ),
          ]),
        ),
      Flexible(
        child: shown.isEmpty
            ? const Padding(padding: EdgeInsets.all(28), child: Text('No structures match.'))
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: shown.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (c, i) {
                  final r = shown[i];
                  final on = _picked.contains(r.id);
                  final st = r.builtin ? null : d.builderStructures[r.id];
                  return Material(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _selecting ? (r.builtin ? null : () => setState(() => on ? _picked.remove(r.id) : _picked.add(r.id))) : () => widget.onApply(r),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? p.amber : p.borderSubtle)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            if (_selecting && !r.builtin) Padding(padding: const EdgeInsets.only(right: 10), child: Icon(on ? Icons.check_circle : Icons.radio_button_unchecked, size: 22, color: on ? p.amber : p.textTertiary)),
                            Expanded(child: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
                            const SizedBox(width: 8),
                            StatusBadge(r.builtin ? 'Built-in' : 'Yours', r.builtin ? p.textTertiary : p.green),
                          ]),
                          const SizedBox(height: 8),
                          Wrap(spacing: 5, runSpacing: 5, children: [
                            for (final b in r.blocks.take(7))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: pfColor(TemplateEngine.blockColor(b)).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                                child: Text(TemplateEngine.blockLabel(b), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: pfColor(TemplateEngine.blockColor(b)))),
                              ),
                            if (r.blocks.length > 7) Padding(padding: const EdgeInsets.only(top: 3), child: Text('+${r.blocks.length - 7}', style: TextStyle(fontSize: 11.5, color: p.textTertiary))),
                          ]),
                          if (!_selecting) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              TextButton.icon(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), icon: const Icon(Icons.north_east, size: 16), label: const Text('Use'), onPressed: () => widget.onApply(r)),
                              if (st != null) TextButton.icon(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit'), onPressed: () => widget.onEdit(st)),
                              TextButton.icon(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), icon: const Icon(Icons.copy_all_outlined, size: 16), label: Text(r.builtin ? 'Copy to edit' : 'Duplicate'), onPressed: () => widget.onDuplicate(r)),
                              const Spacer(),
                              if (!r.builtin) IconButton(visualDensity: VisualDensity.compact, tooltip: 'Delete', icon: Icon(Icons.delete_outline, size: 20, color: p.red), onPressed: () => delete({r.id})),
                            ]),
                          ],
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

// ------------------------------------------------------------ new / edit structure

class _NewStructureSheet extends ConsumerStatefulWidget {
  final List<PromptBlock> prefill;
  final BuilderStructure? existing;
  const _NewStructureSheet({required this.prefill, this.existing});

  @override
  ConsumerState<_NewStructureSheet> createState() => _NewStructureSheetState();
}

class _NewStructureSheetState extends ConsumerState<_NewStructureSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
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
      final blocks = _picked.map((b) => PromptBlock(type: b.type, label: b.label, color: b.color)).toList();
      final ex = widget.existing;
      await vault.saveStructure(ex == null ? BuilderStructure(name: name, blocks: blocks) : BuilderStructure(id: ex.id, name: name, blocks: blocks, createdAt: ex.createdAt));
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, ex == null ? '“$name” saved — pick it from Structures anytime.' : '“$name” updated.');
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
    final editing = widget.existing != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ListView(shrinkWrap: true, children: [
        if (!editing) ...[
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('Fill in')), ButtonSegment(value: true, label: Text('Paste JSON'))],
            selected: {_paste},
            onSelectionChanged: (s) => setState(() => _paste = s.first),
          ),
          const SizedBox(height: 12),
        ],
        if (!_paste) ...[
          TextField(controller: _name, maxLength: 80, decoration: const InputDecoration(labelText: 'Structure name', hintText: 'e.g. Image (Character + Background + Style)')),
          const SectionTitle('Blocks — tap to add or remove'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final bt in kBlockTypes)
              GestureDetector(
                onTap: () => _toggleBuiltin(bt),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: pfColor(bt.color).withValues(alpha: _isPicked(bt.id) ? 0.22 : 0.07),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: pfColor(bt.color).withValues(alpha: _isPicked(bt.id) ? 0.9 : 0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_isPicked(bt.id) ? Icons.check : Icons.add, size: 15, color: pfColor(bt.color)),
                    const SizedBox(width: 5),
                    Text(bt.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: pfColor(bt.color))),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _custom, decoration: const InputDecoration(hintText: 'Custom section, e.g. Character'), onSubmitted: (_) => _addCustom())),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _addCustom, child: const Text('Add')),
          ]),
          if (_picked.isNotEmpty) ...[
            SectionTitle('Order — drag to rearrange (${_picked.length})'),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (o, n) => setState(() {
                if (n > o) n -= 1;
                _picked.insert(n, _picked.removeAt(o));
              }),
              children: [
                for (var i = 0; i < _picked.length; i++)
                  Container(
                    key: ValueKey('${_picked[i].id}'),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: pfColor(TemplateEngine.blockColor(_picked[i])), width: 4))),
                    child: ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text('${i + 1}.  ${TemplateEngine.blockLabel(_picked[i])}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _picked.removeAt(i))),
                        ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.drag_indicator, color: p.textTertiary))),
                      ]),
                    ),
                  ),
              ],
            ),
          ],
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
        FilledButton(onPressed: _save, child: Text(_paste ? 'Import' : (editing ? 'Save changes' : 'Save structure'))),
      ]),
    );
  }
}
