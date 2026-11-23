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
import '../widgets/fill_variables.dart';
import '../widgets/groups_ui.dart';
import '../new_template_dialog.dart';

/// Templates (reusable prompts with {{variables}}) and snippets (/trigger text expansions).
class TemplatesScreen extends ConsumerStatefulWidget {
  const TemplatesScreen({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  final _search = TextEditingController();
  String _q = '';
  String _cat = 'all';
  String? _groupId;
  final Set<String> _sel = {};
  bool _selectMode = false;
  int _tab = 0;

  bool get _selecting => _selectMode || _sel.isNotEmpty;

  void _exitSelect() {
    _sel.clear();
    _selectMode = false;
  }

  void _toggleSel(String id) => setState(() => _sel.contains(id) ? _sel.remove(id) : _sel.add(id));

  Future<void> _bulkDelete(bool templates) async {
    final ids = _sel.toList();
    final noun = templates ? 'templates' : 'snippets';
    final ok = await confirmDialog(context, title: 'Delete ${ids.length} $noun?', message: 'They are removed from your folder.', confirmLabel: 'Delete', destructive: true);
    if (!ok) return;
    final vn = ref.read(vaultProvider.notifier);
    for (final id in ids) {
      templates ? await vn.deleteTemplate(id) : await vn.deleteSnippet(id);
    }
    if (mounted) setState(_exitSelect);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _use(Template t) async {
    final text = await fillVariables(context, t.body, title: t.displayName, actionLabel: 'Open in editor');
    if (text == null || !mounted) return;
    await ref.read(vaultProvider.notifier).incrementTemplateUse(t.id);
    if (!mounted) return;
    openInEditor(context, ref, seedBody: text, seedTitle: t.displayName);
  }

  Future<void> _edit(Template? t) async {
    await showPfSheet<void>(context, title: t == null ? 'New template' : 'Edit template', full: true, builder: (ctx) => _TemplateForm(template: t));
  }

  Future<void> _editSnippet(Snippet? s) async {
    await showPfSheet<void>(context, title: s == null ? 'New snippet' : 'Edit snippet', full: true, builder: (ctx) => _SnippetForm(snippet: s));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final d = ref.watch(vaultProvider).data;
    final q = _q.trim().toLowerCase();
    final group = _groupId == null ? null : d.groups[_groupId];
    final templates = d.templates.values.where((t) {
      if (_cat != 'all' && t.category != _cat) return false;
      if (group != null && !group.memberIds.contains(t.id)) return false;
      return q.isEmpty || '${t.name} ${t.body}'.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final snippets = d.snippets.values.where((s) => q.isEmpty || '${s.trigger} ${s.body}'.toLowerCase().contains(q)).toList()..sort((a, b) => a.trigger.compareTo(b.trigger));

    final mono = TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback);

    Widget tagChip(String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: p.surface3, borderRadius: BorderRadius.circular(5), border: Border.all(color: p.borderSubtle)),
          child: Text(t, style: mono.copyWith(fontSize: 11.5, color: p.textSecondary)),
        );

    Widget seg(int i, String label, int count) {
      final on = _tab == i;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() {
            _tab = i;
            _exitSelect();
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? p.amber : p.borderSubtle, width: on ? 2 : 1))),
            child: Text('$label ($count)', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: on ? p.amber : p.textTertiary)),
          ),
        ),
      );
    }

    final header = _selecting
        ? Padding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_sel.isEmpty ? 'Select items' : '${_sel.length} selected', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: p.text)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (_tab == 0) PfBtn(label: 'Add to group', icon: Icons.folder_special_outlined, primary: true, onPressed: _sel.isEmpty ? null : () => showGroupMembership(context, kind: 'templates', ids: _sel.toList())),
                PfBtn(label: 'Delete', icon: Icons.delete_outline, onPressed: _sel.isEmpty ? null : () => _bulkDelete(_tab == 0)),
                PfBtn(label: 'Done', onPressed: () => setState(_exitSelect)),
              ]),
            ]),
          )
        : PfPageHeader(
            title: _tab == 0 ? 'Templates' : 'Snippets',
            subtitle: _tab == 0 ? 'Reusable prompts with {{variables}} you fill in through a form. ${templates.length} ${templates.length == 1 ? 'template' : 'templates'}' : 'Short /triggers that expand into longer text while you type. ${snippets.length} ${snippets.length == 1 ? 'snippet' : 'snippets'}',
            actions: [
              PfBtn(label: 'Select', onPressed: () => setState(() => _selectMode = true)),
              PfBtn(label: _tab == 0 ? 'New Template' : 'New Snippet', icon: Icons.add, primary: true, onPressed: () => _tab == 0 ? showNewTemplateDialog(context, ref) : _editSnippet(null)),
              PfIconBtn(icon: Icons.folder_special_outlined, tooltip: 'Manage groups', onPressed: () => showGroupsManager(context, kind: 'templates', selectedId: _groupId, onSelect: (id) => setState(() => _groupId = id))),
            ],
          );

    Widget templateCard(Template t) {
      final vars = TemplateEngine.extractVariables(t.body);
      final selected = _sel.contains(t.id);
      return PfCard(
        padding: const EdgeInsets.all(18),
        onTap: _selecting ? () => _toggleSel(t.id) : () => _use(t),
        onLongPress: () => setState(() {
          _selectMode = true;
          _toggleSel(t.id);
        }),
        borderColor: selected ? p.amber : null,
        color: selected ? p.amber.withOpacity(0.06) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_selecting) Padding(padding: const EdgeInsets.only(right: 10, top: 1), child: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: selected ? p.amber : p.textTertiary)),
            Expanded(child: Text(t.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, height: 1.3))),
            if (!_selecting) ...[
              InkWell(onTap: () => _edit(t), child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.edit_outlined, size: 19, color: p.textSecondary))),
              InkWell(
                onTap: () async {
                  final ok = await confirmDialog(context, title: 'Delete template?', message: '"${t.displayName}" is removed from your folder.', confirmLabel: 'Delete', destructive: true);
                  if (ok) await ref.read(vaultProvider.notifier).deleteTemplate(t.id);
                },
                child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.delete_outline, size: 19, color: p.textSecondary)),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          Text(Utils.truncate(t.body.replaceAll('\n', ' '), 170), maxLines: 3, overflow: TextOverflow.ellipsis, style: mono.copyWith(color: p.textTertiary, fontSize: 13.5, height: 1.55)),
          if (vars.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final v in vars) tagChip('{{$v}}')]),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Text('Used ${t.useCount}x', style: mono.copyWith(fontSize: 12, color: p.textTertiary)),
            const Spacer(),
            Text(Utils.formatDate(t.updatedAt), style: mono.copyWith(fontSize: 12, color: p.textTertiary)),
          ]),
        ]),
      );
    }

    Widget snippetCard(Snippet s) {
      final selected = _sel.contains(s.id);
      return PfCard(
        padding: const EdgeInsets.all(18),
        onTap: _selecting ? () => _toggleSel(s.id) : () => _editSnippet(s),
        onLongPress: () => setState(() {
          _selectMode = true;
          _toggleSel(s.id);
        }),
        borderColor: selected ? p.amber : null,
        color: selected ? p.amber.withOpacity(0.06) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_selecting) Padding(padding: const EdgeInsets.only(right: 10, top: 1), child: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: selected ? p.amber : p.textTertiary)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.trigger, style: mono.copyWith(color: p.amber, fontWeight: FontWeight.w700, fontSize: 14.5)),
              const SizedBox(height: 6),
              Text(Utils.truncate(s.body.replaceAll('\n', ' '), 150), maxLines: 3, overflow: TextOverflow.ellipsis, style: mono.copyWith(color: p.textTertiary, fontSize: 13.5, height: 1.55)),
              const SizedBox(height: 10),
              Text('Used ${s.useCount}x', style: mono.copyWith(fontSize: 12, color: p.textTertiary)),
            ]),
          ),
          if (!_selecting)
            InkWell(
              onTap: () async {
                final ok = await confirmDialog(context, title: 'Delete snippet?', message: 'Snippet ${s.trigger} is removed.', confirmLabel: 'Delete', destructive: true);
                if (ok) await ref.read(vaultProvider.notifier).deleteSnippet(s.id);
              },
              child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.delete_outline, size: 19, color: p.textSecondary)),
            ),
        ]),
      );
    }

    final items = _tab == 0 ? templates.length : snippets.length;
    return Scaffold(
      backgroundColor: p.bg,
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              header,
              Row(children: [seg(0, 'Templates', d.templates.length), seg(1, 'Snippets', d.snippets.length)]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(flex: 3, child: SearchField(controller: _search, hint: _tab == 0 ? 'Search templates…' : 'Search snippets…', onChanged: (v) => setState(() => _q = v))),
                if (_tab == 0) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: PfSelect<String>(
                      value: _cat,
                      options: [const MapEntry('all', 'All categories'), for (final c in kCategories) MapEntry(c.id, c.label)],
                      onChanged: (v) => setState(() => _cat = v),
                    ),
                  ),
                ],
              ]),
              if (_tab == 0) GroupFilterBar(kind: 'templates', selectedId: _groupId, onChanged: (id) => setState(() => _groupId = id)),
              const SizedBox(height: 14),
            ]),
          ),
        ),
        if (items == 0)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _tab == 0
                ? EmptyState(icon: Icons.web_asset_outlined, title: 'No templates yet', body: 'Turn a prompt you write often into a reusable template with {{variables}}.', actionLabel: 'Create a template', onAction: () => showNewTemplateDialog(context, ref))
                : EmptyState(icon: Icons.bolt, title: 'No snippets yet', body: 'A snippet expands when you type its trigger (like /sig) in the editor.', actionLabel: 'Create a snippet', onAction: () => _editSnippet(null)),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverList.separated(
              itemCount: items,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (c, i) => _tab == 0 ? templateCard(templates[i]) : snippetCard(snippets[i]),
            ),
          ),
      ]),
    );
  }
}

