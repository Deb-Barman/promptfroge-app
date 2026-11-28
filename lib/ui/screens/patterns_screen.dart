import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../core/constants.dart';
import '../../domain/engines/template_engine.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/pf_chrome.dart';
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
  bool _selectMode = false;

  bool get _selecting => _selectMode || _sel.isNotEmpty;

  void _exitSelect() {
    _sel.clear();
    _selectMode = false;
  }

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
    if (mounted) setState(_exitSelect);
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

    final nBuiltin = all.where((x) => x.builtin).length;
    final nCustom = all.length - nBuiltin;

    Widget tab(String id, String label, int n) {
      final on = _tab == id;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = id),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? p.amber : p.borderSubtle, width: on ? 2 : 1))),
            child: Text('$label ($n)', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: on ? p.amber : p.textTertiary)),
          ),
        ),
      );
    }

    final header = _selecting
        ? Padding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_sel.isEmpty ? 'Select patterns' : '${_sel.length} selected', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: p.text)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                PfBtn(label: 'Add to group', icon: Icons.folder_special_outlined, primary: true, onPressed: _sel.isEmpty ? null : () => showGroupMembership(context, kind: 'patterns', ids: _sel.toList())),
                PfBtn(label: 'Delete custom', icon: Icons.delete_outline, onPressed: _sel.isEmpty ? null : _bulkDelete),
                PfBtn(label: 'Done', onPressed: () => setState(_exitSelect)),
              ]),
            ]),
          )
        : PfPageHeader(
            title: 'Pattern Library',
            subtitle: '$nBuiltin built-in ${nBuiltin == 1 ? 'pattern' : 'patterns'}${nCustom > 0 ? ' · $nCustom of your own' : ''}',
            actions: [
              PfBtn(label: 'Select', onPressed: () => setState(() => _selectMode = true)),
              PfBtn(label: 'Add Pattern', icon: Icons.add, primary: true, onPressed: () => _edit(null)),
              PfIconBtn(icon: Icons.folder_special_outlined, tooltip: 'Manage groups', onPressed: () => showGroupsManager(context, kind: 'patterns', selectedId: _groupId, onSelect: (id) => setState(() => _groupId = id))),
            ],
          );

    Widget card(PromptPattern x) {
      final selected = _sel.contains(x.id);
      return PfCard(
        padding: const EdgeInsets.all(18),
        onTap: _selecting ? () => _toggleSel(x.id) : () => _detail(x),
        onLongPress: () => setState(() {
          _selectMode = true;
          _toggleSel(x.id);
        }),
        borderColor: selected ? p.amber : null,
        color: selected ? p.amber.withOpacity(0.06) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_selecting) Padding(padding: const EdgeInsets.only(right: 10), child: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: selected ? p.amber : p.textTertiary)),
            Expanded(child: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, height: 1.3))),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: x.builtin ? p.surface3 : p.green.withOpacity(0.15), borderRadius: BorderRadius.circular(999)),
              child: Text(x.builtin ? x.category.toUpperCase() : 'YOURS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: x.builtin ? p.textTertiary : p.green)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(x.purpose, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textTertiary, fontSize: 13.5, height: 1.5)),
        ]),
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              header,
              Row(children: [tab('all', 'All', all.length), tab('builtin', 'Built-in', nBuiltin), tab('custom', 'My Patterns', nCustom)]),
              const SizedBox(height: 14),
              SearchField(controller: _search, hint: 'Search ${all.length} patterns…', onChanged: (v) => setState(() => _q = v)),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final c in ['All', ...cats])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _cat = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: _cat == c ? p.amber.withValues(alpha: 0.16) : p.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: _cat == c ? p.amber.withValues(alpha: 0.8) : p.border)),
                          child: Text(c == 'All' ? 'All types' : c, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _cat == c ? p.amber : p.textSecondary)),
                        ),
                      ),
                    ),
                ]),
              ),
              GroupFilterBar(kind: 'patterns', selectedId: _groupId, padding: EdgeInsets.zero, onChanged: (id) => setState(() => _groupId = id)),
              const SizedBox(height: 14),
            ]),
          ),
        ),
        if (list.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Icons.search_off, title: 'No patterns match', body: 'Try different words or another type.'))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverList.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (c, i) => card(list[i]),
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
