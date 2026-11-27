import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../core/util.dart';
import '../../domain/engines/analyzer.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../external_diff.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/diff_view.dart';
import '../widgets/pf_chrome.dart';

/// Prompts picked for comparison. The Library's "Compare" bulk action fills this and opens the Compare screen.
final compareSelectionProvider = StateProvider<List<String>>((ref) => const []);

const List<(String, String)> _dims = [
  ('clarity', 'Clarity'),
  ('context', 'Context'),
  ('specificity', 'Specificity'),
  ('structure', 'Structure'),
  ('constraints', 'Constraints'),
  ('output', 'Output definition'),
];

/// Compare two or more prompts: a verdict, Analyzer scores bar by bar, and a word-level diff for a pair.
class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key});

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  final _search = TextEditingController();
  String _q = '';
  bool _showAll = false;
  final Map<String, AnalysisResult> _cache = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  AnalysisResult _analysis(Prompt x, String profile) {
    final key = '${x.id}|${x.updatedAt}|$profile';
    if (_cache.length > 60) _cache.clear();
    return _cache.putIfAbsent(key, () => Analyzer.analyze(x.body, profileId: profile));
  }

  void _toggle(String id) {
    final cur = ref.read(compareSelectionProvider);
    ref.read(compareSelectionProvider.notifier).state = cur.contains(id) ? cur.where((x) => x != id).toList() : [...cur, id];
  }

  static Color _color(PfPalette p, int i) => [p.amber, p.blue, p.green, p.violet, p.red, const Color(0xFF4FC3D9)][i % 6];

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final d = ref.watch(vaultProvider).data;
    final selIds = ref.watch(compareSelectionProvider);
    final profile = d.settings.scoringProfile;
    // Drop ids that no longer resolve (deleted elsewhere) so stale selections never linger.
    final selected = [for (final id in selIds) if (d.prompts[id] != null) d.prompts[id]!];
    final all = d.prompts.values.where((x) => !x.archived).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final q = _q.trim().toLowerCase();
    final pool = q.isEmpty ? all : all.where((x) => x.title.toLowerCase().contains(q) || x.body.toLowerCase().contains(q) || x.tags.any((t) => t.toLowerCase().contains(q))).toList();
    final limit = _showAll ? 60 : 6;
    final picker = pool.take(limit).toList();

    return Scaffold(
      backgroundColor: p.bg,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
        PfPageHeader(
          title: 'Compare Prompts',
          subtitle: 'Pick two or more prompts to see which is stronger and exactly how they differ.',
          actions: [
            PfBtn(label: 'Diff pasted text', icon: Icons.content_paste_go_outlined, onPressed: () => showExternalDiff(context, ref, initialPromptId: selected.isEmpty ? null : selected.first.id)),
            if (selected.length == 2) PfBtn(label: 'Swap', icon: Icons.swap_horiz, onPressed: () => ref.read(compareSelectionProvider.notifier).state = [selected[1].id, selected[0].id, ...selIds.skip(2)]),
            if (selected.isNotEmpty) PfBtn(label: 'Clear', onPressed: () => ref.read(compareSelectionProvider.notifier).state = const []),
          ],
        ),
        if (selected.isNotEmpty) ...[
          _tray(p, selected, profile),
          const SizedBox(height: 14),
        ],
        _picker(p, picker, pool.length, all.length, selIds, profile),
        const SizedBox(height: 16),
        if (selected.length == 1)
          const EmptyState(icon: Icons.compare_arrows, title: 'Pick one more prompt', body: 'Select at least one more prompt above to start comparing.')
        else if (selected.length >= 2)
          ..._results(context, selected, profile),
      ]),
    );
  }

  // ---- selected prompts

  Widget _tray(PfPalette p, List<Prompt> selected, String profile) {
    return SizedBox(
      height: 46,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (var i = 0; i < selected.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
              decoration: BoxDecoration(color: _color(p, i).withValues(alpha: 0.13), borderRadius: BorderRadius.circular(23), border: Border.all(color: _color(p, i).withValues(alpha: 0.6))),
              child: Row(children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: _color(p, i), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 140), child: Text(selected[i].displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                const SizedBox(width: 8),
                Text('${_analysis(selected[i], profile).overall}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: scoreColor(context, _analysis(selected[i], profile).overall))),
                IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 17), onPressed: () => _toggle(selected[i].id)),
              ]),
            ),
          ),
      ]),
    );
  }

  // ---- picker

  Widget _picker(PfPalette p, List<Prompt> picker, int matches, int total, List<String> selIds, String profile) {
    return PfCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SearchField(controller: _search, hint: 'Search your prompts to compare…', onChanged: (v) => setState(() {
              _q = v;
              _showAll = false;
            })),
        const SizedBox(height: 6),
        if (picker.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Center(child: Text(total == 0 ? 'No saved prompts yet — write and save one in the Editor first.' : 'No matches. Try different words.', style: TextStyle(color: p.textTertiary))),
          )
        else
          for (final x in picker)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _toggle(x.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                child: Row(children: [
                  Icon(selIds.contains(x.id) ? Icons.check_box : Icons.check_box_outline_blank, size: 22, color: selIds.contains(x.id) ? p.amber : p.textTertiary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(x.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text('${Utils.countWords(x.body)} words · ${Utils.timeAgo(x.updatedAt)}', style: TextStyle(color: p.textTertiary, fontSize: 11.5)),
                    ]),
                  ),
                  Builder(builder: (context) {
                    final s = _analysis(x, profile).overall;
                    final c = scoreColor(context, s);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                      child: Text('$s', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: c)),
                    );
                  }),
                ]),
              ),
            ),
        if (matches > picker.length)
          TextButton(onPressed: () => setState(() => _showAll = true), child: Text('Show ${matches - picker.length > 54 ? 'more' : '${matches - picker.length} more'}'))
        else if (_showAll && matches > 6)
          TextButton(onPressed: () => setState(() => _showAll = false), child: const Text('Show fewer')),
      ]),
    );
  }

  // ---- results

  List<Widget> _results(BuildContext context, List<Prompt> prompts, String profile) {
    final p = context.pf;
    final analyses = [for (final x in prompts) _analysis(x, profile)];
    final order = List.generate(prompts.length, (i) => i)..sort((a, b) => analyses[b].overall.compareTo(analyses[a].overall));
    final best = order.first;
    final second = order[1];
    final tie = analyses[best].overall == analyses[second].overall;

    // who wins each dimension (only when there is a single leader)
    final dimWinner = <String, int>{};
    for (final dim in _dims) {
      var top = -1, topV = -1;
      var unique = true;
      for (var i = 0; i < analyses.length; i++) {
        final v = analyses[i].scores[dim.$1] ?? 0;
        if (v > topV) {
          top = i;
          topV = v;
          unique = true;
        } else if (v == topV) {
          unique = false;
        }
      }
      if (unique && top >= 0) dimWinner[dim.$1] = top;
    }

    return [
      // verdict
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_color(p, best).withValues(alpha: 0.2), p.surface]),
          border: Border.all(color: _color(p, best).withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: scoreColor(context, analyses[best].overall).withValues(alpha: 0.15), border: Border.all(color: scoreColor(context, analyses[best].overall), width: 2.5)),
            child: Text('${analyses[best].overall}', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: scoreColor(context, analyses[best].overall))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(tie ? Icons.balance : Icons.emoji_events, size: 17, color: p.amber),
                const SizedBox(width: 6),
                Text(tie ? 'Too close to call' : 'Strongest prompt', style: TextStyle(fontSize: 11.5, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: p.amber)),
              ]),
              const SizedBox(height: 4),
              Text(tie ? '${prompts[best].displayTitle} and ${prompts[second].displayTitle} score the same' : prompts[best].displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, height: 1.2)),
              if (!tie)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('${analyses[best].overall - analyses[second].overall} points ahead of “${prompts[second].displayTitle}”', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
                ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 18),
      // score bars
      const SectionTitle('Score comparison'),
      PfCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 14, runSpacing: 6, children: [
            for (var i = 0; i < prompts.length; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: _color(p, i), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 6),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: Text(prompts[i].displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.textSecondary, fontWeight: FontWeight.w600))),
              ]),
          ]),
          const SizedBox(height: 14),
          for (final dim in _dims) ...[
            Row(children: [
              Text(dim.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.textSecondary)),
              if (dimWinner[dim.$1] != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.workspace_premium, size: 15, color: _color(p, dimWinner[dim.$1]!)),
              ],
            ]),
            const SizedBox(height: 6),
            for (var i = 0; i < prompts.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: ((analyses[i].scores[dim.$1] ?? 0) / 100).clamp(0.0, 1.0), minHeight: 8, color: _color(p, i), backgroundColor: p.surface3))),
                  SizedBox(width: 34, child: Text('${analyses[i].scores[dim.$1] ?? 0}', textAlign: TextAlign.right, style: TextStyle(fontSize: 12.5, fontWeight: dimWinner[dim.$1] == i ? FontWeight.w800 : FontWeight.w500, color: dimWinner[dim.$1] == i ? _color(p, i) : p.textSecondary, fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback))),
                ]),
              ),
            const SizedBox(height: 10),
          ],
        ]),
      ),
      const SizedBox(height: 18),
      // at a glance
      const SectionTitle('At a glance'),
      SizedBox(
        height: 92,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (var i = 0; i < prompts.length; i++)
            Container(
              width: 168,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border(top: BorderSide(color: _color(p, i), width: 3), left: BorderSide(color: p.borderSubtle), right: BorderSide(color: p.borderSubtle), bottom: BorderSide(color: p.borderSubtle))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(prompts[i].displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const Spacer(),
                Text('${Utils.countWords(prompts[i].body)} words · ${prompts[i].body.length} chars', style: TextStyle(fontSize: 12, color: p.textSecondary)),
                Text('${analyses[i].issues.length} issue${analyses[i].issues.length == 1 ? '' : 's'} found', style: TextStyle(fontSize: 12, color: analyses[i].issues.isEmpty ? p.green : p.textTertiary)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 18),
      if (prompts.length == 2) ...[
        const SectionTitle('Word-level diff'),
        Builder(builder: (context) {
          final sim = Utils.textSimilarity(prompts[0].body, prompts[1].body);
          final counts = diffCounts(prompts[0].body, prompts[1].body);
          return PfCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${(sim * 100).round()}% similar', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                StatusBadge('+${counts.added}', p.green),
                const SizedBox(width: 6),
                StatusBadge('−${counts.removed}', p.red),
              ]),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: sim.clamp(0.0, 1.0).toDouble(), minHeight: 7, color: p.blue, backgroundColor: p.surface3)),
              const SizedBox(height: 12),
              if (prompts[0].body.isEmpty && prompts[1].body.isEmpty)
                Text('Both prompts are empty.', style: TextStyle(color: p.textSecondary))
              else if (prompts[0].body == prompts[1].body)
                Text('No differences — these prompts are identical.', style: TextStyle(color: p.textSecondary))
              else
                DiffView(before: prompts[0].body, after: prompts[1].body),
            ]),
          );
        }),
      ] else
        Text('The word-level diff appears when exactly 2 prompts are selected.', style: TextStyle(color: p.textTertiary, fontSize: 12)),
      const SizedBox(height: 18),
      const SectionTitle('Full text'),
      for (var i = 0; i < prompts.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.borderSubtle)),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: prompts.length <= 2,
                shape: const Border(),
                collapsedShape: const Border(),
                leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: _color(p, i), shape: BoxShape.circle)),
                title: Text(prompts[i].displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: SingleChildScrollView(child: SelectableText(prompts[i].body, style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 12, height: 1.55, color: p.textSecondary))),
                    ),
                  ),
                  Row(children: [
                    TextButton.icon(icon: const Icon(Icons.edit_note, size: 18), label: const Text('Open in editor'), onPressed: () => openInEditor(context, ref, promptId: prompts[i].id)),
                    TextButton.icon(icon: const Icon(Icons.copy, size: 16), label: const Text('Copy'), onPressed: () => copyToClipboard(context, prompts[i].body)),
                  ]),
                ],
              ),
            ),
          ),
        ),
    ];
  }
}
