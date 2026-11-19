import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../core/util.dart';
import '../../domain/engines/analyzer.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/diff_view.dart';

/// Version history for one prompt, with word diffs and restore.
class HistoryScreen extends ConsumerStatefulWidget {
  final String? initialPromptId;
  const HistoryScreen({super.key, this.initialPromptId});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String? _promptId;
  int _reload = 0;
  int? _openVersion;
  bool _vsCurrent = false;

  @override
  void initState() {
    super.initState();
    _promptId = widget.initialPromptId;
  }

  Future<void> _pickPrompt() async {
    final vn = ref.read(vaultProvider.notifier);
    final d = ref.read(vaultProvider).data;
    final withVersions = (await vn.allVersions()).entries.where((e) => e.value.isNotEmpty).map((e) => e.key).toSet();
    if (!mounted) return;
    final list = d.prompts.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    var onlyVersioned = false;
    final id = await showPfSheet<String>(
      context,
      title: 'Choose a prompt',
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final shown = onlyVersioned ? list.where((x) => withVersions.contains(x.id)).toList() : list;
        return ListView(shrinkWrap: true, children: [
          SwitchListTile(
            title: const Text('Only prompts with saved versions'),
            subtitle: Text('${withVersions.length} of ${list.length} have history'),
            value: onlyVersioned,
            onChanged: (v) => setSheet(() => onlyVersioned = v),
          ),
          if (shown.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No prompts have saved versions yet.')),
          for (final x in shown)
            ListTile(
              title: Text(x.displayTitle),
              subtitle: Text('Updated ${Utils.timeAgo(x.updatedAt)}${withVersions.contains(x.id) ? ' · has history' : ''}'),
              selected: x.id == _promptId,
              onTap: () => Navigator.pop(ctx, x.id),
            ),
        ]);
      }),
    );
    if (id != null) {
      setState(() {
        _promptId = id;
        _openVersion = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final vault = ref.watch(vaultProvider);
    final d = vault.data;
    final prompt = _promptId == null ? null : d.prompts[_promptId];
    final vn = ref.read(vaultProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Version history'),
        actions: [IconButton(tooltip: 'Choose prompt', icon: const Icon(Icons.swap_horiz), onPressed: _pickPrompt)],
      ),
      body: prompt == null
          ? EmptyState(icon: Icons.history, title: 'Pick a prompt', body: 'Versions are saved with the editor’s “Save version” action and live inside your folder under .promptforge/versions.', actionLabel: 'Choose prompt', onAction: _pickPrompt)
          : FutureBuilder<List<PromptVersion>>(
              key: ValueKey('${prompt.id}-$_reload-${vault.revision}'),
              future: vn.versionsOf(prompt.id),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                final versions = (snap.data ?? const <PromptVersion>[]).reversed.toList();
                return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                  PfCard(
                    onTap: _pickPrompt,
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(prompt.displayTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          Text('${versions.length} saved version${versions.length == 1 ? '' : 's'} · ${Utils.countWords(prompt.body)} words now', style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
                        ]),
                      ),
                      TextButton(onPressed: () => openInEditor(context, ref, promptId: prompt.id), child: const Text('Open')),
                    ]),
                  ),
                  if (versions.length >= 2) _ScoreSpark(versions: versions.reversed.toList(), profileId: d.settings.scoringProfile),
                  if (versions.isEmpty)
                    const Padding(padding: EdgeInsets.only(top: 40), child: EmptyState(icon: Icons.history_toggle_off, title: 'No versions yet', body: 'Use “Save version…” in the editor menu to snapshot this prompt.')),
                  if (versions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SegmentedButton<bool>(
                        segments: const [ButtonSegment(value: false, label: Text('Diff vs previous')), ButtonSegment(value: true, label: Text('Diff vs current'))],
                        selected: {_vsCurrent},
                        onSelectionChanged: (s) => setState(() => _vsCurrent = s.first),
                      ),
                    ),
                  for (var i = 0; i < versions.length; i++)
                    Builder(builder: (context) {
                      final v = versions[i];
                      final older = i + 1 < versions.length ? versions[i + 1] : null;
                      final open = _openVersion == v.versionNum;
                      final before = _vsCurrent ? v.body : (older?.body ?? '');
                      final after = _vsCurrent ? prompt.body : v.body;
                      final counts = diffCounts(before, after);
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: PfCard(
                          onTap: () => setState(() => _openVersion = open ? null : v.versionNum),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              StatusBadge('v${v.versionNum}', p.amber),
                              const SizedBox(width: 8),
                              Expanded(child: Text(v.note.isEmpty ? 'No note' : v.note, style: TextStyle(fontWeight: FontWeight.w600, color: v.note.isEmpty ? p.textTertiary : p.text))),
                              Text(Utils.timeAgo(v.createdAt), style: TextStyle(color: p.textTertiary, fontSize: 12)),
                            ]),
                            const SizedBox(height: 4),
                            Text('${Utils.countWords(v.body)} words · +${counts.added} / −${counts.removed}', style: TextStyle(color: p.textSecondary, fontSize: 12)),
                            if (open) ...[
                              const SizedBox(height: 10),
                              DiffView(before: before, after: after),
                              const SizedBox(height: 10),
                              Wrap(spacing: 8, children: [
                                OutlinedButton.icon(icon: const Icon(Icons.copy, size: 16), label: const Text('Copy'), onPressed: () => copyToClipboard(context, v.body)),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.note_add_outlined, size: 16),
                                  label: const Text('Open as new'),
                                  onPressed: () => openInEditor(context, ref, seedBody: v.body, seedTitle: '${v.title.isEmpty ? prompt.displayTitle : v.title} (v${v.versionNum})'),
                                ),
                                FilledButton.tonalIcon(
                                  icon: const Icon(Icons.restore, size: 16),
                                  label: const Text('Restore'),
                                  onPressed: () async {
                                    final ok = await confirmDialog(context,
                                        title: 'Restore v${v.versionNum}?', message: 'The current text is replaced. It is saved as a version first, so nothing is lost.', confirmLabel: 'Restore');
                                    if (!ok) return;
                                    await vn.restoreVersion(prompt.id, v.versionNum);
                                    if (mounted) {
                                      setState(() => _reload++);
                                      toast(context, 'Restored v${v.versionNum}');
                                    }
                                  },
                                ),
                                TextButton.icon(
                                  icon: Icon(Icons.delete_outline, size: 16, color: p.red),
                                  label: Text('Delete', style: TextStyle(color: p.red)),
                                  onPressed: () async {
                                    final ok = await confirmDialog(context, title: 'Delete v${v.versionNum}?', message: 'Only this snapshot is removed.', confirmLabel: 'Delete', destructive: true);
                                    if (!ok) return;
                                    await vn.deleteVersion(prompt.id, v.versionNum);
                                    if (mounted) setState(() => _reload++);
                                  },
                                ),
                              ]),
                            ],
                          ]),
                        ),
                      );
                    }),
                ]);
              },
            ),
    );
  }
}


