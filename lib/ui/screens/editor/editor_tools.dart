import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/util.dart';
import '../../../domain/engines/analyzer.dart';
import '../../../domain/engines/cleaner.dart';
import '../../../domain/engines/format_converter.dart';
import '../../../domain/engines/readability.dart';
import '../../../domain/engines/template_engine.dart';
import '../../../domain/engines/token_estimator.dart';
import '../../../domain/engines/tools.dart';
import '../../../domain/engines/validator.dart';
import '../../../state/tokenizer_provider.dart';
import '../../../state/vault_notifier.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/pf_menu.dart';

/// What the tools sheet needs from the editor.
abstract class EditorHost {
  String get text;
  String get format;
  String get title;
  String? get promptId;
  void replaceText(String text);
  void insertAtCursor(String text);
  void setFormat(String format);
  void openAsNew(String body, {String? title, String? format});
  void jumpToOffset(int offset);
}

Future<void> showEditorTools(BuildContext context, EditorHost host, {int initialTab = 0}) {
  return showPfSheet<void>(context, title: 'Prompt tools', full: true, builder: (ctx) => _ToolsSheet(host: host, initialTab: initialTab));
}

class _ToolsSheet extends ConsumerStatefulWidget {
  final EditorHost host;
  final int initialTab;
  const _ToolsSheet({required this.host, this.initialTab = 0});

  @override
  ConsumerState<_ToolsSheet> createState() => _ToolsSheetState();
}

