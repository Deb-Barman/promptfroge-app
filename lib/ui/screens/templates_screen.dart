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
  final ScrollController _scroll = ScrollController();
  int _perPage = 50; // 0 = all
  int _page = 0;
  String _sig = '';

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
    _scroll.dispose();
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

    Widget selectMark(bool selected) => Padding(padding: const EdgeInsets.only(right: 10, top: 2), child: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: selected ? p.amber : p.textTertiary));

    Widget templateCard(Template t) {
      final vars = TemplateEngine.extractVariables(t.body);
      final selected = _sel.contains(t.id);
      final cat = categoryById(t.category);
      return PfCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
        onTap: _selecting ? () => _toggleSel(t.id) : () => _use(t),
        onLongPress: () => setState(() {
          _selectMode = true;
          _toggleSel(t.id);
        }),
        borderColor: selected ? p.amber : null,
        color: selected ? p.amber.withValues(alpha: 0.06) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_selecting) selectMark(selected),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2, right: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.25)),
                  const SizedBox(height: 5),
                  Row(children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: pfColor(cat.color), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(cat.label, style: TextStyle(fontSize: 11.5, color: p.textTertiary, fontWeight: FontWeight.w600)),
                    if (vars.isNotEmpty) Text('  ·  ${vars.length} variable${vars.length == 1 ? '' : 's'}', style: TextStyle(fontSize: 11.5, color: p.textTertiary)),
                  ]),
                ]),
              ),
            ),
            if (!_selecting)
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: Icon(Icons.more_vert, size: 20, color: p.textTertiary),
                onSelected: (v) async {
                  if (v == 'use') _use(t);
                  if (v == 'edit') _edit(t);
                  if (v == 'copy') copyToClipboard(context, t.body, message: 'Template text copied');
                  if (v == 'dup') {
                    final c = Template()
                      ..name = '${t.name} (copy)'
                      ..body = t.body
                      ..category = t.category;
                    await ref.read(vaultProvider.notifier).saveTemplate(c);
                    if (mounted) toast(context, 'Duplicated');
                  }
                  if (v == 'delete') {
                    final ok = await confirmDialog(context, title: 'Delete template?', message: '"${t.displayName}" is removed from your folder.', confirmLabel: 'Delete', destructive: true);
                    if (ok) await ref.read(vaultProvider.notifier).deleteTemplate(t.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'use', child: Text('Fill in & open in editor')),
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'copy', child: Text('Copy template text')),
                  PopupMenuItem(value: 'dup', child: Text('Duplicate')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
          ]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(Utils.truncate(t.body.replaceAll(RegExp(r'\s+'), ' '), 200), maxLines: 2, overflow: TextOverflow.ellipsis, style: mono.copyWith(color: p.textTertiary, fontSize: 12.5, height: 1.5)),
          ),
          if (vars.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 26,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(right: 8), children: [for (final v in vars) Padding(padding: const EdgeInsets.only(right: 6), child: tagChip('{{$v}}'))]),
            ),
          ],
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              Expanded(child: Text('Used ${t.useCount}× · ${Utils.formatDate(t.updatedAt, withTime: false)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: mono.copyWith(fontSize: 11.5, color: p.textTertiary))),
              if (!_selecting)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 14), visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Use'),
                  onPressed: () => _use(t),
                ),
            ]),
          ),
        ]),
      );
    }

    Widget snippetCard(Snippet s) {
      final selected = _sel.contains(s.id);
      return PfCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        onTap: _selecting ? () => _toggleSel(s.id) : () => _editSnippet(s),
        onLongPress: () => setState(() {
          _selectMode = true;
          _toggleSel(s.id);
        }),
        borderColor: selected ? p.amber : null,
        color: selected ? p.amber.withValues(alpha: 0.06) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_selecting) selectMark(selected),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: p.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(s.trigger, style: mono.copyWith(color: p.amber, fontWeight: FontWeight.w800, fontSize: 13.5)),
              ),
              const SizedBox(height: 8),
              Text(Utils.truncate(s.body.replaceAll(RegExp(r'\s+'), ' '), 180), maxLines: 2, overflow: TextOverflow.ellipsis, style: mono.copyWith(color: p.textTertiary, fontSize: 12.5, height: 1.5)),
              const SizedBox(height: 8),
              Text('Used ${s.useCount}×', style: mono.copyWith(fontSize: 11.5, color: p.textTertiary)),
            ]),
          ),
          if (!_selecting)
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(Icons.more_vert, size: 20, color: p.textTertiary),
              onSelected: (v) async {
                if (v == 'edit') _editSnippet(s);
                if (v == 'copy') copyToClipboard(context, s.body, message: 'Snippet text copied');
                if (v == 'delete') {
                  final ok = await confirmDialog(context, title: 'Delete snippet?', message: 'Snippet ${s.trigger} is removed.', confirmLabel: 'Delete', destructive: true);
                  if (ok) await ref.read(vaultProvider.notifier).deleteSnippet(s.id);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'copy', child: Text('Copy text')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ]),
      );
    }

    final items = _tab == 0 ? templates.length : snippets.length;
    final sig = '$_tab|$_q|$_cat|$_groupId|$_perPage';
    if (sig != _sig) {
      _sig = sig;
      _page = 0;
    }
    final pages = _perPage == 0 || items == 0 ? 1 : ((items + _perPage - 1) ~/ _perPage);
    if (_page >= pages) _page = pages - 1;
    final pageStart = _perPage == 0 ? 0 : _page * _perPage;
    final pageEnd = _perPage == 0 ? items : (pageStart + _perPage).clamp(0, items);
    void goPage(int n) {
      setState(() => _page = n.clamp(0, pages - 1));
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: CustomScrollView(controller: _scroll, slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              header,
              Row(children: [seg(0, 'Templates', d.templates.length), seg(1, 'Snippets', d.snippets.length)]),
              const SizedBox(height: 14),
              SearchField(controller: _search, hint: _tab == 0 ? 'Search ${d.templates.length} templates…' : 'Search snippets…', onChanged: (v) => setState(() => _q = v)),
              if (_tab == 0) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final c in [(id: 'all', label: 'All', color: p.amber), for (final c in kCategories) (id: c.id, label: c.label, color: pfColor(c.color))])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _cat = c.id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            padding: const EdgeInsets.symmetric(horizontal: 13),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: _cat == c.id ? c.color.withValues(alpha: 0.16) : p.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: _cat == c.id ? c.color.withValues(alpha: 0.8) : p.border)),
                            child: Text(c.label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _cat == c.id ? c.color : p.textSecondary)),
                          ),
                        ),
                      ),
                  ]),
                ),
                GroupFilterBar(kind: 'templates', selectedId: _groupId, padding: EdgeInsets.zero, onChanged: (id) => setState(() => _groupId = id)),
              ],
              if (items > 0) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Text('Showing ${pageStart + 1}–$pageEnd of $items', style: TextStyle(fontSize: 12.5, color: p.textTertiary, fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback))),
                  SizedBox(
                    width: 132,
                    child: PfSelect<int>(
                      value: _perPage,
                      options: const [MapEntry(25, '25 per page'), MapEntry(50, '50 per page'), MapEntry(100, '100 per page'), MapEntry(0, 'Show all')],
                      onChanged: (v) => setState(() {
                        _perPage = v;
                        _page = 0;
                      }),
                    ),
                  ),
                ]),
              ],
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
              itemCount: pageEnd - pageStart,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (c, i) => _tab == 0 ? templateCard(templates[pageStart + i]) : snippetCard(snippets[pageStart + i]),
            ),
          ),
        if (items > 0 && pages > 1)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                OutlinedButton.icon(icon: const Icon(Icons.chevron_left), label: const Text('Prev'), onPressed: _page > 0 ? () => goPage(_page - 1) : null),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Text('Page ${_page + 1} of $pages', style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w600))),
                OutlinedButton.icon(icon: const Icon(Icons.chevron_right), label: const Text('Next'), onPressed: _page < pages - 1 ? () => goPage(_page + 1) : null),
              ]),
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
      PfField<String>(
        label: 'Category',
        value: kCategories.any((c) => c.id == _cat) ? _cat : 'custom',
        items: [for (final c in kCategories) PfMenuItem<String>(c.id, c.label)],
        onChanged: (v) => setState(() => _cat = v),
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