class _TemplateForm extends ConsumerStatefulWidget {
  final Template? template;
  const _TemplateForm({this.template});

  @override
  ConsumerState<_TemplateForm> createState() => _TemplateFormState();
}

class _TemplateFormState extends ConsumerState<_TemplateForm> {
  late final _name = TextEditingController(text: widget.template?.name ?? '');
  late final _body = TextEditingController(text: widget.template?.body ?? '');
  late String _cat = widget.template?.category ?? 'custom';

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _body.text.trim().isEmpty) {
      toast(context, 'A template needs a name and some text.');
      return;
    }
    final base = widget.template?.clone() ?? Template();
    base
      ..name = _name.text.trim()
      ..body = _body.text
      ..category = _cat;
    await ref.read(vaultProvider.notifier).saveTemplate(base);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final vars = TemplateEngine.extractVariables(_body.text);
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
      TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name'), textCapitalization: TextCapitalization.sentences),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: kCategories.any((c) => c.id == _cat) ? _cat : 'custom',
        decoration: const InputDecoration(labelText: 'Category'),
        items: [for (final c in kCategories) DropdownMenuItem(value: c.id, child: Text(c.label))],
        onChanged: (v) => setState(() => _cat = v ?? 'custom'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _body,
        minLines: 8,
        maxLines: 16,
        onChanged: (_) => setState(() {}),
        style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 13),
        decoration: const InputDecoration(labelText: 'Template text', hintText: 'Write the prompt. Use {{name}}, {{name:number}}, {{name:select:a|b}} or {{name=default}}.', alignLabelWithHint: true),
      ),
      if (vars.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, children: [for (final v in vars) Chip(label: Text('{{$v}}'), visualDensity: VisualDensity.compact)])),
      const SizedBox(height: 16),
      FilledButton(onPressed: _save, child: const Text('Save template')),
    ]);
  }
}