class _ToolsSheetState extends ConsumerState<_ToolsSheet> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 6, vsync: this, initialIndex: widget.initialTab.clamp(0, 5));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.78;
    return SizedBox(
      height: h,
      child: Column(children: [
        TabBar(controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [
          Tab(text: 'Analyze'),
          Tab(text: 'Scan'),
          Tab(text: 'Transform'),
          Tab(text: 'Variables'),
          Tab(text: 'Copy as'),
          Tab(text: 'Checklist'),
        ]),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            _AnalyzeTab(host: widget.host),
            _ScanTab(host: widget.host, onChanged: refresh),
            _TransformTab(host: widget.host, onChanged: refresh),
            _VariablesTab(host: widget.host, onChanged: refresh),
            _CopyAsTab(host: widget.host),
            _ChecklistTab(host: widget.host),
          ]),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ analyze

class _AnalyzeTab extends ConsumerWidget {
  final EditorHost host;
  const _AnalyzeTab({required this.host});

  static const labels = {
    'clarity': 'Clarity',
    'context': 'Context',
    'specificity': 'Specificity',
    'structure': 'Structure',
    'constraints': 'Constraints',
    'output': 'Output format',
    'completeness': 'Completeness',
    'ambiguity': 'Low ambiguity',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pf;
    final d = ref.watch(vaultProvider).data;
    final text = host.text;
    if (text.trim().isEmpty) {
      return const EmptyState(icon: Icons.analytics_outlined, title: 'Nothing to analyze', body: 'Write some prompt text and the scores appear here.');
    }
    final a = Analyzer.analyze(text, profileId: d.settings.scoringProfile);
    final improvements = Analyzer.improve(text);
    final read = ReadabilityEngine.analyze(text);
    ref.watch(tokenizerProvider);
    final est = TokenEstimator.estimateCost(text, d.settings.selectedModel, d.settings.customModels);
    final exact = TokenEstimator.isExact(d.settings.selectedModel, d.settings.customModels);
    final pendingExact = TokenEstimator.isPendingExact(d.settings.selectedModel, d.settings.customModels);
    final sections = FormatConverter.extractSections(text, 'text');
    final sectionTokens = sections.length < 2
        ? const <(String, int)>[]
        : [for (final sec in sections) (sec.label, TokenEstimator.estimateTokens(sec.content, d.settings.selectedModel, d.settings.customModels))];
    final sectionTotal = sectionTokens.fold<int>(0, (a, b) => a + b.$2) == 0 ? 1 : sectionTokens.fold<int>(0, (a, b) => a + b.$2);
    final ctx = TokenEstimator.contextStatus(text, d.settings.selectedModel, d.settings.customModels);
    final blocks = d.prompts[host.promptId]?.blocks;
    final dna = Analyzer.dnaProfile(text, blocks);
    final profile = kScoringProfiles.firstWhere((x) => x.id == a.profileId, orElse: () => kScoringProfiles.first);

    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        ScoreRing(a.overall, size: 76),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Overall score', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 2),
            Text('${a.wordCount} words · profile: ${profile.label}', style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
            const SizedBox(height: 2),
            Text('Heuristic score from local rules — not a model evaluation.', style: TextStyle(color: p.textTertiary, fontSize: 11.5)),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      for (final e in labels.entries)
        if (a.scores.containsKey(e.key)) Padding(padding: const EdgeInsets.only(bottom: 8), child: ScoreBar(e.value, a.scores[e.key]!)),
      const SizedBox(height: 8),
      if (dna.isNotEmpty) ...[
        const SectionTitle('Prompt DNA'),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Row(children: [
              for (final e in dna)
                if (e.strength > 0) Expanded(flex: (e.strength * 100).round().clamp(1, 1000), child: Container(color: pfColor(e.color))),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 4, children: [
          for (final e in dna)
            if (e.strength > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(radius: 4, backgroundColor: pfColor(e.color)),
                const SizedBox(width: 5),
                Text('${e.label} ${(e.strength * 100).round()}%', style: TextStyle(fontSize: 11.5, color: p.textSecondary)),
              ]),
        ]),
        const SizedBox(height: 8),
      ],
      const SectionTitle('Findings'),
      for (final i in a.issues)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(i.level == 'ok' ? Icons.check_circle_outline : (i.level == 'error' ? Icons.error_outline : Icons.warning_amber_rounded), size: 20, color: i.level == 'ok' ? p.green : (i.level == 'error' ? p.red : p.amber)),
          title: Text(i.msg, style: const TextStyle(fontSize: 13.5)),
        ),
      if (improvements.isNotEmpty) ...[
        const SectionTitle('Suggested improvements'),
        for (final i in improvements)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PfCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i.title, style: TextStyle(color: p.amber, fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                Text(i.detail, style: const TextStyle(fontSize: 13)),
              ]),
            ),
          ),
      ],
      const SectionTitle('Readability'),
      KeyValueRow('Flesch reading ease', '${read.fleschScore} (${read.label})'),
      KeyValueRow('Grade level', '${read.gradeLevel}'),
      KeyValueRow('Avg. sentence length', '${read.avgSentenceLen} words'),
      SectionTitle(exact ? 'Size (exact tokens)' : 'Size (estimate)'),
      KeyValueRow('Model', est.model.label),
      KeyValueRow(exact ? 'Prompt tokens' : 'Prompt tokens (est.)', '${exact ? '' : '~'}${est.promptTokens}'),
      KeyValueRow('Context window used', '${ctx.pct.toStringAsFixed(ctx.pct < 1 ? 2 : 1)}% of ${ctx.limit}'),
      KeyValueRow('Cost per call (est.)', '${_fmtCost(est.cost)}${est.model.priceIn == 0 ? '  (free / self-hosted)' : ''}'),
      const SizedBox(height: 6),
      _VolumeCost(perCall: est.cost, calls: d.settings.volumeCallsPerMonth),
      if (sectionTokens.length >= 2) ...[
        const SectionTitle('Tokens by section'),
        for (final t in sectionTokens)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 96, child: Text(t.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.textSecondary))),
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: (t.$2 / sectionTotal).clamp(0.03, 1.0).toDouble(), minHeight: 6, backgroundColor: p.surface2, color: p.textTertiary))),
              SizedBox(width: 44, child: Text('${(t.$2 / sectionTotal * 100).round()}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: p.textTertiary))),
            ]),
          ),
      ],
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          exact
              ? 'Counted with the real cl100k_base tokenizer, so this is exact for GPT-family models. Other vendors tokenize differently. Nothing is sent to any API.'
              : (pendingExact
                  ? 'Loading the exact tokenizer… showing a characters-per-token estimate until it is ready.'
                  : 'No public tokenizer exists for this model, so this is a characters-per-token estimate (real counts differ by roughly 10–20%). Nothing is sent to any API.'),
          style: TextStyle(color: p.textTertiary, fontSize: 11.5),
        ),
      ),
    ]);
  }
}

