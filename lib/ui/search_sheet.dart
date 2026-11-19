import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/shell.dart';
import '../core/constants.dart';
import '../domain/engines/search_engine.dart';
import '../state/vault_notifier.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

/// Global search ("command palette"): prompts, templates, shortcuts and patterns.
Future<void> showSearchSheet(BuildContext context, WidgetRef ref) {
  return showPfSheet<void>(
    context,
    full: true,
    builder: (ctx) => _SearchBody(parentContext: context, ref: ref),
  );
}

class _SearchBody extends StatefulWidget {
  final BuildContext parentContext;
  final WidgetRef ref;
  const _SearchBody({required this.parentContext, required this.ref});

  @override
  State<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends State<_SearchBody> {
  final _ctrl = TextEditingController();
  List<SearchResult> _results = const [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    final data = widget.ref.read(vaultProvider).data;
    setState(() => _results = SearchEngine.search(data, q, types: const {'prompts', 'templates', 'snippets', 'patterns'}, limit: 40));
  }

  IconData _icon(String kind) {
    switch (kind) {
      case 'template':
        return Icons.article_outlined;
      case 'snippet':
        return Icons.bolt;
      case 'pattern':
        return Icons.pattern;
      default:
        return Icons.description_outlined;
    }
  }

  void _open(SearchResult r) {
    final data = widget.ref.read(vaultProvider).data;
    final ctx = widget.parentContext;
    Navigator.pop(context);
    switch (r.kind) {
      case 'prompt':
        openInEditor(ctx, widget.ref, promptId: r.id);
        break;
      case 'template':
        final t = data.templates[r.id];
        if (t != null) openInEditor(ctx, widget.ref, seedBody: t.body, seedTitle: t.name);
        break;
      case 'pattern':
        PromptPatternLookup.open(ctx, widget.ref, r.id);
        break;
      case 'snippet':
        final s = data.snippets[r.id];
        if (s != null) copyToClipboard(ctx, s.body, message: 'Snippet copied');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: _search,
          decoration: const InputDecoration(hintText: 'Search prompts, templates, shortcuts, patterns', prefixIcon: Icon(Icons.search)),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _ctrl.text.trim().isEmpty
              ? const EmptyState(icon: Icons.search, title: 'Search your vault', body: 'Type to find anything by title, body, tag or category.')
              : _results.isEmpty
                  ? const EmptyState(icon: Icons.search_off, title: 'No matches', body: 'Try fewer or different words.')
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (c, i) {
                        final r = _results[i];
                        return ListTile(
                          leading: Icon(_icon(r.kind), color: p.amber),
                          title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(r.snippet.replaceAll('\n', ' '), maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Text(r.kind, style: TextStyle(color: p.textTertiary, fontSize: 11.5)),
                          onTap: () => _open(r),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

/// Opens a (built-in or custom) pattern's template in a new editor draft.
class PromptPatternLookup {
  static void open(BuildContext context, WidgetRef ref, String patternId) {
    final data = ref.read(vaultProvider).data;
    for (final pat in [...kPatterns, ...data.customPatterns.values]) {
      if (pat.id == patternId) {
        openInEditor(context, ref, seedBody: pat.template, seedTitle: pat.name);
        return;
      }
    }
  }
}
