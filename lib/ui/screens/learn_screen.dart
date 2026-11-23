import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/util.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/pf_chrome.dart';
import '../widgets/common.dart';

class LearnScreen extends ConsumerWidget {
  const LearnScreen({super.key});

  Color _levelColor(PfPalette p, String level) => level == 'beginner' ? p.green : (level == 'intermediate' ? p.amber : p.red);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pf;
    final settings = ref.watch(vaultProvider).data.settings;
    final progress = settings.challengeProgress;
    final attempts = settings.challengeAttempts;
    final solved = kChallenges.where((c) => progress[c.id] == true).length;
    return Scaffold(
      appBar: PfAppBar(title: const Text('Learn')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Text('$solved of ${kChallenges.length} challenges completed', style: TextStyle(color: p.textSecondary)),
        const SectionTitle('Tips'),
        for (var i = 0; i < kLearnTips.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PfCard(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((i + 1).toString().padLeft(2, '0'), style: TextStyle(color: p.amber, fontWeight: FontWeight.w800, fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback)),
                const SizedBox(width: 12),
                Expanded(child: Text(kLearnTips[i], style: TextStyle(color: p.textSecondary, height: 1.4, fontSize: 13.5))),
              ]),
            ),
          ),
        const SectionTitle('Challenges'),
        for (final c in kChallenges)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PfCard(
              onTap: () => showPfSheet<void>(context, title: c.title, full: true, builder: (_) => _ChallengeSheet(challenge: c)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    StatusBadge(c.level.toUpperCase(), _levelColor(p, c.level)),
                    const SizedBox(height: 6),
                    Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(c.task, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
                    if (attempts[c.id] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Last attempt: ${attempts[c.id]!.score}/100 · ${Utils.timeAgo(attempts[c.id]!.attemptedAt)}', style: TextStyle(color: p.textTertiary, fontSize: 11.5)),
                      ),
                  ]),
                ),
                Icon(progress[c.id] == true ? Icons.check_circle : Icons.chevron_right, color: progress[c.id] == true ? p.green : p.textTertiary),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _ChallengeSheet extends ConsumerStatefulWidget {
  final Challenge challenge;
  const _ChallengeSheet({required this.challenge});

  @override
  ConsumerState<_ChallengeSheet> createState() => _ChallengeSheetState();
}

class _ChallengeSheetState extends ConsumerState<_ChallengeSheet> {
  late final _answer = TextEditingController(text: ref.read(vaultProvider).data.settings.challengeAttempts[widget.challenge.id]?.answer ?? '');
  late int? _score = ref.read(vaultProvider).data.settings.challengeAttempts[widget.challenge.id]?.score;
  late bool _solved = ref.read(vaultProvider).data.settings.challengeAttempts[widget.challenge.id]?.solved ?? false;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  /// Same rule as the original app: keyword coverage >= 40% and longer than the original prompt.
  Future<void> _check() async {
    final c = widget.challenge;
    final text = _answer.text;
    final lower = text.toLowerCase();
    final hits = c.checkKeywords.where(lower.contains).length;
    final score = ((hits / c.checkKeywords.length) * 100).round();
    final solved = score >= 40 && text.trim().length > c.prompt.length;
    setState(() {
      _score = score;
      _solved = solved;
    });
    // Every attempt is remembered (answer + score), exactly like the original. A solved mark is never taken back.
    final vn = ref.read(vaultProvider.notifier);
    final s = ref.read(vaultProvider).data.settings.clone();
    s.challengeAttempts[c.id] = ChallengeAttempt(solved: solved, score: score, answer: text, attemptedAt: Utils.nowMs());
    if (solved) s.challengeProgress[c.id] = true;
    await vn.updateSettings(s);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final c = widget.challenge;
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
      Text(c.task, style: TextStyle(color: p.textSecondary, height: 1.45)),
      const SectionTitle('Original prompt'),
      PfCard(child: Text(c.prompt, style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, color: p.textTertiary))),
      const SizedBox(height: 12),
      TextField(controller: _answer, minLines: 5, maxLines: 10, decoration: const InputDecoration(labelText: 'Your rewrite', alignLabelWithHint: true)),
      const SizedBox(height: 12),
      FilledButton(onPressed: _check, child: const Text('Check my answer')),
      if (_score != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: PfCard(
            color: (_solved ? p.green : p.amber).withOpacity(0.1),
            child: Text(
              'Local score: $_score/100 — ${_solved ? 'nice work, this hits the key elements.' : 'getting there — look for: ${c.checkKeywords.take(3).join(', ')}'}',
              style: TextStyle(color: _solved ? p.green : p.amber),
            ),
          ),
        ),
    ]);
  }
}