// --------------------------------------------------------------------- scan

class _ScanTab extends ConsumerWidget {
  final EditorHost host;
  final VoidCallback onChanged;
  const _ScanTab({required this.host, required this.onChanged});

  Widget _group(BuildContext c, String title, List<Widget> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SectionTitle(title), ...items]);
  }

  Widget _row(BuildContext c, IconData icon, Color color, String title, [String? sub]) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, size: 20, color: color),
        title: Text(title, style: const TextStyle(fontSize: 13.5)),
        subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 12)),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pf;
    final text = host.text;
    if (text.trim().isEmpty) return const EmptyState(icon: Icons.shield_outlined, title: 'Nothing to scan', body: 'Scans run locally on the text in the editor.');
    final sec = SecurityScanner.scan(text);
    final risk = RiskLinter.scan(text);
    final clean = PromptCleaner.inspect(text);
    final amb = PromptTools.scanAmbiguity(text);
    final adv = PromptTools.scanAdversarial(text);
    final red = PromptTools.findInternalRedundancy(text);
    final inj = PromptTools.checkInjectionSurface(text);
    final valid = PromptValidator.validate(text, host.format);
    final embed = PromptValidator.checkJsonEmbedSafety(text);
    final nothing = sec.isEmpty && risk.isEmpty && clean.isEmpty && amb.isEmpty && adv.isEmpty && red.isEmpty && inj.isEmpty && valid.valid;

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (nothing) _row(context, Icons.check_circle_outline, p.green, 'No problems found by the local scans.'),
      _group(context, 'Format check (${host.format})', [
        if (!valid.valid) _row(context, Icons.error_outline, p.red, valid.message ?? 'Invalid ${host.format}') else _row(context, Icons.check_circle_outline, p.green, 'Valid ${host.format}'),
      ]),
      _group(context, 'Secrets', [
        for (final f in sec) _row(context, Icons.key_off_outlined, p.red, '${f.label} (${f.count}x)', 'Looks like: ${f.sample}'),
      ]),
      _group(context, 'Risky phrasing', [
        for (final f in risk) _row(context, Icons.report_gmailerrorred_outlined, p.amber, f.label, f.detail),
      ]),
      _group(context, 'Mechanical issues', [
        for (final f in clean) _row(context, Icons.build_circle_outlined, p.amber, f.detail),
        if (clean.any((f) => f.type == 'whitespace'))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('Clean whitespace'),
              onPressed: () {
                host.replaceText(PromptCleaner.autoClean(text));
                toast(context, 'Whitespace cleaned (undo available)');
                onChanged();
              },
            ),
          ),
      ]),
      _group(context, 'Ambiguous sentences', [
        for (final f in amb) _row(context, Icons.help_outline, p.amber, Utils.truncate(f.sentence, 120)),
      ]),
      _group(context, 'Adversarial phrasing', [
        for (final f in adv) _row(context, Icons.gpp_maybe_outlined, p.red, f.label),
      ]),
      _group(context, 'Internal redundancy', [
        for (final f in red) _row(context, Icons.content_copy, p.amber, Utils.truncate(f.a, 70), 'similar to: ${Utils.truncate(f.b, 70)}'),
      ]),
      _group(context, 'Injection surface (variables)', [
        for (final f in inj) _row(context, Icons.warning_amber_rounded, p.amber, f.label, f.detail),
      ]),
      if (host.format == 'json' && embed.isNotEmpty)
        _group(context, 'Embedding in JSON', [
          for (final f in embed) _row(context, Icons.data_object, f.level == 'warn' ? p.amber : p.blue, f.label, f.detail),
        ]),
    ]);
  }
}

// ---------------------------------------------------------------- transform

class _TransformTab extends ConsumerWidget {
  final EditorHost host;
  final VoidCallback onChanged;
  const _TransformTab({required this.host, required this.onChanged});

  void _apply(BuildContext c, String result, String msg) {
    if (result == host.text) {
      toast(c, 'No change');
      return;
    }
    host.replaceText(result);
    toast(c, '$msg — undo from the editor toolbar');
    onChanged();
  }

