import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../domain/engines/analyzer.dart';
import '../../../domain/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/pf_chrome.dart';

/// The web editor's "Prompt DNA" and "Prompt Analyzer" cards, shown under the text.
class EditorInsights extends StatelessWidget {
  final String text;
  final List<PromptBlock>? blocks;
  final String profileId;
  final ValueChanged<String> onProfile;
  const EditorInsights({super.key, required this.text, required this.blocks, required this.profileId, required this.onProfile});

  Color _barColor(PfPalette p, int v) => v < 50 ? p.red : (v < 80 ? p.amber : p.green);

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final dna = Analyzer.dnaProfile(text, blocks);
    final present = dna.where((e) => e.strength > 0).length;
    final res = Analyzer.analyze(text, profileId: profileId);
    final score = res.overall;
    String cap(String k) => k.isEmpty ? k : k[0].toUpperCase() + k.substring(1);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        PfCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const PfCardLabel('Prompt DNA'),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(children: [
                for (final e in dna) Expanded(child: Container(height: 11, color: pfColor(e.color).withOpacity(e.strength > 0 ? 0.45 + 0.55 * e.strength : 0.16))),
              ]),
            ),
            const SizedBox(height: 8),
            Text('$present of ${dna.length} elements present', style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
            const SizedBox(height: 10),
            Wrap(spacing: 12, runSpacing: 6, children: [
              for (final e in dna)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: pfColor(e.color).withOpacity(e.strength > 0 ? 1 : 0.4), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 5),
                  Text(e.label, style: TextStyle(fontSize: 11.5, color: e.strength > 0 ? p.textSecondary : p.textTertiary)),
                ]),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        PfCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: PfCardLabel('Prompt Analyzer')),
              Text('$score/100', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: scoreColor(context, score.toDouble()))),
            ]),
            PfSelect<String>(
              value: kScoringProfiles.any((x) => x.id == profileId) ? profileId : 'default',
              options: [for (final x in kScoringProfiles) MapEntry(x.id, x.label)],
              onChanged: onProfile,
            ),
            const SizedBox(height: 14),
            for (final e in res.scores.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(children: [
                  SizedBox(width: 92, child: Text(cap(e.key), style: TextStyle(fontSize: 12.5, color: p.textSecondary))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: e.value / 100, minHeight: 7, backgroundColor: p.surface3, valueColor: AlwaysStoppedAnimation(_barColor(p, e.value))),
                    ),
                  ),
                  SizedBox(width: 34, child: Text('${e.value}', textAlign: TextAlign.right, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback))),
                ]),
              ),
            if (res.issues.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final i in res.issues.take(6))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(i.level == 'error' ? Icons.error_outline : (i.level == 'warn' ? Icons.warning_amber_rounded : Icons.check_circle_outline), size: 16, color: i.level == 'error' ? p.red : (i.level == 'warn' ? p.amber : p.green)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(i.msg, style: TextStyle(fontSize: 12.5, color: p.textSecondary, height: 1.35))),
                  ]),
                ),
            ],
          ]),
        ),
      ],
    );
  }
}
