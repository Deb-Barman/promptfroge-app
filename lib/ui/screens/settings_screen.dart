import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../domain/models.dart';
import '../../state/device_settings.dart';
import '../../state/vault_notifier.dart';
import '../more_menu.dart';
import '../theme/app_theme.dart';
import '../onboarding.dart';
import '../widgets/pf_chrome.dart';
import '../widgets/common.dart';

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
          child: DropdownButtonFormField<T>(value: value, isExpanded: true, decoration: InputDecoration(labelText: label), items: items, onChanged: onChanged),
        );

    final allModels = [
      for (final m in kModels) DropdownMenuItem(value: m.id, child: Text(m.label)),
      for (final m in s.customModels) DropdownMenuItem(value: m.id, child: Text('${m.label} (custom)')),
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
        Text('Interface scale: ${(ds.uiScale * 100).round()}%', style: TextStyle(color: p.textSecondary, fontSize: 13)),
        Slider(value: ds.uiScale, min: 0.85, max: 1.3, divisions: 9, label: '${(ds.uiScale * 100).round()}%', onChanged: (v) => dev.update(ds.copyWith(uiScale: double.parse(v.toStringAsFixed(2))))),
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
        _SettingsGroup(title: 'Custom models', children: [
        Text('Add a model so token and cost estimates use its context window and price. Token counts for custom models are characters-per-token estimates.', style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
        const SizedBox(height: 8),
        for (final m in s.customModels)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(m.label),
            subtitle: Text('${m.vendor} · ${m.contextWindow} ctx · \$${m.priceIn}/\$${m.priceOut} per 1M · ${m.charsPerToken} chars/token'),
            onTap: () => _editModel(context, ref, m),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final next = s.clone()..customModels.removeWhere((x) => x.id == m.id);
                if (next.selectedModel == m.id) next.selectedModel = 'generic';
                await save(next);
              },
            ),
          ),
        if (s.customModels.length >= 2)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: Icon(Icons.delete_sweep_outlined, color: p.red),
              label: Text('Remove all ${s.customModels.length} custom models', style: TextStyle(color: p.red)),
              onPressed: () async {
                final ok = await confirmDialog(context, title: 'Remove all custom models?', message: 'Prompts keep working; token estimates fall back to the generic model if one of these was selected.', confirmLabel: 'Remove all', destructive: true);
                if (!ok) return;
                final next = s.clone()..customModels.clear();
                if (!kModels.any((m) => m.id == next.selectedModel)) next.selectedModel = 'generic';
                await save(next);
              },
            ),
          ),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(icon: const Icon(Icons.add), label: const Text('Add model'), onPressed: () => _editModel(context, ref, null))),
        ]),
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

  Future<void> _editModel(BuildContext context, WidgetRef ref, CustomModel? existing) async {
    final label = TextEditingController(text: existing?.label ?? '');
    final vendor = TextEditingController(text: existing?.vendor ?? 'Custom');
    final cpt = TextEditingController(text: '${existing?.charsPerToken ?? 4.0}');
    final ctx = TextEditingController(text: '${existing?.contextWindow ?? 32000}');
    final pin = TextEditingController(text: '${existing?.priceIn ?? 0}');
    final pout = TextEditingController(text: '${existing?.priceOut ?? 0}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(existing == null ? 'Add model' : 'Edit model'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: label, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: vendor, decoration: const InputDecoration(labelText: 'Vendor')),
            TextField(controller: cpt, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Characters per token')),
            TextField(controller: ctx, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Context window (tokens)')),
            TextField(controller: pin, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Input price per 1M tokens (USD)')),
            TextField(controller: pout, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Output price per 1M tokens (USD)')),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))],
      ),
    );
    final vals = (label.text.trim(), vendor.text.trim(), double.tryParse(cpt.text.trim()), int.tryParse(ctx.text.trim()), double.tryParse(pin.text.trim()), double.tryParse(pout.text.trim()));
    for (final c in [label, vendor, cpt, ctx, pin, pout]) {
      c.dispose();
    }
    if (ok != true) return;
    if (vals.$1.isEmpty || vals.$3 == null || vals.$3! <= 0 || vals.$4 == null || vals.$4! <= 0) {
      if (context.mounted) toast(context, 'Enter a name, a positive chars-per-token and a context window.');
      return;
    }
    final vn = ref.read(vaultProvider.notifier);
    final s = ref.read(vaultProvider).data.settings.clone();
    final m = CustomModel(
      id: existing?.id,
      label: vals.$1,
      vendor: vals.$2.isEmpty ? 'Custom' : vals.$2,
      charsPerToken: vals.$3!,
      contextWindow: vals.$4!,
      priceIn: vals.$5 ?? 0,
      priceOut: vals.$6 ?? 0,
    );
    final i = s.customModels.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      s.customModels[i] = m;
    } else {
      s.customModels.add(m);
    }
    await vn.updateSettings(s);
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