  Widget _btn(BuildContext c, IconData icon, String label, VoidCallback fn) => Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: OutlinedButton.icon(icon: Icon(icon, size: 18), label: Text(label), onPressed: fn),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = host.text;
    final d = ref.watch(vaultProvider).data;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const SectionTitle('Rewrite (rule-based, offline)'),
      Wrap(children: [
        _btn(context, Icons.compress, 'Shorten', () => _apply(context, PromptTools.shorten(text), 'Shortened')),
        _btn(context, Icons.format_list_bulleted, 'Bulletify', () => _apply(context, PromptTools.bulletify(text), 'Bulletified')),
        _btn(context, Icons.table_chart_outlined, 'Lists → table', () {
          final t = PromptTools.tableify(text);
          if (t == null) {
            toast(context, 'No list-like lines found');
          } else {
            _apply(context, t, 'Converted to table');
          }
        }),
        _btn(context, Icons.psychology_outlined, 'Add reasoning block', () {
          host.insertAtCursor(PromptTools.chainOfThoughtBlock());
          toast(context, 'Inserted at cursor');
          onChanged();
        }),
      ]),
      const SectionTitle('Tone'),
      Wrap(spacing: 8, children: [
        for (final t in PromptTools.tones) ActionChip(label: Text(t[0].toUpperCase() + t.substring(1)), onPressed: () => _apply(context, PromptTools.toneShift(text, t), 'Tone: $t')),
      ]),
      const SizedBox(height: 8),
      const SectionTitle('Structure'),
      Wrap(children: [
        _btn(context, Icons.code, 'Wrap in XML tags', () => _apply(context, ModelAdapter.wrapInXml(text, host.format), 'Wrapped in XML tags')),
      ]),
      const SectionTitle('Adapt for a model family'),
      Wrap(spacing: 8, children: [
        for (final e in kModelIdioms.entries)
          ActionChip(
            label: Text(e.value.label),
            onPressed: () => showPfSheet<void>(context, title: 'Adapt: ${e.value.label}', builder: (ctx) {
              final adapted = ModelAdapter.adapt(text, host.format, e.key);
              return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
                Text(e.value.comparative, style: TextStyle(color: ctx.pf.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                for (final tip in e.value.tips) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $tip', style: const TextStyle(fontSize: 13))),
                const SizedBox(height: 12),
                PfCard(child: SelectableText(adapted, style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 12.5))),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => copyToClipboard(ctx, adapted), child: const Text('Copy'))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _apply(context, adapted, 'Adapted for ${e.value.label}');
                      },
                      child: const Text('Replace text'),
                    ),
                  ),
                ]),
              ]);
            }),
          ),
      ]),
      const SizedBox(height: 8),
      const SectionTitle('Convert format'),
      Wrap(spacing: 8, children: [
        for (final f in kPromptFormats)
          if (f.id != host.format)
            ActionChip(
              label: Text('→ ${f.label}'),
              onPressed: () {
                final out = FormatConverter.convert(text, host.format, f.id);
                host.replaceText(out);
                host.setFormat(f.id);
                toast(context, 'Converted to ${f.label}');
                onChanged();
              },
            ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text('Model for sizing: ${TokenEstimator.getModel(d.settings.selectedModel, d.settings.customModels).label}', style: TextStyle(color: context.pf.textTertiary, fontSize: 11.5)),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- variables

class _VariablesTab extends ConsumerStatefulWidget {
  final EditorHost host;
  final VoidCallback onChanged;
  const _VariablesTab({required this.host, required this.onChanged});

  @override
  ConsumerState<_VariablesTab> createState() => _VariablesTabState();
}

class _VariablesTabState extends ConsumerState<_VariablesTab> {
  final Map<String, String> _values = {};
  final Set<int> _picked = {};

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final text = widget.host.text;
    final specs = TemplateEngine.extractVariableSpecs(text);
    final spans = TemplateEngine.detectParameterizableSpans(text);
    final merged = <String, String>{for (final s in specs) s.name: _values[s.name] ?? s.defaultValue};
    final rendered = TemplateEngine.render(text, merged);

    return ListView(padding: const EdgeInsets.all(16), children: [
      const SectionTitle('Fill variables'),
      if (specs.isEmpty)
        Text('No {{variables}} in this prompt. Use {{name}}, {{name:number}}, {{name:select:a|b|c}} or {{name=default}}.', style: TextStyle(color: p.textSecondary, fontSize: 13))
      else ...[
        for (final s in specs)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: s.type == 'select' && s.options.isNotEmpty
                ? PfField<String>(
                    label: TemplateEngine.humanizeVarName(s.name),
                    value: s.options.contains(_values[s.name]) ? _values[s.name] : (s.options.contains(s.defaultValue) ? s.defaultValue : null),
                    items: [for (final o in s.options) PfMenuItem<String>(o, o)],
                    onChanged: (v) => setState(() => _values[s.name] = v),
                  )
                : TextFormField(
                    initialValue: _values[s.name] ?? s.defaultValue,
                    keyboardType: s.type == 'number' ? TextInputType.number : TextInputType.multiline,
                    maxLines: s.type == 'multiline' ? 4 : 1,
                    decoration: InputDecoration(labelText: TemplateEngine.humanizeVarName(s.name), hintText: '{{${s.name}}}'),
                    onChanged: (v) => setState(() => _values[s.name] = v),
                  ),
          ),
        const SectionTitle('Result'),
        PfCard(child: SelectableText(rendered, style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 12.5))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.copy, size: 18), label: const Text('Copy'), onPressed: () => copyToClipboard(context, rendered))),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.note_add_outlined, size: 18),
              label: const Text('Save as new prompt'),
              onPressed: () {
                Navigator.pop(context);
                widget.host.openAsNew(rendered, title: '${widget.host.title} (filled)', format: widget.host.format);
              },
            ),
          ),
        ]),
        if (TemplateEngine.hasUnfilledVariables(rendered))
          Padding(padding: const EdgeInsets.only(top: 8), child: Text('Some variables are still empty.', style: TextStyle(color: p.amber, fontSize: 12.5))),
      ],
      const SizedBox(height: 8),
      SectionTitle('Turn text into variables', trailing: spans.isEmpty ? null : Text('${spans.length} candidates', style: TextStyle(color: p.textTertiary, fontSize: 12))),
      if (spans.isEmpty)
        Text('Nothing that looks parameterizable (quoted strings, numbers, proper names).', style: TextStyle(color: p.textSecondary, fontSize: 13))
      else ...[
        for (var i = 0; i < spans.length; i++)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _picked.contains(i),
            onChanged: (v) => setState(() => v == true ? _picked.add(i) : _picked.remove(i)),
            title: Text(spans[i].text, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(spans[i].kind),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: _picked.isEmpty
                ? null
                : () {
                    final reps = <VarReplacement>[];
                    final used = <String>{...specs.map((s) => s.name)};
                    for (final i in _picked) {
                      var base = spans[i].text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
                      if (base.isEmpty) base = spans[i].kind;
                      if (base.length > 24) base = base.substring(0, 24);
                      var name = base;
                      var n = 2;
                      while (used.contains(name)) {
                        name = '${base}_${n++}';
                      }
                      used.add(name);
                      reps.add(VarReplacement(spans[i].text, name));
                    }
                    widget.host.replaceText(TemplateEngine.applyExtractedVariables(text, reps));
                    setState(_picked.clear);
                    toast(context, 'Variables created');
                    widget.onChanged();
                  },
            child: const Text('Replace selected with {{variables}}'),
          ),
        ),
      ],
    ]);
  }
}

