import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../domain/engines/token_estimator.dart';
import '../../domain/models.dart';
import '../../state/device_settings.dart';
import '../../state/vault_notifier.dart';
import '../more_menu.dart';
import '../theme/app_theme.dart';
import '../onboarding.dart';
import '../widgets/pf_chrome.dart';
import '../widgets/common.dart';
import '../widgets/model_manager.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pf;
    final ds = ref.watch(deviceSettingsProvider);
    final dev = ref.read(deviceSettingsProvider.notifier);
    final vault = ref.watch(vaultProvider);
    final vn = ref.read(vaultProvider.notifier);
    final s = vault.data.settings;

    Future<void> save(VaultSettings next) => vn.updateSettings(next);

    Widget dropdown<T>({required String label, required T value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PfField<T>(
            label: label,
            value: value,
            items: [for (final i in items) i.enabled ? PfMenuItem<T>(i.value as T, i.child is Text ? ((i.child as Text).data ?? '') : '') : PfMenuItem<T>.header(i.child is Text ? ((i.child as Text).data ?? '') : '')],
            onChanged: (v) => onChanged(v),
          ),
        );

    final customIds = {for (final m in s.customModels) m.id};
    final specs = [
      for (final m in TokenEstimator.allModels(s.customModels))
        if (!s.hideBuiltinModels || customIds.contains(m.id) || m.id == s.selectedModel) m,
    ];
    final byGroup = <String, List<ModelSpec>>{};
    for (final m in specs) {
      byGroup.putIfAbsent(m.group, () => []).add(m);
    }
    final groupNames = byGroup.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final allModels = <DropdownMenuItem<String>>[
      for (final g in groupNames) ...[
        if (groupNames.length > 1) DropdownMenuItem<String>(enabled: false, value: '__group_$g', child: Text(g.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: p.textTertiary))),
        for (final m in byGroup[g]!) DropdownMenuItem<String>(value: m.id, child: Text(m.label, overflow: TextOverflow.ellipsis)),
      ],
    ];
    final selectedModel = allModels.any((e) => e.value == s.selectedModel) ? s.selectedModel : 'generic';

    return Scaffold(
      appBar: PfAppBar(title: const Text('Settings'), subtitle: 'Everything here is stored on this device only.', actions: const [MoreMenuButton()]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        const SectionTitle('Vault folder'),
        PfCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.folder_open, color: p.amber),
              const SizedBox(width: 10),
              Expanded(child: Text(vault.rootPath ?? 'No folder open', style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 12.5))),
            ]),
            const SizedBox(height: 6),
            Text('${vault.data.prompts.length} prompts · ${vault.data.templates.length} templates · ${vault.data.snippets.length} snippets · ${vault.data.customPatterns.length} patterns · ${vault.data.chains.length} chains',
                style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(icon: const Icon(Icons.refresh, size: 18), label: const Text('Rescan folder'), onPressed: () async {
                await vn.rescan();
                if (context.mounted) toast(context, 'Folder rescanned');
              }),
              OutlinedButton.icon(
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Switch folder'),
                onPressed: () async {
                  final ok = await confirmDialog(context, title: 'Switch vault folder?', message: 'Your current folder is left untouched. You can choose or create another folder, or reopen this one later.', confirmLabel: 'Switch');
                  if (ok) await vn.closeVault();
                },
              ),
            ]),
            const SizedBox(height: 6),
            Text('Everything lives as plain files in this folder, so you can open it in Obsidian or any editor, sync it with the tool of your choice, and back it up like any folder.',
                style: TextStyle(color: p.textTertiary, fontSize: 11.5)),
          ]),
        ),
        _SettingsGroup(title: 'Appearance (this device)', children: [
        dropdown<ThemeMode>(
          label: 'Theme',
          value: ds.themeMode,
          items: const [DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')), DropdownMenuItem(value: ThemeMode.light, child: Text('Light')), DropdownMenuItem(value: ThemeMode.system, child: Text('Follow system'))],
          onChanged: (v) => dev.update(ds.copyWith(themeMode: v)),
        ),
        Row(children: [
          Expanded(child: Text('Interface size', style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w700))),
          Text('${(ds.uiZoom * 100).round()}%', style: TextStyle(color: p.amber, fontSize: 13.5, fontWeight: FontWeight.w800)),
        ]),
        Text('Scales everything at once — text, icons, spacing — like zooming a web page. Pick what feels comfortable on your screen.', style: TextStyle(color: p.textTertiary, fontSize: 12, height: 1.4)),
        const SizedBox(height: 4),
        Slider(value: ds.uiZoom.clamp(kMinUiZoom, kMaxUiZoom).toDouble(), min: kMinUiZoom, max: kMaxUiZoom, divisions: 16, label: '${(ds.uiZoom * 100).round()}%', onChanged: (v) => dev.update(ds.copyWith(uiZoom: double.parse(v.toStringAsFixed(2))))),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final z in const [(0.6, 'Tiny'), (0.75, 'Small'), (0.9, 'Compact'), (1.0, 'Standard'), (1.15, 'Large')])
            ChoiceChip(
              label: Text('${z.$2} · ${(z.$1 * 100).round()}%'),
              selected: (ds.uiZoom - z.$1).abs() < 0.03,
              onSelected: (_) => dev.update(ds.copyWith(uiZoom: z.$1)),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: Text('Text size', style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w700))),
          Text('${(ds.uiScale * 100).round()}%', style: TextStyle(color: p.amber, fontSize: 13.5, fontWeight: FontWeight.w800)),
        ]),
        Slider(value: ds.uiScale.clamp(0.7, 1.5).toDouble(), min: 0.7, max: 1.5, divisions: 16, label: '${(ds.uiScale * 100).round()}%', onChanged: (v) => dev.update(ds.copyWith(uiScale: double.parse(v.toStringAsFixed(2))))),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(icon: const Icon(Icons.restart_alt, size: 18), label: const Text('Reset size'), onPressed: () => dev.update(ds.copyWith(uiZoom: kDefaultUiZoom, uiScale: 1.0))),
        ),
        ]),
        _SettingsGroup(title: 'Editor (this device)', children: [
        dropdown<String>(
          label: 'Editor font',
          value: ds.editorFont,
          items: [for (final f in kEditorFonts) DropdownMenuItem(value: f.id, child: Text(f.label))],
          onChanged: (v) => dev.update(ds.copyWith(editorFont: v)),
        ),
        Text('Editor font size: ${ds.editorFontSize.round()} pt', style: TextStyle(color: p.textSecondary, fontSize: 13)),
        Slider(value: ds.editorFontSize, min: 11, max: 24, divisions: 13, label: '${ds.editorFontSize.round()}', onChanged: (v) => dev.update(ds.copyWith(editorFontSize: v.roundToDouble()))),
        Row(children: [
          Expanded(child: Text('Tab width: ${ds.tabWidth} spaces', style: TextStyle(color: p.textSecondary, fontSize: 13))),
          IconButton(tooltip: 'Decrease', icon: const Icon(Icons.remove_circle_outline), onPressed: ds.tabWidth <= 1 ? null : () => dev.update(ds.copyWith(tabWidth: ds.tabWidth - 1))),
          IconButton(tooltip: 'Increase', icon: const Icon(Icons.add_circle_outline), onPressed: ds.tabWidth >= 8 ? null : () => dev.update(ds.copyWith(tabWidth: ds.tabWidth + 1))),
        ]),
        dropdown<String>(
          label: 'Line height',
          value: ds.lineHeight,
          items: const [DropdownMenuItem(value: 'compact', child: Text('Compact')), DropdownMenuItem(value: 'relaxed', child: Text('Relaxed')), DropdownMenuItem(value: 'loose', child: Text('Loose'))],
          onChanged: (v) => dev.update(ds.copyWith(lineHeight: v)),
        ),
        dropdown<int>(
          label: 'Warn when a prompt gets longer than',
          value: const [0, 200, 500, 1000, 2000, 5000].contains(ds.wordCountWarning) ? ds.wordCountWarning : 0,
          items: const [
            DropdownMenuItem(value: 0, child: Text('Never')),
            DropdownMenuItem(value: 200, child: Text('200 words')),
            DropdownMenuItem(value: 500, child: Text('500 words')),
            DropdownMenuItem(value: 1000, child: Text('1,000 words')),
            DropdownMenuItem(value: 2000, child: Text('2,000 words')),
            DropdownMenuItem(value: 5000, child: Text('5,000 words')),
          ],
          onChanged: (v) => dev.update(ds.copyWith(wordCountWarning: v ?? 0)),
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Suggestions while typing'), subtitle: const Text('Snippets (/), prompts (//), links (@), variables ({{) and phrases learned from your own prompts'), value: ds.suggestionsEnabled, onChanged: (v) => dev.update(ds.copyWith(suggestionsEnabled: v))),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Live analyzer score'), subtitle: const Text('Shows the prompt score under the editor as you type'), value: ds.analyzerLive, onChanged: (v) => dev.update(ds.copyWith(analyzerLive: v))),
        dropdown<String>(
          label: 'Autosave',
          value: kAutosaveIntervals.any((o) => o.id == '${ds.autosaveMs}') ? '${ds.autosaveMs}' : '900',
          items: [for (final o in kAutosaveIntervals) DropdownMenuItem(value: o.id, child: Text(o.label))],
          onChanged: (v) => dev.update(ds.copyWith(autosaveMs: int.tryParse(v ?? '') ?? 900)),
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Line numbers'), value: ds.lineNumbers, onChanged: (v) => dev.update(ds.copyWith(lineNumbers: v))),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Word wrap'), value: ds.wordWrap, onChanged: (v) => dev.update(ds.copyWith(wordWrap: v))),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Syntax highlighting'), subtitle: const Text('Variables, headers, constraints, JSON, XML and Markdown'), value: ds.highlight, onChanged: (v) => dev.update(ds.copyWith(highlight: v))),
        ]),
        _SettingsGroup(title: 'New prompts (stored in the vault)', children: [
        dropdown<String>(
          label: 'Default category for new prompts',
          value: kCategories.any((c) => c.id == s.defaultCategory) ? s.defaultCategory : 'custom',
          items: [for (final c in kCategories) DropdownMenuItem(value: c.id, child: Text(c.label))],
          onChanged: (v) => save(s.clone()..defaultCategory = v ?? 'custom'),
        ),
        ]),
        _SettingsGroup(title: 'Analysis (stored in the vault)', children: [
        dropdown<String>(
          label: 'Model used for token and cost estimates',
          value: selectedModel,
          items: allModels,
          onChanged: (v) => save(s.clone()..selectedModel = v ?? 'generic'),
        ),
        dropdown<String>(
          label: 'Scoring profile',
          value: kScoringProfiles.any((x) => x.id == s.scoringProfile) ? s.scoringProfile : 'default',
          items: [for (final x in kScoringProfiles) DropdownMenuItem(value: x.id, child: Text(x.label))],
          onChanged: (v) => save(s.clone()..scoringProfile = v ?? 'default'),
        ),
        dropdown<String>(
          label: 'Versions to keep per prompt',
          value: kVersionRetention.any((o) => o.id == '${s.versionRetention}') ? '${s.versionRetention}' : '25',
          items: [for (final o in kVersionRetention) DropdownMenuItem(value: o.id, child: Text(o.label))],
          onChanged: (v) => save(s.clone()..versionRetention = int.tryParse(v ?? '') ?? 25),
        ),
        dropdown<String>(
          label: 'Output-format hint in the analyzer',
          value: kOutputFormatHints.any((o) => o.id == s.outputFormatHint) ? s.outputFormatHint : kOutputFormatHints.first.id,
          items: [for (final o in kOutputFormatHints) DropdownMenuItem(value: o.id, child: Text(o.label))],
          onChanged: (v) => save(s.clone()..outputFormatHint = v ?? 'none'),
        ),
        ]),
        const _SettingsGroup(title: 'Models & tokens', children: [ModelsSettingsCard()]),
        _SettingsGroup(title: 'Data', children: [
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.import_export), title: const Text('Import, export & backup'), subtitle: const Text('JSON backups, single files, restore'), onTap: () => context.push('/data')),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.school_outlined),
          title: const Text('Reset Learn progress'),
          subtitle: const Text('Clears completion marks and your saved answers'),
          onTap: () async {
            final ok = await confirmDialog(context, title: 'Reset progress?', message: 'Challenge completion marks and your saved rewrites are cleared.', confirmLabel: 'Reset', destructive: true);
            if (ok) await save(s.clone()..challengeProgress = <String, bool>{}..challengeAttempts = <String, ChallengeAttempt>{});
          },
        ),
        ]),
        _SettingsGroup(title: 'Clear data', children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Deletes the matching files from your vault folder. This cannot be undone, so export a backup first if unsure.', style: TextStyle(color: p.textTertiary, fontSize: 12)),
        ),
        for (final c in <(String, String, IconData, int)>[
          ('prompts', 'Prompts', Icons.description_outlined, vault.data.prompts.length),
          ('templates', 'Templates', Icons.article_outlined, vault.data.templates.length),
          ('patterns', 'Custom patterns', Icons.extension_outlined, vault.data.customPatterns.length),
          ('snippets', 'Snippets', Icons.bolt, vault.data.snippets.length),
          ('chains', 'Chains', Icons.link, vault.data.chains.length),
          ('groups', 'Groups', Icons.folder_special_outlined, vault.data.groups.length),
          ('structures', 'Saved builder structures', Icons.dashboard_customize_outlined, vault.data.builderStructures.length),
          ('searches', 'Saved searches', Icons.bookmark_outline, vault.data.savedSearches.length),
          ('history', 'Version history', Icons.history, -1),
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(c.$3, color: p.textSecondary),
            title: Text('Clear ${c.$2.toLowerCase()}'),
            subtitle: c.$4 < 0 ? null : Text('${c.$4} ${c.$4 == 1 ? 'item' : 'items'}'),
            enabled: c.$4 != 0,
            onTap: () async {
              final ok = await confirmDialog(context, title: 'Clear ${c.$2.toLowerCase()}?', message: 'Every ${c.$2.toLowerCase()} file in your vault will be deleted. This cannot be undone.', confirmLabel: 'Clear', destructive: true);
              if (!ok) return;
              final n = await vn.clearData(c.$1);
              if (context.mounted) toast(context, 'Cleared $n ${c.$2.toLowerCase()}');
            },
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.delete_forever_outlined, color: p.red),
          title: Text('Clear everything', style: TextStyle(color: p.red, fontWeight: FontWeight.w700)),
          subtitle: const Text('All of the above plus Learn progress. Settings and the folder itself stay.'),
          onTap: () async {
            final ok = await confirmDialog(context, title: 'Clear everything?', message: 'All prompts, templates, patterns, snippets, chains, groups, saved structures, searches and history are deleted from your vault folder.', confirmLabel: 'Delete all', destructive: true);
            if (!ok) return;
            final n = await vn.clearEverything();
            if (context.mounted) toast(context, 'Cleared $n items');
          },
        ),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.waving_hand_outlined), title: const Text('Replay welcome tour'), onTap: () => showWelcome(context, ref)),
        ]),
        const SectionTitle('About'),
        PfCard(
          child: Text(
            'Prompt Forge is an offline prompt workspace. It makes no network requests, calls no AI service and has no account or backend. '
            'Your prompts are Markdown files in the folder you chose.\n\n'
            'GPT-family token counts are exact (real cl100k tokenizer, built in); other models use a characters-per-token estimate. Scores are rule-based heuristics, not model evaluations.',
            style: TextStyle(color: p.textSecondary, fontSize: 13, height: 1.45),
          ),
        ),
      ]),
    );
  }
}

/// A settings card: small uppercase label, then the rows (like the web app's settings sections).
class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.borderSubtle)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PfCardLabel(title.replaceAll(RegExp(r' \((this device|stored in the vault)\)'), '')),
            ...children,
          ]),
        ),
      ),
    );
  }
}
