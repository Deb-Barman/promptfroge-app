import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../core/constants.dart';
import '../../domain/engines/template_engine.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/fill_variables.dart';
import '../widgets/groups_ui.dart';

class PatternsScreen extends ConsumerStatefulWidget {
  const PatternsScreen({super.key});

  @override
  ConsumerState<PatternsScreen> createState() => _PatternsScreenState();
}

class _PatternsScreenState extends ConsumerState<PatternsScreen> {
  final _search = TextEditingController();
  String _q = '';
  String _cat = 'All';
  String _tab = 'all'; // all | builtin | custom
  String? _groupId;
  final Set<String> _sel = {};

  void _toggleSel(String id) => setState(() => _sel.contains(id) ? _sel.remove(id) : _sel.add(id));

  Future<void> _bulkDelete() async {
    final d = ref.read(vaultProvider).data;
    final ids = _sel.where(d.customPatterns.containsKey).toList();
    if (ids.isEmpty) {
      toast(context, 'Built-in patterns can’t be deleted — only your own.');
      return;
    }
    final ok = await confirmDialog(context, title: 'Delete ${ids.length} custom pattern${ids.length == 1 ? '' : 's'}?', message: 'Built-in patterns in your selection are kept.', confirmLabel: 'Delete', destructive: true);
    if (!ok) return;
    final vn = ref.read(vaultProvider.notifier);
    for (final id in ids) {
      await vn.deletePattern(id);
    }
    if (mounted) setState(_sel.clear);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _use(PromptPattern pat) async {
    final text = await fillVariables(context, pat.template, title: pat.name, actionLabel: 'Open in editor');
    if (text == null || !mounted) return;
    if (!pat.builtin) {
      final c = pat.clone()..useCount += 1;
      await ref.read(vaultProvider.notifier).savePattern(c);
    }
    if (!mounted) return;
    openInEditor(context, ref, seedBody: text, seedTitle: pat.name);
  }

  Future<void> _detail(PromptPattern pat) async {
    final p = context.pf;
    await showPfSheet<void>(
      context,
      title: pat.name,
      full: true,
      builder: (ctx) {
        Widget block(String title, String body, {bool mono = false}) => body.trim().isEmpty
            ? const SizedBox.shrink()
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionTitle(title),
                PfCard(child: SelectableText(body, style: mono ? TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 12.5) : const TextStyle(fontSize: 13.5, height: 1.4))),
              ]);
        return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
          Wrap(spacing: 8, children: [StatusBadge(pat.category, p.blue), if (pat.builtin) const StatusBadge('Built-in', Color(0xFF7A8290))]),
          block('Purpose', pat.purpose),
          block('When to use', pat.when),
          block('Template', pat.template, mono: true),
          block('Example', pat.example, mono: true),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.copy, size: 18), label: const Text('Copy'), onPressed: () => copyToClipboard(ctx, pat.template))),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Use'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _use(pat);
                },
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            TextButton.icon(
              icon: const Icon(Icons.folder_special_outlined, size: 18),
              label: const Text('Groups…'),
              onPressed: () => showGroupMembership(ctx, kind: 'patterns', ids: [pat.id]),
            ),
            TextButton.icon(
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: Text(pat.builtin ? 'Save as my pattern' : 'Duplicate'),
              onPressed: () async {
                Navigator.pop(ctx);
                final copy = PromptPattern(name: pat.builtin ? pat.name : '${pat.name} (copy)', category: pat.category, purpose: pat.purpose, when: pat.when, template: pat.template, example: pat.example, variables: List.of(pat.variables));
                await ref.read(vaultProvider.notifier).savePattern(copy);
                if (mounted) toast(context, 'Saved to Patterns/');
              },
            ),
            if (!pat.builtin) ...[
              TextButton.icon(icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit'), onPressed: () {
                Navigator.pop(ctx);
                _edit(pat);
              }),
              TextButton.icon(
                icon: Icon(Icons.delete_outline, size: 18, color: p.red),
                label: Text('Delete', style: TextStyle(color: p.red)),
                onPressed: () async {
                  final ok = await confirmDialog(context, title: 'Delete pattern?', message: '"${pat.name}" is removed from your folder.', confirmLabel: 'Delete', destructive: true);
                  if (ok) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    await ref.read(vaultProvider.notifier).deletePattern(pat.id);
                  }
                },
              ),
            ],
          ]),
        ]);
      },
    );
  }

  Future<void> _edit(PromptPattern? pat) async {
    await showPfSheet<void>(context, title: pat == null ? 'New pattern' : 'Edit pattern', full: true, builder: (ctx) => _PatternForm(pattern: pat));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final d = ref.watch(vaultProvider).data;
    final all = [...kPatterns, ...d.customPatterns.values];
    final cats = <String>{for (final x in all) x.category}.toList()..sort();
    final q = _q.trim().toLowerCase();
    final group = _groupId == null ? null : d.groups[_groupId];
    final list = all.where((x) {
      if (_tab == 'builtin' && !x.builtin) return false;
      if (_tab == 'custom' && x.builtin) return false;
      if (group != null && !group.memberIds.contains(x.id)) return false;
      if (_cat != 'All' && x.category != _cat) return false;
      return q.isEmpty || '${x.name} ${x.purpose} ${x.when} ${x.template}'.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
          leading: _sel.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_sel.clear)),
          title: Text(_sel.isEmpty ? 'Patterns' : '${_sel.length} selected'),
          actions: _sel.isNotEmpty
              ? [
                  IconButton(tooltip: 'Add to groups', icon: const Icon(Icons.folder_special_outlined), onPressed: () => showGroupMembership(context, kind: 'patterns', ids: _sel.toList())),
                  IconButton(tooltip: 'Delete custom', icon: const Icon(Icons.delete_outline), onPressed: _bulkDelete),
                ]
              : [
        IconButton(
          tooltip: 'Manage groups',
          icon: const Icon(Icons.folder_special_outlined),
          onPressed: () => showGroupsManager(context, kind: 'patterns', selectedId: _groupId, onSelect: (id) => setState(() => _groupId = id)),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(null), icon: const Icon(Icons.add), label: const Text('New pattern')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: SearchField(controller: _search, hint: 'Search patterns', onChanged: (v) => setState(() => _q = v))),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final t in const [('all', 'All patterns'), ('builtin', 'Built-in'), ('custom', 'Yours')])
              Padding(padding: const EdgeInsets.only(right: 8), child: PfChip(label: t.$2, selected: _tab == t.$1, color: p.blue, onTap: () => setState(() => _tab = t.$1))),
          ]),
        ),
        GroupFilterBar(kind: 'patterns', selectedId: _groupId, onChanged: (id) => setState(() => _groupId = id)),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final c in ['All', ...cats]) Padding(padding: const EdgeInsets.only(right: 8), child: PfChip(label: c, selected: _cat == c, color: p.amber, onTap: () => setState(() => _cat = c))),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(icon: Icons.search_off, title: 'No patterns match', body: 'Try different words or another category.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (c, i) {
                    final x = list[i];
                    return PfCard(
                      onTap: _sel.isNotEmpty ? () => _toggleSel(x.id) : () => _detail(x),
                      onLongPress: () => _toggleSel(x.id),
                      borderColor: _sel.contains(x.id) ? p.amber : null,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                          if (!x.builtin) const StatusBadge('Yours', Color(0xFF4FAE7A)),
                        ]),
                        const SizedBox(height: 4),
                        Text(x.purpose, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 13)),
                        const SizedBox(height: 6),
                        Text('${x.category}${x.variables.isEmpty ? '' : ' · ${x.variables.length} variables'}', style: TextStyle(color: p.textTertiary, fontSize: 11.5)),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _PatternForm extends ConsumerStatefulWidget {
  final PromptPattern? pattern;
  const _PatternForm({this.pattern});

  @override
  ConsumerState<_PatternForm> createState() => _PatternFormState();
}