// ------------------------------------------------------------------ copy as

class _CopyAsTab extends ConsumerStatefulWidget {
  final EditorHost host;
  const _CopyAsTab({required this.host});

  @override
  ConsumerState<_CopyAsTab> createState() => _CopyAsTabState();
}

class _CopyAsTabState extends ConsumerState<_CopyAsTab> {
  String? _fmt;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final d = ref.watch(vaultProvider).data;
    final model = TokenEstimator.getModel(d.settings.selectedModel, d.settings.customModels);
    final options = MessageComposer.formatsFor(model.vendor);
    final fmt = options.any((o) => o.id == _fmt) ? _fmt! : options.first.id;
    final out = MessageComposer.render(widget.host.text, fmt, model.id, model.vendor);
    final plain = <String, String>{
      'Plain text': widget.host.text,
      'Markdown code block': '```\n${widget.host.text}\n```',
    };
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('These are formatted snippets for pasting into your own tools. Nothing is sent anywhere.', style: TextStyle(color: p.textSecondary, fontSize: 13)),
      const SectionTitle('Plain'),
      Wrap(spacing: 8, children: [
        for (final e in plain.entries) ActionChip(avatar: const Icon(Icons.copy, size: 16), label: Text(e.key), onPressed: () => copyToClipboard(context, e.value)),
      ]),
      SectionTitle('For ${model.label}'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final o in options) PfChip(label: o.label, selected: o.id == fmt, color: p.amber, onTap: () => setState(() => _fmt = o.id)),
      ]),
      const SizedBox(height: 12),
      PfCard(child: SelectableText(out, style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 12))),
      const SizedBox(height: 8),
      FilledButton.icon(icon: const Icon(Icons.copy, size: 18), label: const Text('Copy snippet'), onPressed: () => copyToClipboard(context, out)),
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text('API keys are never included — snippets use a placeholder such as YOUR_API_KEY.', style: TextStyle(color: p.textTertiary, fontSize: 11.5)),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- checklist