class _SnippetForm extends ConsumerStatefulWidget {
  final Snippet? snippet;
  const _SnippetForm({this.snippet});

  @override
  ConsumerState<_SnippetForm> createState() => _SnippetFormState();
}

class _SnippetFormState extends ConsumerState<_SnippetForm> {
  late final _trigger = TextEditingController(text: widget.snippet?.trigger ?? '/');
  late final _body = TextEditingController(text: widget.snippet?.body ?? '');

  @override
  void dispose() {
    _trigger.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    var t = _trigger.text.trim().replaceAll(RegExp(r'\s+'), '');
    if (!t.startsWith('/')) t = '/$t';
    if (t.length < 2 || _body.text.trim().isEmpty) {
      toast(context, 'A snippet needs a trigger (like /sig) and some text.');
      return;
    }
    final d = ref.read(vaultProvider).data;
    final clash = d.snippets.values.any((s) => s.trigger.toLowerCase() == t.toLowerCase() && s.id != widget.snippet?.id);
    if (clash) {
      toast(context, 'Another snippet already uses $t.');
      return;
    }
    final base = widget.snippet?.clone() ?? Snippet();
    base
      ..trigger = t
      ..body = _body.text;
    await ref.read(vaultProvider.notifier).saveSnippet(base);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
      TextField(controller: _trigger, autocorrect: false, decoration: const InputDecoration(labelText: 'Trigger', hintText: '/sig')),
      const SizedBox(height: 12),
      TextField(controller: _body, minLines: 6, maxLines: 14, decoration: const InputDecoration(labelText: 'Expands to', alignLabelWithHint: true)),
      const SizedBox(height: 16),
      FilledButton(onPressed: _save, child: const Text('Save snippet')),
    ]);
  }
}
