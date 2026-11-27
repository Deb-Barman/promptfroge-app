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
import '../search_sheet.dart';
import '../theme/app_theme.dart';
import '../external_diff.dart';
import 'compare_screen.dart' show compareSelectionProvider;
import '../widgets/common.dart';
import '../widgets/groups_ui.dart';
import '../new_prompt_dialog.dart';
import '../widgets/pf_chrome.dart';
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
  final ScrollController _scroll = ScrollController();
  int _perPage = 50; // 0 = all
  int _page = 0;
  String _sig = '';

  bool _selectMode = false;
  bool get _selecting => _selectMode || _selected.isNotEmpty;

  void _exitSelect() {
    _selected.clear();
    _selectMode = false;
  }

  @override
  void dispose() {
    _scroll.dispose();
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
                if (mounted) setState(_exitSelect);
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

    Widget tagChip(String t) {
      final on = _tag == t;
      return GestureDetector(
        onTap: () => setState(() => _tag = on ? '' : t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: on ? p.blue.withOpacity(0.16) : p.surface3,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: on ? p.blue : p.borderSubtle),
          ),
          child: Text('#$t', style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 12, color: on ? p.blue : p.textSecondary)),
        ),
      );
    }

    final header = _selecting
        ? Padding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_selected.isEmpty ? 'Select prompts' : '${_selected.length} selected', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: p.text)),
              const SizedBox(height: 4),
              Text('Tap cards to select them, then add them to a group, tag, archive or delete — all at once.', style: TextStyle(fontSize: 13, color: p.textTertiary)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                PfBtn(label: 'Select all', icon: Icons.select_all, onPressed: () => setState(() => _selected.addAll(list.map((e) => e.id)))),
                PfBtn(label: 'Add to group', icon: Icons.folder_special_outlined, primary: true, onPressed: _selected.isEmpty ? null : () => _groupMembershipSheet(_selected.toList())),
                PfBtn(label: 'Actions', icon: Icons.more_horiz, onPressed: _selected.isEmpty ? null : _bulkMenu),
                PfBtn(label: 'Done', onPressed: () => setState(_exitSelect)),
              ]),
            ]),
          )
        : PfPageHeader(
            title: _showArchived ? 'Archive' : 'Library',
            subtitle: '${list.length} ${list.length == 1 ? 'prompt' : 'prompts'}',
            actions: [
              PfBtn(label: 'Select', onPressed: () => setState(() => _selectMode = true)),
              PfBtn(label: 'New Prompt', icon: Icons.add, primary: true, onPressed: () => showNewPromptDialog(context, ref)),
            ],
          );

    final activeFilterCount = (_tag.isNotEmpty ? 1 : 0) + (_favOnly ? 1 : 0) + (_showArchived ? 1 : 0) + (_groupId != null ? 1 : 0) + (_category != 'all' ? 1 : 0) + (_sort != 'updated' ? 1 : 0);
    // any change of the filters goes back to the first page
    final sig = '$_query|$_category|$_tag|$_favOnly|$_showArchived|$_sort|$_groupId|$_perPage';
    if (sig != _sig) {
      _sig = sig;
      _page = 0;
    }
    final pages = _perPage == 0 || list.isEmpty ? 1 : ((list.length + _perPage - 1) ~/ _perPage);
    if (_page >= pages) _page = pages - 1;
    final pageStart = _perPage == 0 ? 0 : _page * _perPage;
    final pageEnd = _perPage == 0 ? list.length : (pageStart + _perPage).clamp(0, list.length);
    final pageItems = list.sublist(pageStart.clamp(0, list.length), pageEnd);
    void goPage(int n) {
      setState(() => _page = n.clamp(0, pages - 1));
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    }

    final categoryOptions = <MapEntry<String, String>>[
      const MapEntry('all', 'All categories'),
      for (final c in kCategories)
        if ((catCounts[c.id] ?? 0) > 0 || _category == c.id) MapEntry(c.id, '${c.label} (${catCounts[c.id] ?? 0})'),
    ];

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) setState(_exitSelect);
      },
      child: Scaffold(
        backgroundColor: p.bg,
        body: CustomScrollView(controller: _scroll, slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                header,
                Row(children: [
                  Expanded(child: SearchField(controller: _search, hint: 'Search library…', onChanged: (v) => setState(() => _query = v))),
                  const SizedBox(width: 8),
                  Badge(
                    isLabelVisible: activeFilterCount > 0,
                    label: Text('$activeFilterCount'),
                    backgroundColor: p.amber,
                    textColor: Colors.black,
                    child: PfIconBtn(icon: Icons.tune, tooltip: 'Filters & sort', onPressed: () => _filterSheet(tags)),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (v) {
                      if (v == 'searches') _savedSearches();
                      if (v == 'dupes') _duplicates();
                      if (v == 'search') showSearchSheet(context, ref);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'search', child: Text('Search everything')),
                      PopupMenuItem(value: 'searches', child: Text('Saved searches')),
                      PopupMenuItem(value: 'dupes', child: Text('Find duplicates')),
                    ],
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: p.surface3, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
                      child: Icon(Icons.more_horiz, size: 19, color: p.textSecondary),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    PopupMenuButton<String>(
                      tooltip: 'Category',
                      onSelected: (v) => setState(() => _category = v),
                      itemBuilder: (_) => [for (final o in categoryOptions) PopupMenuItem(value: o.key, child: Text(o.value))],
                      child: _RailChip(label: _category == 'all' ? 'All categories' : categoryById(_category).label, icon: Icons.category_outlined, on: _category != 'all', trailing: Icons.arrow_drop_down),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Sort',
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'updated', child: Text('Recently updated')),
                        PopupMenuItem(value: 'created', child: Text('Newest')),
                        PopupMenuItem(value: 'title', child: Text('Title')),
                        PopupMenuItem(value: 'used', child: Text('Most used')),
                      ],
                      child: _RailChip(label: const {'updated': 'Recently updated', 'created': 'Newest', 'title': 'Title', 'used': 'Most used'}[_sort] ?? 'Sort', icon: Icons.swap_vert, on: false, trailing: Icons.arrow_drop_down),
                    ),
                    _RailChip(label: 'Favorites', icon: Icons.star_border, on: _favOnly, onTap: () => setState(() => _favOnly = !_favOnly)),
                    _RailChip(label: 'Archived', icon: Icons.archive_outlined, on: _showArchived, onTap: () => setState(() => _showArchived = !_showArchived)),
                    _RailChip(label: 'Diff pasted text', icon: Icons.difference_outlined, on: false, onTap: () => showExternalDiff(context, ref)),
                  ]),
                ),
                if (libGroups.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final g in libGroups)
                        _RailChip(label: '${g.name}  ${g.memberIds.length}', icon: Icons.circle, iconSize: 9, on: _groupId == g.id, color: pfColor(g.color), onTap: () => setState(() => _groupId = _groupId == g.id ? null : g.id)),
                      TextButton(onPressed: _groupsManager, child: const Text('Manage groups…', style: TextStyle(fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ] else
                  Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _groupsManager, child: const Text('Create a group…', style: TextStyle(fontWeight: FontWeight.w600)))),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SizedBox(height: 32, child: ListView(scrollDirection: Axis.horizontal, children: [for (final t in tags) Padding(padding: const EdgeInsets.only(right: 6), child: tagChip(t))])),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Text(list.isEmpty ? '' : 'Showing ${pageStart + 1}–$pageEnd of ${list.length}', style: TextStyle(fontSize: 12.5, color: p.textTertiary, fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback))),
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
                const SizedBox(height: 8),
              ]),
            ),
          ),
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: filtersActive ? Icons.search_off : Icons.delete_outline,
                title: filtersActive ? 'Nothing matches' : (_showArchived ? 'Archive is empty' : 'Your library is empty'),
                body: filtersActive ? 'Clear a filter or try different search words.' : 'Prompts you write and save will show up here, organized and searchable.',
                actionLabel: filtersActive ? 'Clear filters' : 'Write your first prompt',
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
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              sliver: SliverList.separated(
                itemCount: pageItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (c, i) {
                  final x = pageItems[i];
                  return PromptCard(
                    prompt: x,
                    selected: _selected.contains(x.id),
                    selectionMode: _selecting,
                    onTap: () => _selecting ? _toggleSelect(x.id) : openInEditor(context, ref, promptId: x.id),
                    onLongPress: () {
                      setState(() => _selectMode = true);
                      _toggleSelect(x.id);
                    },
                    onMenu: () => _cardMenu(x),
                    actions: PromptCardActions(
                      profileId: d.settings.scoringProfile,
                      onCopy: () async {
                        await copyToClipboard(context, x.body, message: 'Copied “${x.displayTitle}”');
                        await _vault.incrementUse(x.id);
                      },
                      onFavorite: () => _vault.toggleFavorite(x.id),
                      onBestOf: () => _vault.toggleBestOf(x.id),
                      onPin: () => _vault.togglePinned(x.id),
                      onDuplicate: () async {
                        await _vault.duplicatePrompt(x.id);
                        if (mounted) toast(context, 'Duplicated');
                      },
                      onArchive: () => _vault.setArchived(x.id, !x.archived),
                    ),
                  );
                },
              ),
            ),
          if (list.isNotEmpty && pages > 1)
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
      ),
    );
  }
}

/// A compact pill for the library's scrolling filter rail.
class _RailChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final double iconSize;
  final bool on;
  final Color? color;
  final VoidCallback? onTap;
  final IconData? trailing;
  const _RailChip({required this.label, this.icon, this.iconSize = 15, required this.on, this.color, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final c = color ?? p.amber;
    final chip = Container(
      margin: const EdgeInsets.only(right: 8),
      padding: EdgeInsets.only(left: 12, right: trailing != null ? 6 : 12),
      decoration: BoxDecoration(
        color: on ? c.withValues(alpha: 0.16) : p.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: on ? c.withValues(alpha: 0.75) : p.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: iconSize, color: on ? c : p.textTertiary), const SizedBox(width: 6)],
        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? c : p.textSecondary)),
        if (trailing != null) Icon(trailing, size: 20, color: p.textTertiary),
      ]),
    );
    return onTap == null ? chip : GestureDetector(onTap: onTap, child: chip);
  }
}
