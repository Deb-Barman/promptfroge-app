import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../core/constants.dart';
import '../../core/util.dart';
import '../../domain/engines/template_engine.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/fill_variables.dart';
import '../widgets/groups_ui.dart';

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
    if (mounted) setState(_sel.clear);
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

    return DefaultTabController(
      length: 2,
      child: Builder(builder: (context) {
        final tabs = DefaultTabController.of(context);
        return Scaffold(
          appBar: AppBar(
            leading: _sel.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_sel.clear)),
            title: Text(_sel.isEmpty ? 'Templates & snippets' : '${_sel.length} selected'),
            actions: _sel.isNotEmpty
                ? [
                    if (tabs.index == 0) IconButton(tooltip: 'Add to groups', icon: const Icon(Icons.folder_special_outlined), onPressed: () => showGroupMembership(context, kind: 'templates', ids: _sel.toList())),
                    IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _bulkDelete(tabs.index == 0)),
                  ]
                : [
              IconButton(
                tooltip: 'Manage groups',
                icon: const Icon(Icons.folder_special_outlined),
                onPressed: () => showGroupsManager(context, kind: 'templates', selectedId: _groupId, onSelect: (id) => setState(() => _groupId = id)),
              ),
            ],
            bottom: const TabBar(tabs: [Tab(text: 'Templates'), Tab(text: 'Snippets')]),
          ),
          floatingActionButton: ListenableBuilder(
            listenable: tabs,
            builder: (context, _) => FloatingActionButton.extended(
              onPressed: () => tabs.index == 0 ? _edit(null) : _editSnippet(null),
              icon: const Icon(Icons.add),
              label: Text(tabs.index == 0 ? 'New template' : 'New snippet'),
            ),
          ),
          body: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: SearchField(controller: _search, hint: 'Search', onChanged: (v) => setState(() => _q = v))),
            Expanded(
              child: TabBarView(children: [
                Column(children: [
                  SizedBox(
                    height: 40,
                    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                      Padding(padding: const EdgeInsets.only(right: 8), child: PfChip(label: 'All', selected: _cat == 'all', color: p.amber, onTap: () => setState(() => _cat = 'all'))),
                      for (final c in kCategories) Padding(padding: const EdgeInsets.only(right: 8), child: PfChip(label: c.label, selected: _cat == c.id, color: pfColor(c.color), onTap: () => setState(() => _cat = c.id))),
                    ]),
                  ),
                  GroupFilterBar(kind: 'templates', selectedId: _groupId, onChanged: (id) => setState(() => _groupId = id)),
                  Expanded(
                    child: templates.isEmpty
                        ? EmptyState(icon: Icons.article_outlined, title: 'No templates', body: 'Templates are prompts with {{variables}} you fill in each time. Save one from the editor menu or create one here.', actionLabel: 'New template', onAction: () => _edit(null))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            itemCount: templates.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (c, i) {
                              final t = templates[i];
                              final vars = TemplateEngine.extractVariables(t.body);
                              return PfCard(
                                onTap: _sel.isNotEmpty ? () => _toggleSel(t.id) : () => _use(t),
                                onLongPress: () => _toggleSel(t.id),
                                borderColor: _sel.contains(t.id) ? p.amber : null,
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(child: Text(t.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                                    StatusBadge(categoryById(t.category).label, pfColor(categoryById(t.category).color)),
                                    PopupMenuButton<String>(
                                      onSelected: (v) async {
                                        if (v == 'edit') _edit(t);
                                        if (v == 'groups') await showGroupMembership(context, kind: 'templates', ids: [t.id]);
                                        if (v == 'dup') await ref.read(vaultProvider.notifier).saveTemplate(Template(name: '${t.displayName} (copy)', body: t.body, category: t.category));
                                        if (v == 'delete') {
                                          final ok = await confirmDialog(context, title: 'Delete template?', message: '"${t.displayName}" is removed from your folder.', confirmLabel: 'Delete', destructive: true);
                                          if (ok) await ref.read(vaultProvider.notifier).deleteTemplate(t.id);
                                        }
                                      },
                                      itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'dup', child: Text('Duplicate')), PopupMenuItem(value: 'groups', child: Text('Groups…')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
                                    ),
                                  ]),
                                  Text(Utils.truncate(t.body.replaceAll('\n', ' '), 140), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 13)),
                                  const SizedBox(height: 6),
                                  Text('${vars.isEmpty ? 'No variables' : vars.map((v) => '{{$v}}').take(4).join('  ')} · used ${t.useCount}× · ${Utils.timeAgo(t.updatedAt)}', style: TextStyle(color: p.textTertiary, fontSize: 11.5)),
                                ]),
                              );
                            },
                          ),
                  ),
                ]),
                snippets.isEmpty
                    ? EmptyState(icon: Icons.bolt, title: 'No snippets', body: 'A snippet expands when you type its trigger (like /sig) in the editor.', actionLabel: 'New snippet', onAction: () => _editSnippet(null))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: snippets.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (c, i) {
                          final s = snippets[i];
                          return PfCard(
                            onTap: _sel.isNotEmpty ? () => _toggleSel(s.id) : () => _editSnippet(s),
                            onLongPress: () => _toggleSel(s.id),
                            borderColor: _sel.contains(s.id) ? p.amber : null,
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(s.trigger, style: TextStyle(color: p.amber, fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(Utils.truncate(s.body.replaceAll('\n', ' '), 120), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 13)),
                                  Text('used ${s.useCount}×', style: TextStyle(color: p.textTertiary, fontSize: 11.5)),
                                ]),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final ok = await confirmDialog(context, title: 'Delete snippet?', message: 'Snippet ${s.trigger} is removed.', confirmLabel: 'Delete', destructive: true);
                                  if (ok) await ref.read(vaultProvider.notifier).deleteSnippet(s.id);
                                },
                              ),
                            ]),
                          );
                        },
                      ),
              ]),
            ),
          ]),
        );
      }),
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
