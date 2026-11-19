import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell.dart';
import '../../core/constants.dart';
import '../../core/util.dart';
import '../../domain/engines/analytics.dart';
import '../../domain/engines/exporter.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../export_helpers.dart';
import '../more_menu.dart';
import '../search_sheet.dart';
import '../theme/app_theme.dart';
import '../external_diff.dart';
import 'compare_screen.dart' show compareSelectionProvider;
import '../widgets/common.dart';
import '../widgets/groups_ui.dart';
import '../widgets/prompt_card.dart';
import '../../data/vault/vault_repository.dart' show VaultData;

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _category = 'all';
  String _tag = '';
  bool _favOnly = false;
  bool _showArchived = false;
  String _sort = 'updated';
  String? _groupId;
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  VaultNotifier get _vault => ref.read(vaultProvider.notifier);

  List<Prompt> _filtered(VaultData d) {
    final q = _query.trim().toLowerCase();
    final group = _groupId == null ? null : d.groups[_groupId];
    var list = d.prompts.values.where((p) {
      if (p.archived != _showArchived) return false;
      if (_category != 'all' && p.category != _category) return false;
      if (_tag.isNotEmpty && !p.tags.contains(_tag)) return false;
      if (_favOnly && !p.favorite) return false;
      if (group != null && !group.memberIds.contains(p.id)) return false;
      if (q.isNotEmpty) {
        final hay = '${p.title} ${p.body} ${p.tags.join(' ')} ${p.category}'.toLowerCase();
        for (final t in Utils.tokenize(q)) {
          if (!hay.contains(t)) return false;
        }
      }
      return true;
    }).toList();
    int cmp(Prompt a, Prompt b) {
      switch (_sort) {
        case 'title':
          return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
        case 'created':
          return b.createdAt.compareTo(a.createdAt);
        case 'used':
          return b.useCount.compareTo(a.useCount);
        default:
          return b.updatedAt.compareTo(a.updatedAt);
      }
    }

    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return cmp(a, b);
    });
    return list;
  }

  void _toggleSelect(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  Future<void> _cardMenu(Prompt p) async {
    final d = ref.read(vaultProvider).data;
    await showPfSheet<void>(
      context,
      title: p.displayTitle,
      builder: (ctx) {
        Widget tile(IconData icon, String label, VoidCallback fn, {Color? color}) => ListTile(
              leading: Icon(icon, color: color),
              title: Text(label, style: TextStyle(color: color)),
              onTap: () {
                Navigator.pop(ctx);
                fn();
              },
            );
        return ListView(shrinkWrap: true, children: [
          tile(Icons.edit_outlined, 'Open in editor', () => openInEditor(context, ref, promptId: p.id)),
          tile(p.favorite ? Icons.star : Icons.star_border, p.favorite ? 'Remove favorite' : 'Favorite', () => _vault.toggleFavorite(p.id)),
          tile(p.pinned ? Icons.push_pin : Icons.push_pin_outlined, p.pinned ? 'Unpin' : 'Pin to top', () => _vault.togglePinned(p.id)),
          tile(p.bestOf ? Icons.emoji_events : Icons.emoji_events_outlined, p.bestOf ? 'Remove "best of"' : 'Mark as best of', () => _vault.toggleBestOf(p.id)),
          tile(Icons.copy_all_outlined, 'Duplicate', () async {
            await _vault.duplicatePrompt(p.id);
            if (mounted) toast(context, 'Duplicated');
          }),
          if (d.groups.isNotEmpty) tile(Icons.folder_special_outlined, 'Groups…', () => _groupMembershipSheet([p.id])),
          tile(Icons.history, 'Version history', () => context.push('/history?id=${p.id}')),
          tile(Icons.ios_share, 'Export / share…', () => _exportSheet(p)),
          tile(p.archived ? Icons.unarchive_outlined : Icons.archive_outlined, p.archived ? 'Unarchive' : 'Archive', () => _vault.setArchived(p.id, !p.archived)),
          tile(Icons.delete_outline, 'Delete', () async {
            final ok = await confirmDialog(context, title: 'Delete prompt?', message: 'This removes "${p.displayTitle}" and its version history from your folder.', confirmLabel: 'Delete', destructive: true);
            if (ok) await _vault.deletePrompt(p.id);
          }, color: context.pf.red),
        ]);
      },
    );
  }

  Future<void> _exportSheet(Prompt p) async {
    await showPfSheet<void>(
      context,
      title: 'Export "${p.displayTitle}"',
      builder: (ctx) => ListView(shrinkWrap: true, children: [
        for (final f in const [['txt', 'Plain text (.txt)'], ['md', 'Markdown (.md)'], ['json', 'JSON (.json)'], ['html', 'HTML (.html)']])
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(f[1]),
            subtitle: const Text('Copy, or share / save the file'),
            trailing: IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy),
              onPressed: () => copyToClipboard(ctx, Exporter.promptToFormat(p, f[0])),
            ),
            onTap: () async {
              Navigator.pop(ctx);
              final root = ref.read(vaultProvider).rootPath;
              if (root == null) return;
              final name = '${Utils.fileSafe(p.displayTitle)}.${Exporter.fileExt(f[0])}';
              final file = await saveExportFile(root, name, Exporter.promptToFormat(p, f[0]));
              if (mounted) toast(context, 'Saved to Exports/$name');
              await shareFilePath(file.path);
            },
          ),
      ]),
    );
  }

  Future<void> _groupMembershipSheet(List<String> ids) => showGroupMembership(context, kind: 'library', ids: ids);

  Future<void> _groupsManager() => showGroupsManager(context, kind: 'library', selectedId: _groupId, onSelect: (id) => setState(() => _groupId = id));

  Future<void> _savedSearches() async {
    await showPfSheet<void>(
      context,
      title: 'Saved searches',
      builder: (ctx) => Consumer(builder: (c, r, _) {
        final list = r.watch(vaultProvider).data.savedSearches.values.toList();
        return ListView(shrinkWrap: true, children: [
          for (final s in list)
            ListTile(
              leading: const Icon(Icons.bookmark_outline),
              title: Text(s.name),
              subtitle: Text([if (s.query.isNotEmpty) '"${s.query}"', if (s.category != 'all') categoryById(s.category).label, if (s.tag.isNotEmpty) '#${s.tag}', if (s.favoritesOnly) 'favorites'].join(' · ')),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _query = s.query;
                  _search.text = s.query;
                  _category = s.category;
                  _tag = s.tag;
                  _favOnly = s.favoritesOnly;
                  _sort = s.sort;
                });
              },
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _vault.deleteSearch(s.id)),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Save current filters'),
            onTap: () async {
              final name = await textPrompt(context, title: 'Save search', label: 'Name', confirmLabel: 'Save');
              if (name != null && name.trim().isNotEmpty) {
                await _vault.saveSearch(SavedSearch(name: name.trim(), query: _query, category: _category, tag: _tag, favoritesOnly: _favOnly, sort: _sort));
              }
            },
          ),
        ]);
      }),
    );
  }

  Future<void> _duplicates() async {
    final d = ref.read(vaultProvider).data;
    final groups = DuplicateFinder.find(d.prompts.values.where((p) => !p.archived));
    await showPfSheet<void>(
      context,
      title: 'Possible duplicates',
      builder: (ctx) => groups.isEmpty
          ? const SingleChildScrollView(child: EmptyState(icon: Icons.check_circle_outline, title: 'No near-duplicates', body: 'No two prompts look more than 55% alike.'))
          : ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
              for (final g in groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PfCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${g.prompts.length} similar prompts', style: TextStyle(color: ctx.pf.amber, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      for (final p in g.prompts)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.displayTitle),
                          subtitle: Text('Updated ${Utils.timeAgo(p.updatedAt)}'),
                          onTap: () {
                            Navigator.pop(ctx);
                            openInEditor(context, ref, promptId: p.id);
                          },
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            context.go('/compare');
                          },
                          child: const Text('Compare'),
                        ),
                      ),
                    ]),
                  ),
                ),
            ]),
    );
  }

  Future<void> _bulkMenu() async {
    final ids = _selected.toList();
    await showPfSheet<void>(
      context,
      title: '${ids.length} selected',
      builder: (ctx) {
        Widget tile(IconData icon, String label, Future<void> Function() fn, {Color? color}) => ListTile(
              leading: Icon(icon, color: color),
              title: Text(label, style: TextStyle(color: color)),
              onTap: () async {
                Navigator.pop(ctx);
                await fn();
                if (mounted) setState(_selected.clear);
              },
            );
        return ListView(shrinkWrap: true, children: [
          if (ids.length >= 2)
            tile(Icons.compare_arrows, 'Compare ${ids.length} prompts', () async {
              ref.read(compareSelectionProvider.notifier).state = ids;
              if (mounted) context.push('/compare');
            }),
          tile(Icons.archive_outlined, _showArchived ? 'Unarchive' : 'Archive', () => _vault.bulkSetArchived(ids, !_showArchived)),
          tile(Icons.sell_outlined, 'Add tag…', () async {
            final t = await textPrompt(context, title: 'Add tag', label: 'Tag (without #)', confirmLabel: 'Add');
            if (t != null) await _vault.bulkAddTag(ids, t);
          }),
          tile(Icons.category_outlined, 'Set category…', () async {
            final c = await showPfSheet<String>(
              context,
              title: 'Category',
              builder: (cx) => ListView(shrinkWrap: true, children: [
                for (final cat in kCategories)
                  ListTile(leading: CircleAvatar(radius: 6, backgroundColor: pfColor(cat.color)), title: Text(cat.label), onTap: () => Navigator.pop(cx, cat.id)),
              ]),
            );
            if (c != null) await _vault.bulkSetCategory(ids, c);
          }),
          tile(Icons.flag_outlined, 'Set status…', () async {
            final s = await showPfSheet<String>(
              context,
              title: 'Status',
              builder: (cx) => ListView(shrinkWrap: true, children: [
                for (final st in kStatuses) ListTile(title: Text(st.label), onTap: () => Navigator.pop(cx, st.id)),
              ]),
            );
            if (s != null) await _vault.bulkSetStatus(ids, s);
          }),
          tile(Icons.folder_special_outlined, 'Groups…', () async => _groupMembershipSheet(ids)),
          tile(Icons.delete_outline, 'Delete', () async {
            final ok = await confirmDialog(context, title: 'Delete ${ids.length} prompts?', message: 'The files and their version history are removed from your folder.', confirmLabel: 'Delete', destructive: true);
            if (ok) await _vault.bulkDelete(ids);
          }, color: context.pf.red),
        ]);
      },
    );
  }

  Future<void> _filterSheet(List<String> allTags) async {
    await showPfSheet<void>(
      context,
      title: 'Filter & sort',
      builder: (ctx) => StatefulBuilder(builder: (c, setSheet) {
        void both(VoidCallback fn) {
          setState(fn);
          setSheet(() {});
        }

        return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          const Text('Sort by', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final s in const [['updated', 'Recently updated'], ['created', 'Newest'], ['title', 'Title'], ['used', 'Most used']])
              PfChip(label: s[1], selected: _sort == s[0], color: c.pf.amber, onTap: () => both(() => _sort = s[0])),
          ]),
          const SizedBox(height: 16),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Favorites only'), value: _favOnly, onChanged: (v) => both(() => _favOnly = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show archived'), value: _showArchived, onChanged: (v) => both(() => _showArchived = v)),
          if (allTags.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Tag', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              PfChip(label: 'Any', selected: _tag.isEmpty, color: c.pf.amber, onTap: () => both(() => _tag = '')),
              for (final t in allTags) PfChip(label: '#$t', selected: _tag == t, color: c.pf.amber, onTap: () => both(() => _tag = t)),
            ]),
          ],
        ]);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultProvider);
    final d = vault.data;
    final p = context.pf;
    final list = _filtered(d);
    final tags = <String>{for (final x in d.prompts.values) ...x.tags}.toList()..sort();
    final catCounts = <String, int>{};
    for (final x in d.prompts.values) {
      if (x.archived == _showArchived) catCounts[x.category] = (catCounts[x.category] ?? 0) + 1;
    }
    final libGroups = d.groups.values.where((g) => g.kind == 'library').toList();
    final filtersActive = _tag.isNotEmpty || _favOnly || _groupId != null || _category != 'all' || _query.isNotEmpty;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
                title: Text('${_selected.length} selected'),
                actions: [
                  IconButton(
                    tooltip: 'Select all',
                    icon: const Icon(Icons.select_all),
                    onPressed: () => setState(() => _selected.addAll(list.map((e) => e.id))),
                  ),
                  IconButton(tooltip: 'Actions', icon: const Icon(Icons.more_horiz), onPressed: _bulkMenu),
                ],
              )
            : AppBar(
                title: Text(_showArchived ? 'Archive' : 'Library'),
                actions: [
                  IconButton(tooltip: 'Search everything', icon: const Icon(Icons.manage_search), onPressed: () => showSearchSheet(context, ref)),
                  IconButton(tooltip: 'Filter & sort', icon: Icon(Icons.tune, color: filtersActive ? p.amber : null), onPressed: () => _filterSheet(tags)),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'groups') _groupsManager();
                      if (v == 'extdiff') showExternalDiff(context, ref);
                      if (v == 'searches') _savedSearches();
                      if (v == 'dupes') _duplicates();
                      if (v == 'archive') setState(() => _showArchived = !_showArchived);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'groups', child: Text('Groups')),
                      const PopupMenuItem(value: 'extdiff', child: Text('Diff pasted text…')),
                      const PopupMenuItem(value: 'searches', child: Text('Saved searches')),
                      const PopupMenuItem(value: 'dupes', child: Text('Find duplicates')),
                      PopupMenuItem(value: 'archive', child: Text(_showArchived ? 'Show active' : 'Show archive')),
                    ],
                  ),
                  const MoreMenuButton(),
                ],
              ),
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton.extended(
                onPressed: () => openInEditor(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('New prompt'),
              ),
        body: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: SearchField(controller: _search, hint: 'Search prompts', onChanged: (v) => setState(() => _query = v))),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PfChip(label: 'All ${catCounts.values.fold<int>(0, (a, b) => a + b)}', selected: _category == 'all', color: p.amber, onTap: () => setState(() => _category = 'all')),
              ),
              for (final c in kCategories)
                if ((catCounts[c.id] ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PfChip(label: '${c.label} ${catCounts[c.id]}', selected: _category == c.id, color: pfColor(c.color), onTap: () => setState(() => _category = c.id)),
                  ),
            ]),
          ),
          if (libGroups.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                for (final g in libGroups)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 4),
                    child: PfChip(
                      icon: Icons.folder_special_outlined,
                      label: g.name,
                      selected: _groupId == g.id,
                      color: pfColor(g.color),
                      onTap: () => setState(() => _groupId = _groupId == g.id ? null : g.id),
                    ),
                  ),
              ]),
            ),
          Expanded(
            child: list.isEmpty
                ? EmptyState(
                    icon: filtersActive ? Icons.search_off : Icons.folder_open,
                    title: filtersActive ? 'Nothing matches' : (_showArchived ? 'Archive is empty' : 'No prompts yet'),
                    body: filtersActive ? 'Clear a filter or try different search words.' : 'Create a prompt and it appears here as a Markdown file in your vault folder.',
                    actionLabel: filtersActive ? 'Clear filters' : 'New prompt',
                    onAction: () {
                      if (filtersActive) {
                        setState(() {
                          _query = '';
                          _search.clear();
                          _category = 'all';
                          _tag = '';
                          _favOnly = false;
                          _groupId = null;
                        });
                      } else {
                        openInEditor(context, ref);
                      }
                    },
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (c, i) {
                      final x = list[i];
                      return PromptCard(
                        prompt: x,
                        selected: _selected.contains(x.id),
                        selectionMode: _selecting,
                        onTap: () => _selecting ? _toggleSelect(x.id) : openInEditor(context, ref, promptId: x.id),
                        onLongPress: () => _toggleSelect(x.id),
                        onMenu: () => _cardMenu(x),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
