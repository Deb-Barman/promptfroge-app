import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_forge/domain/models.dart';

void main() {
  group('VaultSettings', () {
    test('defaults', () {
      final s = VaultSettings();
      expect(s.volumeCallsPerMonth, 1000);
      expect(s.defaultCategory, 'custom');
      expect(s.challengeAttempts, isEmpty);
    });

    test('round-trips attempts, volume and default category', () {
      final s = VaultSettings(
        volumeCallsPerMonth: 25000,
        defaultCategory: 'inbox',
        challengeProgress: {'c1': true},
        challengeAttempts: {'c1': const ChallengeAttempt(solved: true, score: 80, answer: 'my rewrite', attemptedAt: 123)},
      );
      final back = VaultSettings.fromMap(s.toMap());
      expect(back.volumeCallsPerMonth, 25000);
      expect(back.defaultCategory, 'inbox');
      expect(back.challengeProgress['c1'], isTrue);
      expect(back.challengeAttempts['c1']!.answer, 'my rewrite');
      expect(back.challengeAttempts['c1']!.score, 80);
      expect(back.challengeAttempts['c1']!.attemptedAt, 123);
    });

    test('reads the HTML app format: challengeProgress values are {solved, score, answer, attemptedAt}', () {
      final s = VaultSettings.fromMap({
        'challengeProgress': {
          'a': {'solved': true, 'score': 100, 'answer': 'x', 'attemptedAt': 5},
          'b': {'solved': false, 'score': 20, 'answer': 'y', 'attemptedAt': 6},
        },
      });
      expect(s.challengeProgress, {'a': true});
      expect(s.challengeAttempts['b']!.solved, isFalse);
      expect(s.challengeAttempts['b']!.answer, 'y');
    });

    test('reads this app\'s older format where progress was just true', () {
      final s = VaultSettings.fromMap({'challengeProgress': {'a': true}});
      expect(s.challengeProgress, {'a': true});
      expect(s.challengeAttempts, isEmpty);
    });

    test('volume is clamped to something sane and clone is independent', () {
      expect(VaultSettings.fromMap({'volumeCallsPerMonth': -5}).volumeCallsPerMonth, 1);
      final a = VaultSettings(challengeAttempts: {'x': const ChallengeAttempt(solved: false, score: 1, answer: '', attemptedAt: 0)});
      final b = a.clone()..challengeAttempts.remove('x');
      expect(a.challengeAttempts.containsKey('x'), isTrue);
      expect(b.challengeAttempts, isEmpty);
    });
  });
}
