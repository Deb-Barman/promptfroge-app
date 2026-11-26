import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../domain/engines/brain.dart';
import '../../state/brain_provider.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Opens the editor brain dashboard: its level, what it has learned from the vault, and how well its
/// suggestions have matched what the user actually accepted.
Future<void> showBrainSheet(BuildContext context) => showPfSheet<void>(context, full: true, builder: (_) => const BrainPanel());

class BrainPanel extends ConsumerWidget {
  const BrainPanel({super.key});

  static const _sourceColors = <BrainSource, int>{
    BrainSource.prompt: 0xFFE8A33D,
    BrainSource.template: 0xFF5B8DEF,
    BrainSource.pattern: 0xFF9B7FE0,
    BrainSource.snippet: 0xFF4FAE7A,
    BrainSource.chain: 0xFFE58A5A,
  };
  static const _sourceNames = <BrainSource, String>{
    BrainSource.prompt: 'Prompts',
    BrainSource.template: 'Templates',
    BrainSource.pattern: 'Patterns',
    BrainSource.snippet: 'Snippets',
    BrainSource.chain: 'Chains',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pf;
    final st = ref.watch(brainProvider);
    final model = st.model;
    if (model == null) {
      return const Padding(padding: EdgeInsets.fromLTRB(24, 8, 24, 40), child: Center(child: CircularProgressIndicator()));
    }
    final lvl = model.level;
    final stats = model.stats;
    final total = stats.documents == 0 ? 1 : stats.documents;
    final nextName = lvl.level < kBrainLevels.length ? kBrainLevels[lvl.level].$2 : null;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.violet.withValues(alpha: 0.20), p.amber.withValues(alpha: 0.10)]),
            border: Border.all(color: p.violet.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            SizedBox(
              width: 92,
              height: 92,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: lvl.progress),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => CustomPaint(
                  painter: _RingPainter(progress: v, color: p.amber, track: p.surface3),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('LV', style: TextStyle(fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w700, color: p.textTertiary)),
                      Text('${lvl.level}', style: TextStyle(fontSize: 30, height: 1, fontWeight: FontWeight.w800, color: p.text)),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.psychology, size: 20, color: p.violet),
                  const SizedBox(width: 6),
                  Text(lvl.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 6),
                Text(
                  nextName == null ? 'Top level reached — it keeps getting sharper with every prompt you write.' : '${lvl.nextAt - lvl.points} more to reach $nextName. Write, import or save more prompts, templates and patterns.',
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: p.textSecondary),
                ),
                if (st.building) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: p.amber)),
                    const SizedBox(width: 8),
                    Text('Learning from your latest changes…', style: TextStyle(fontSize: 11.5, color: p.textTertiary)),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _Stat(label: 'Words learned', value: _compact(stats.tokens))),
          const SizedBox(width: 8),
          Expanded(child: _Stat(label: 'Vocabulary', value: _compact(stats.vocabulary))),
          const SizedBox(width: 8),
          Expanded(child: _Stat(label: 'Phrases', value: _compact(stats.phrases))),
          const SizedBox(width: 8),
          Expanded(child: _Stat(label: 'Documents', value: _compact(stats.documents))),
        ]),
        if (stats.documents > 0) ...[
          const SectionTitle('Learns from'),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(children: [
                for (final s in _sourceNames.keys)
                  if ((stats.bySource[s] ?? 0) > 0) Expanded(flex: math.max(1, ((stats.bySource[s]! / total) * 1000).round()), child: ColoredBox(color: pfColor(_sourceColors[s]!))),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 14, runSpacing: 6, children: [
            for (final s in _sourceNames.keys)
              if ((stats.bySource[s] ?? 0) > 0)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: pfColor(_sourceColors[s]!), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('${_sourceNames[s]} ${stats.bySource[s]}', style: TextStyle(fontSize: 12, color: p.textSecondary)),
                ]),
          ]),
        ],
        const SectionTitle('Suggestion accuracy'),
        PfCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(st.usage.shown == 0 ? 'No suggestions shown yet' : '${(st.usage.acceptRate * 100).round()}% accepted', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${st.usage.acceptedTotal} of ${st.usage.shown}', style: TextStyle(fontSize: 12, color: p.textTertiary)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: st.usage.acceptRate, minHeight: 7, color: p.green, backgroundColor: p.surface2)),
            const SizedBox(height: 8),
            Text('Words and phrases you accept are ranked higher next time.', style: TextStyle(fontSize: 12, color: p.textTertiary)),
          ]),
        ),
        if (model.topPhrases.isNotEmpty) ...[
          const SectionTitle('Phrases you use'),
          Wrap(spacing: 7, runSpacing: 7, children: [for (final ph in model.topPhrases.take(14)) _Tag(ph.text, p.amber, count: ph.weight.round())]),
        ],
        if (model.topWords.isNotEmpty) ...[
          const SectionTitle('Words you favour'),
          Wrap(spacing: 7, runSpacing: 7, children: [for (final w in model.topWords.take(20)) _Tag(w.key, p.blue, count: w.value.round())]),
        ],
        if (model.topSections.isNotEmpty) ...[
          const SectionTitle('Sections you write'),
          for (final s in model.topSections.take(6))
            _SectionBar(label: blockTypeById(s.key)?.label ?? s.key, value: s.value, max: model.topSections.first.value, color: pfColor(blockTypeById(s.key)?.color ?? 0xFF7A8290)),
        ],
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.refresh, size: 18), label: const Text('Relearn now'), onPressed: st.building ? null : () => ref.read(brainProvider.notifier).relearn())),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset ranking'),
              onPressed: () async {
                final ok = await confirmDialog(context, title: 'Reset personal ranking?', message: 'This forgets which suggestions you accepted. Your prompts, templates and patterns are not touched.', confirmLabel: 'Reset', destructive: true);
                if (ok) ref.read(brainProvider.notifier).resetPersonalLearning();
              },
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lock_outline, size: 14, color: p.textTertiary),
          const SizedBox(width: 6),
          Expanded(child: Text('The brain is a small statistical model built on this device from your own vault. No AI service, no network, nothing leaves your phone.', style: TextStyle(fontSize: 11.5, height: 1.45, color: p.textTertiary))),
        ]),
      ],
    );
  }

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 10000) return '${(n / 1000).round()}k';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.borderSubtle)),
      child: Column(children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: p.textTertiary)),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  final int count;
  const _Tag(this.text, this.color, {required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
        const SizedBox(width: 6),
        Text('×$count', style: TextStyle(fontSize: 10.5, color: color.withValues(alpha: 0.7))),
      ]),
    );
  }
}

class _SectionBar extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final Color color;
  const _SectionBar({required this.label, required this.value, required this.max, required this.color});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 118, child: Text(label, style: TextStyle(fontSize: 12.5, color: p.textSecondary))),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: max <= 0 ? 0 : (value / max).clamp(0.0, 1.0), minHeight: 7, color: color, backgroundColor: p.surface2))),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  _RingPainter({required this.progress, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 5;
    final rect = Rect.fromCircle(center: c, radius: r);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = track;
    canvas.drawCircle(c, r, base);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8
      ..shader = SweepGradient(startAngle: -math.pi / 2, endAngle: 3 * math.pi / 2, colors: [color.withValues(alpha: 0.55), color], transform: const GradientRotation(-math.pi / 2)).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress.clamp(0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress || old.color != color || old.track != track;
}
