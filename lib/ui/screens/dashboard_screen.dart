import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell.dart';
import '../../core/constants.dart';
import '../../core/util.dart';
import '../../domain/engines/analytics.dart';
import '../../state/device_settings.dart';
import '../../state/vault_notifier.dart';
import '../onboarding.dart';
import '../quick_capture.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../new_prompt_dialog.dart';
import '../widgets/pf_chrome.dart';
import '../widgets/prompt_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  AnalyticsSummary? _cache;
  int _cacheRev = -1;
  int _words = 0;

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
    var w = 0;
    final ws = RegExp(r'\S+');
    for (final x in s.data.prompts.values) {
      w += ws.allMatches(x.body).length;
    }
    _words = w;
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

    String ago(int ms) {
      final d = DateTime.now().millisecondsSinceEpoch - ms;
      if (d < 60000) return 'just now';
      if (d < 3600000) return '${d ~/ 60000}m ago';
      if (d < 86400000) return '${d ~/ 3600000}h ago';
      return '${d ~/ 86400000}d ago';
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: RefreshIndicator(
        onRefresh: () => ref.read(vaultProvider.notifier).rescan(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          children: [
            PfPageHeader(
              title: 'Dashboard',
              subtitle: 'Everything lives on this device — nothing here is sent anywhere.',
              actions: [
                PfIconBtn(icon: Icons.calendar_today_outlined, tooltip: 'Search by date', onPressed: () => context.go('/date-search')),
                PfIconBtn(icon: Icons.hub_outlined, tooltip: 'Prompt graph', onPressed: () => context.go('/graph')),
                PfIconBtn(icon: Icons.bolt, tooltip: 'Quick capture', onPressed: () => showQuickCapture(context, ref)),
                PfBtn(label: 'New Prompt', icon: Icons.add, primary: true, onPressed: () => showNewPromptDialog(context, ref)),
              ],
            ),
            if (recent.isNotEmpty) ...[
              PfCard(
                onTap: () => open(recent.first.id),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const PfCardLabel('Continue where you left off'),
                  Text(recent.first.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(ago(recent.first.updatedAt), style: TextStyle(fontSize: 13, color: p.textSecondary)),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            PfStatCard(icon: Icons.description_outlined, value: '${sum.totalPrompts}', label: 'Prompts'),
            const SizedBox(height: 12),
            PfStatCard(icon: Icons.web_asset_outlined, value: '${sum.totalTemplates}', label: 'Templates'),
            const SizedBox(height: 12),
            PfStatCard(icon: Icons.data_object, value: '${data.snippets.length}', label: 'Snippets'),
            const SizedBox(height: 12),
            PfStatCard(icon: Icons.notes, value: '$_words', label: 'Words written'),
            const SizedBox(height: 12),
            PfCard(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const PfCardLabel('Quick actions'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  PfBtn(label: 'From template', icon: Icons.web_asset_outlined, onPressed: () => context.go('/templates')),
                  PfBtn(label: 'Builder', icon: Icons.view_agenda_outlined, onPressed: () => context.go('/builder')),
                  PfBtn(label: 'Patterns', icon: Icons.bubble_chart_outlined, onPressed: () => context.go('/patterns')),
                  PfBtn(label: 'Import', icon: Icons.file_upload_outlined, onPressed: () => context.go('/data')),
                ]),
              ]),
            ),
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
            SectionTitle('Recently edited', trailing: TextButton(onPressed: () => context.go('/library'), child: const Text('See all'))),
            if (recent.isEmpty)
              const EmptyState(
                icon: Icons.edit_note,
                title: 'Your vault is empty',
                body: 'Write your first prompt — it is saved as a Markdown file in your folder.',
              )
            else
              for (final x in recent) Padding(padding: const EdgeInsets.only(bottom: 8), child: PromptCard(prompt: x, onTap: () => open(x.id))),
            const SectionTitle('Activity — last 14 days'),
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