/// "Score across versions": one bar per saved version coloured by its Analyzer score, with the net change.
class _ScoreSpark extends StatelessWidget {
  final List<PromptVersion> versions; // oldest first
  final String profileId;
  const _ScoreSpark({required this.versions, required this.profileId});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final scores = [for (final v in versions) Analyzer.analyze(v.body, profileId: profileId).overall];
    final net = scores.last - scores.first;
    final netLabel = net > 0 ? '+$net' : (net == 0 ? '±0' : '$net');
    final netColor = net > 0 ? p.green : (net < 0 ? p.red : p.textTertiary);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: PfCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Score across versions', style: TextStyle(color: p.textTertiary, fontSize: 12))),
            Text('$netLabel since v${versions.first.versionNum}', style: TextStyle(color: netColor, fontSize: 12, fontWeight: FontWeight.w700, fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < scores.length; i++)
                Expanded(
                  child: Tooltip(
                    message: 'v${versions[i].versionNum}: ${scores[i]}/100${i > 0 ? ' (${scores[i] - scores[i - 1] >= 0 ? '+' : ''}${scores[i] - scores[i - 1]})' : ''}',
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      height: 44 * (scores[i] < 6 ? 6 : scores[i]) / 100,
                      decoration: BoxDecoration(color: scoreColor(context, scores[i]), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