class _ChecklistTab extends ConsumerWidget {
  final EditorHost host;
  const _ChecklistTab({required this.host});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pf;
    final id = host.promptId;
    final prompt = id == null ? null : ref.watch(vaultProvider).data.prompts[id];
    if (prompt == null) {
      return const EmptyState(icon: Icons.checklist, title: 'Save the prompt first', body: 'The edge-case checklist is stored with the prompt file, so it needs to exist in your folder.');
    }
    final done = kEdgeCaseChecklist.where((e) => prompt.edgeCaseChecks[e.id] == true).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Edge-case review: $done of ${kEdgeCaseChecklist.length} considered', style: TextStyle(color: p.textSecondary, fontSize: 13)),
      const SizedBox(height: 8),
      for (final e in kEdgeCaseChecklist)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: prompt.edgeCaseChecks[e.id] == true,
          title: Text(e.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(e.question, style: const TextStyle(fontSize: 12.5)),
          onChanged: (v) => ref.read(vaultProvider.notifier).setEdgeCheck(prompt.id, e.id, v ?? false),
        ),
    ]);
  }
}


String _fmtCost(double c) => c == 0 ? '\$0' : (c < 0.01 ? '\$${c.toStringAsFixed(5)}' : '\$${c.toStringAsFixed(4)}');

/// Same precision rules as the original: more decimals for small totals, whole dollars for big ones.
String formatVolumeCost(double total) {
  if (total == 0) return '\$0';
  if (total < 0.01) return '\$${total.toStringAsFixed(5)}';
  if (total < 10) return '\$${total.toStringAsFixed(3)}';
  final whole = total.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  return '\$$buf';
}

/// "At [1000] calls/mo: $x" - the monthly projection, with the call count saved in the vault settings.
class _VolumeCost extends ConsumerStatefulWidget {
  final double perCall;
  final int calls;
  const _VolumeCost({required this.perCall, required this.calls});

  @override
  ConsumerState<_VolumeCost> createState() => _VolumeCostState();
}

class _VolumeCostState extends ConsumerState<_VolumeCost> {
  late final _ctrl = TextEditingController(text: '${widget.calls}');
  late int _calls = widget.calls;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Row(children: [
      Text('At', style: TextStyle(fontSize: 12, color: p.textTertiary)),
      const SizedBox(width: 8),
      SizedBox(
        width: 96,
        child: TextField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n == null || n < 1) return;
            setState(() => _calls = n);
            final vn = ref.read(vaultProvider.notifier);
            vn.updateSettings(ref.read(vaultProvider).data.settings.clone()..volumeCallsPerMonth = n);
          },
        ),
      ),
      const SizedBox(width: 8),
      Text('calls/mo:', style: TextStyle(fontSize: 12, color: p.textTertiary)),
      const SizedBox(width: 8),
      Text(formatVolumeCost(widget.perCall * _calls), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    ]);
  }
}
