import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../core/util.dart';
import '../../domain/engines/analyzer.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../external_diff.dart';
import '../theme/app_theme.dart';
import '../widgets/pf_chrome.dart';
import '../widgets/common.dart';
import '../widgets/diff_view.dart';

/// Prompts picked for comparison. The Library's "Compare" bulk action fills this and opens the Compare screen.
final compareSelectionProvider = StateProvider<List<String>>((ref) => const []);

const List<(String, String)> _dims = [
  ('overall', 'Overall'),
  ('clarity', 'Clarity'),
  ('context', 'Context'),
  ('specificity', 'Specificity'),
  ('structure', 'Structure'),
  ('constraints', 'Constraints'),
  ('output', 'Output def.'),
];

/// Compare two or more prompts: Analyzer scores side by side, plus a word-level diff when exactly two are picked.
class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key});

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    final cur = ref.read(compareSelectionProvider);
    ref.read(compareSelectionProvider.notifier).state = cur.contains(id) ? cur.where((x) => x != id).toList() : [...cur, id];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final d = ref.watch(vaultProvider).data;
    final selIds = ref.watch(compareSelectionProvider);
    // Drop ids that no longer resolve (deleted elsewhere) so stale selections never linger.
    final selected = [for (final id in selIds) if (d.prompts[id] != null) d.prompts[id]!];
    final all = d.prompts.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final q = _q.trim().toLowerCase();
    final pool = q.isEmpty ? all : all.where((x) => x.title.toLowerCase().contains(q) || x.body.toLowerCase().contains(q)).toList();
    final selectedNotInPool = selected.where((x) => !pool.contains(x)).toList();
    final picker = [...selectedNotInPool, ...pool].take(18).toList();

    return Scaffold(
      backgroundColor: p.bg,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
        PfPageHeader(
          title: 'Compare Prompts',
          subtitle: 'Pick two or more saved prompts to see their structure and Analyzer scores side-by-side.',
          actions: [
            PfBtn(label: 'Diff pasted text', icon: Icons.content_paste_go_outlined, onPressed: () => showExternalDiff(context, ref, initialPromptId: selected.isEmpty ? null : selected.first.id)),
            if (selected.length == 2) PfBtn(label: 'Swap', icon: Icons.swap_horiz, onPressed: () => ref.read(compareSelectionProvider.notifier).state = [selected[1].id, selected[0].id, ...selIds.skip(2)]),
            if (selected.isNotEmpty) PfBtn(label: 'Clear', onPressed: () => ref.read(compareSelectionProvider.notifier).state = const []),
          ],
        ),
        SearchField(controller: _search, hint: 'Search your library to add prompts to compare…', onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: 10),
        if (picker.isEmpty)
          EmptyState(icon: Icons.search_off, title: all.isEmpty ? 'No saved prompts yet' : 'No matches', body: all.isEmpty ? 'Write and save a prompt in the Editor first, then come back here to compare it against others.' : 'Try different search words.')
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final x in picker)
              SizedBox(
                width: 168,
                child: PfCard(
                  onTap: () => _toggle(x.id),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(selIds.contains(x.id) ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: selIds.contains(x.id) ? p.amber : p.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(x.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(Utils.timeAgo(x.updatedAt), style: TextStyle(color: p.textTertiary, fontSize: 11)),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]),
        const SizedBox(height: 14),
        if (selected.isEmpty)
          const SizedBox.shrink()
        else if (selected.length == 1)
          const EmptyState(icon: Icons.compare_arrows, title: 'Pick one more prompt', body: 'Select at least one more prompt above to start comparing.')
        else
          ..._results(context, selected, d.settings.scoringProfile),
      ]),
    );
  }

  List<Widget> _results(BuildContext context, List<Prompt> prompts, String profileId) {
    final p = context.pf;
    final analyses = [for (final x in prompts) Analyzer.analyze(x.body, profileId: profileId)];
    return [
      const SectionTitle('Score comparison'),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: 34,
          dataRowMaxHeight: 38,
          columnSpacing: 22,
          columns: [
            const DataColumn(label: Text('Dimension')),
            for (final x in prompts) DataColumn(numeric: true, label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 120), child: Text(x.displayTitle, overflow: TextOverflow.ellipsis))),
          ],
          rows: [
            for (final dim in _dims)
              DataRow(cells: [
                DataCell(Text(dim.$2, style: TextStyle(color: p.textTertiary, fontWeight: dim.$1 == 'overall' ? FontWeight.w700 : FontWeight.w400))),
                for (final a in analyses)
                  DataCell(Builder(builder: (context) {
                    final v = dim.$1 == 'overall' ? a.overall : (a.scores[dim.$1] ?? 0);
                    return Text('$v', style: TextStyle(color: scoreColor(context, v), fontWeight: dim.$1 == 'overall' ? FontWeight.w800 : FontWeight.w500, fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback));
                  })),
              ]),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (prompts.length == 2) ...[
        const SectionTitle('Word-level diff'),
        Builder(builder: (context) {
          final sim = Utils.textSimilarity(prompts[0].body, prompts[1].body);
          final counts = diffCounts(prompts[0].body, prompts[1].body);
          return Wrap(spacing: 8, runSpacing: 8, children: [
            StatusBadge('${(sim * 100).round()}% similar', p.blue),
            StatusBadge('+${counts.added} words', p.green),
            StatusBadge('−${counts.removed} words', p.red),
          ]);
        }),
        const SizedBox(height: 10),
        if (prompts[0].body.isEmpty && prompts[1].body.isEmpty)
          Text('Both prompts are empty.', style: TextStyle(color: p.textSecondary))
        else if (prompts[0].body == prompts[1].body)
          Text('No differences — these prompts are identical.', style: TextStyle(color: p.textSecondary))
        else
          PfCard(child: DiffView(before: prompts[0].body, after: prompts[1].body)),
      ] else
        Text('Word-level diff is only shown for exactly 2 selected prompts — deselect down to a pair to see it.', style: TextStyle(color: p.textTertiary, fontSize: 12)),
      const SizedBox(height: 14),
      for (final x in prompts)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PfCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.displayTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(child: SelectableText(x.body, style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 11.5, height: 1.5, color: p.textSecondary))),
              ),
              Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => openInEditor(context, ref, promptId: x.id), child: const Text('Open in editor'))),
            ]),
          ),
        ),
    ];
  }
}