class _PatternFormState extends ConsumerState<_PatternForm> {
  late final _name = TextEditingController(text: widget.pattern?.name ?? '');
  late final _category = TextEditingController(text: widget.pattern?.category ?? 'Custom');
  late final _purpose = TextEditingController(text: widget.pattern?.purpose ?? '');
  late final _when = TextEditingController(text: widget.pattern?.when ?? '');
  late final _template = TextEditingController(text: widget.pattern?.template ?? '');
  late final _example = TextEditingController(text: widget.pattern?.example ?? '');

  @override
  void dispose() {
    for (final c in [_name, _category, _purpose, _when, _template, _example]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _template.text.trim().isEmpty) {
      toast(context, 'A pattern needs a name and a template.');
      return;
    }
    final base = widget.pattern?.clone() ?? PromptPattern();
    base
      ..name = _name.text.trim()
      ..category = _category.text.trim().isEmpty ? 'Custom' : _category.text.trim()
      ..purpose = _purpose.text.trim()
      ..when = _when.text.trim()
      ..template = _template.text
      ..example = _example.text
      ..variables = TemplateEngine.extractVariables(_template.text)
      ..builtin = false;
    await ref.read(vaultProvider.notifier).savePattern(base);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    Widget f(String label, TextEditingController c, {int min = 1, int max = 1, bool mono = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: c,
            minLines: min,
            maxLines: max,
            style: mono ? TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 13) : null,
            decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
          ),
        );
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
      f('Name', _name),
      f('Category', _category),
      f('Purpose', _purpose, min: 2, max: 4),
      f('When to use', _when, min: 2, max: 4),
      f('Template (use {{variables}})', _template, min: 6, max: 14, mono: true),
      f('Example', _example, min: 3, max: 10, mono: true),
      FilledButton(onPressed: _save, child: const Text('Save pattern')),
    ]);
  }
}
