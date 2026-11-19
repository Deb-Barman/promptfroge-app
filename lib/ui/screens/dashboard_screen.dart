import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell.dart';
import '../../core/constants.dart';
import '../../core/util.dart';
import '../../domain/engines/analytics.dart';
import '../../state/device_settings.dart';
import '../../state/vault_notifier.dart';
import '../more_menu.dart';
import '../onboarding.dart';
import '../quick_capture.dart';
import '../search_sheet.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/prompt_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  AnalyticsSummary? _cache;
  int _cacheRev = -1;

  @override
  void initState() {
    super.initState();
    // First run: show the welcome once, after the vault is open and the first frame is on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !ref.read(deviceSettingsProvider).onboardingSeen) showWelcome(context, ref);
    });
  }

  AnalyticsSummary _summary(VaultState s, bool active) {
    if (_cache != null && (!active || _cacheRev == s.revision)) return _cache!;
    final hub = ref.read(suggestionHubProvider);
    _cache = AnalyticsEngine.summary(s.data, hub.fresh(s), profileId: s.data.settings.scoringProfile);
    _cacheRev = s.revision;
    return _cache!;
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultProvider);
    final p = context.pf;
    final active = TickerMode.of(context);
    final data = vault.data;
    final sum = _summary(vault, active);
    final all = data.prompts.values.where((x) => !x.archived).toList();
    final recent = ([...all]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt))).take(5).toList();
    final pinned = all.where((x) => x.pinned).toList();
    final revisit = all.where((x) => x.needsRevisit != null).toList();
    final maxAct = sum.activity.fold<int>(1, (m, d) => d.count > m ? d.count : m);

    void open(String id) => openInEditor(context, ref, promptId: id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prompt Forge'),
        actions: [
          IconButton(tooltip: 'Quick capture', icon: const Icon(Icons.bolt), onPressed: () => showQuickCapture(context, ref)),
          IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: () => showSearchSheet(context, ref)),
          const MoreMenuButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(vaultProvider.notifier).rescan(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.0,
              children: [
                _Stat('Prompts', '${sum.totalPrompts}', Icons.description_outlined, p.amber),
                _Stat('Templates', '${sum.totalTemplates}', Icons.article_outlined, p.blue),
                _Stat('Avg quality', sum.totalPrompts == 0 ? '—' : sum.avgScore.round().toString(), Icons.speed, scoreColor(context, sum.avgScore)),
                _Stat('Favorites', '${sum.favoriteCount}', Icons.star_outline, p.violet),
              ],
            ),
            const SectionTitle('Quick actions'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _Action(Icons.add, 'New prompt', () => openInEditor(context, ref)),
              _Action(Icons.article_outlined, 'From template', () => context.push('/templates')),
              _Action(Icons.view_agenda_outlined, 'Builder', () => context.go('/builder')),
              _Action(Icons.pattern, 'Patterns', () => context.push('/patterns')),
              _Action(Icons.import_export, 'Import', () => context.push('/data')),
            ]),
            if (revisit.isNotEmpty) ...[
              const SectionTitle('Needs revisit'),
              for (final x in revisit.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: PfCard(
                    onTap: () => open(x.id),
                    child: Row(children: [
                      Icon(Icons.flag, color: p.red, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(x.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (x.needsRevisit!.note.isNotEmpty) Text(x.needsRevisit!.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ],
            if (pinned.isNotEmpty) ...[
              const SectionTitle('Pinned'),
              for (final x in pinned.take(4))
                Padding(padding: const EdgeInsets.only(bottom: 8), child: PromptCard(prompt: x, onTap: () => open(x.id))),
            ],
            SectionTitle('Recent activity', trailing: TextButton(onPressed: () => context.go('/library'), child: const Text('See all'))),
            if (recent.isEmpty)
              const EmptyState(
                icon: Icons.edit_note,
                title: 'Your vault is empty',
                body: 'Write your first prompt — it is saved as a Markdown file in your folder.',
              )
            else
              for (final x in recent) Padding(padding: const EdgeInsets.only(bottom: 8), child: PromptCard(prompt: x, onTap: () => open(x.id))),
            const SectionTitle('Last 14 days'),
            PfCard(
              child: SizedBox(
                height: 96,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final d in sum.activity)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Container(
                            height: 6 + 58 * (d.count / maxAct),
                            decoration: BoxDecoration(color: d.count == 0 ? p.surface2 : p.amber, borderRadius: BorderRadius.circular(4)),
                          ),
                          const SizedBox(height: 4),
                          Text(d.label.substring(0, 1), style: TextStyle(fontSize: 10, color: p.textTertiary)),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
            if (sum.byCategory.isNotEmpty) ...[
              const SectionTitle('By category'),
              PfCard(
                child: Column(children: [
                  for (final e in (sum.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(6))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        SizedBox(width: 120, child: Text(categoryById(e.key).label, style: TextStyle(fontSize: 12.5, color: p.textSecondary))),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: e.value / (sum.totalPrompts == 0 ? 1 : sum.totalPrompts),
                              minHeight: 7,
                              color: pfColor(categoryById(e.key).color),
                              backgroundColor: p.surface2,
                            ),
                          ),
                        ),
                        SizedBox(width: 30, child: Text('${e.value}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
                      ]),
                    ),
                ]),
              ),
            ],
            const SectionTitle('Vault'),
            PfCard(
              child: Row(children: [
                Icon(Icons.folder_outlined, color: p.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(vault.rootPath ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                    Text('${data.prompts.length} prompt files · pull down to rescan', style: TextStyle(fontSize: 11.5, color: p.textTertiary)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Rescan folder',
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    await ref.read(vaultProvider.notifier).rescan();
                    if (context.mounted) toast(context, 'Vault rescanned (${Utils.formatDate(Utils.nowMs())})');
                  },
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Stat(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return PfCard(
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(fontSize: 12, color: p.textTertiary)),
          ]),
        ),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Action(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: Icon(icon, size: 16, color: context.pf.amber),
        label: Text(label),
        onPressed: onTap,
      );
}
