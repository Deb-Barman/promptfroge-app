import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/util.dart';
import '../../domain/engines/analyzer.dart';
import '../../domain/engines/analytics.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../../app/shell.dart';
import '../theme/app_theme.dart';
import '../widgets/pf_chrome.dart';
import '../widgets/common.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _rev = -1;
  AnalyticsSummary? _summary;
  List<MapEntry<Prompt, int>> _scored = const [];

  void _compute(VaultState v) {
    if (_rev == v.revision && _summary != null) return;
    final engine = ref.read(suggestionHubProvider).fresh(v);
    final profile = v.data.settings.scoringProfile;
    _summary = AnalyticsEngine.summary(v.data, engine, profileId: profile);
    final active = v.data.prompts.values.where((x) => !x.archived && x.body.trim().isNotEmpty);
    _scored = [for (final x in active) MapEntry(x, Analyzer.analyze(x.body, profileId: profile).overall)]..sort((a, b) => a.value.compareTo(b.value));
    _rev = v.revision;
  }

  Widget _bars(BuildContext context, List<(String, int, Color)> rows) {
    final p = context.pf;
    final max = rows.fold<int>(1, (a, b) => b.$2 > a ? b.$2 : a);
    return Column(children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(width: 108, child: Text(r.$1, style: TextStyle(color: p.textSecondary, fontSize: 12.5), overflow: TextOverflow.ellipsis)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: r.$2 / max, minHeight: 10, backgroundColor: p.surface2, valueColor: AlwaysStoppedAnimation(r.$3)),
              ),
            ),
            SizedBox(width: 34, child: Text('${r.$2}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final v = ref.watch(vaultProvider);
    _compute(v);
    final s = _summary!;
    final maxDay = s.activity.fold<int>(1, (a, b) => b.count > a ? b.count : a);

    if (s.totalPrompts == 0) {
      return Scaffold(appBar: PfAppBar(title: const Text('Analytics'), subtitle: 'Computed locally from your saved data — refreshes every time you visit.'), body: const EmptyState(icon: Icons.insights_outlined, title: 'No data yet', body: 'Write a few prompts and your stats appear here.'));
    }
    return Scaffold(
      appBar: PfAppBar(title: const Text('Analytics'), subtitle: 'Computed locally from your saved data — refreshes every time you visit.'),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        PfStatCard(icon: Icons.description_outlined, value: '${s.totalPrompts}', label: 'Total prompts'),
        const SizedBox(height: 12),
        PfStatCard(icon: Icons.notes, value: '${s.avgLen}w', label: 'Avg. length'),
        const SizedBox(height: 12),
        PfStatCard(icon: Icons.star_outline, value: '${s.favoriteCount}', label: 'Favorites'),
        const SizedBox(height: 12),
        PfStatCard(icon: Icons.web_asset_outlined, value: '${s.totalTemplates}', label: 'Templates'),
        const SizedBox(height: 12),
        PfStatCard(icon: Icons.text_snippet_outlined, value: '${s.totalWords}', label: 'Total words'),
        const SizedBox(height: 12),
        PfStatCard(icon: Icons.bolt, value: '${s.totalSnippets}', label: 'Snippets'),
        const SizedBox(height: 12),
        PfStatCard(icon: Icons.speed, value: s.avgScore.toStringAsFixed(0), label: 'Avg. score'),
        const SectionTitle('Activity — last 14 days (prompts edited)'),
        PfCard(
          child: SizedBox(
            height: 110,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final d in s.activity)
                Expanded(
                  child: Tooltip(
                    message: '${d.label}: ${d.count}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Container(height: 4 + (d.count / maxDay) * 80, decoration: BoxDecoration(color: d.count == 0 ? p.surface2 : p.amber, borderRadius: BorderRadius.circular(3))),
                        const SizedBox(height: 4),
                        Text(d.label.length > 2 ? d.label.substring(d.label.length - 2) : d.label, style: TextStyle(fontSize: 9, color: p.textTertiary)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        const SectionTitle('By category'),
        _bars(context, [for (final e in s.byCategory.entries) (categoryById(e.key).label, e.value, pfColor(categoryById(e.key).color))]),
        const SectionTitle('By status'),
        _bars(context, [for (final e in s.byStatus.entries) (statusById(e.key).label, e.value, pfColor(statusById(e.key).color))]),
        if (_scored.isNotEmpty) ...[
          const SectionTitle('Needs the most work'),
          for (final e in _scored.take(5))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e.key.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${Utils.countWords(e.key.body)} words'),
              trailing: ScoreRing(e.value, size: 40),
              onTap: () => openInEditor(context, ref, promptId: e.key.id),
            ),
        ],
        if (s.mostUsed.isNotEmpty) ...[
          const SectionTitle('Most used'),
          for (final e in s.mostUsed) KeyValueRow(e.key, '${e.value}×'),
        ],
        if (s.topWords.isNotEmpty) ...[
          const SectionTitle('Your vocabulary'),
          Wrap(spacing: 10, runSpacing: 4, children: [
            for (final w in s.topWords.take(30))
              Text(w.key, style: TextStyle(fontSize: 11 + (w.value / s.topWords.first.value) * 14, fontWeight: FontWeight.w600, color: p.textSecondary)),
          ]),
        ],
        Padding(padding: const EdgeInsets.only(top: 16), child: Text('Scores are local heuristics (see the analyzer), not model evaluations.', style: TextStyle(color: p.textTertiary, fontSize: 11.5))),
      ]),
    );
  }
}
