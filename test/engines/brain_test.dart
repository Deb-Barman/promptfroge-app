import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_forge/domain/engines/brain.dart';

const _aliases = {
  'role': 'role',
  'task': 'task',
  'context': 'context',
  'constraints': 'constraints',
  'output format': 'output',
  'output': 'output',
};

List<BrainDoc> _corpus(int copies) => [
      for (var i = 0; i < copies; i++)
        const BrainDoc(
          'Role: Act as a world class hyperlocal strategist with {{years}} experience.\nTask: Write a detailed action plan for the team.\nConstraints:\n- Keep it short.\nOutput Format: JSON',
          BrainSource.prompt,
        ),
    ];

void main() {
  group('BrainModel', () {
    test('learns the vocabulary of the user\'s own prompts', () {
      final empty = BrainModel.build(const [], includeSeed: false);
      expect(empty.complete('hyp').isEmpty, isTrue);
      final m = BrainModel.build(_corpus(4), sectionAliases: _aliases);
      final hits = m.complete('hyp');
      expect(hits.isNotEmpty, isTrue);
      expect(hits.first.insert, equals('hyperlocal'));
      expect(hits.first.matchLen, equals(3));
    });

    test('keeps the casing style of what was typed', () {
      final m = BrainModel.build(_corpus(4), sectionAliases: _aliases);
      expect(m.complete('Hyp').first.insert, equals('Hyperlocal'));
      expect(m.complete('HYP').first.insert, equals('HYPERLOCAL'));
    });

    test('predicts the next word and extends it into a phrase', () {
      final m = BrainModel.build(_corpus(5), sectionAliases: _aliases);
      final next = m.predictNext('Act as a ');
      expect(next.isNotEmpty, isTrue);
      expect(next.first.insert.startsWith('world'), isTrue);
      expect(next.first.kind, equals('next'));
      expect(next.any((h) => h.insert.startsWith('world class')), isTrue);
    });

    test('does not suggest for single letters, triggers or mid-token punctuation', () {
      final m = BrainModel.build(_corpus(4), sectionAliases: _aliases);
      expect(m.complete('h').isEmpty, isTrue);
      expect(m.complete('x {{ro').isEmpty, isTrue);
      expect(m.complete('see @hy').isEmpty, isTrue);
      expect(m.complete('hello ').isEmpty, isTrue);
    });

    test('never completes into something that saves fewer than two characters', () {
      final m = BrainModel.build(_corpus(4), sectionAliases: _aliases);
      for (final h in m.complete('stra')) {
        expect(h.insert.length - 4 >= 2, isTrue);
      }
    });

    test('words the user accepted rank higher next time', () {
      final m = BrainModel.build(_corpus(3), sectionAliases: _aliases);
      final before = m.complete('acti').map((h) => h.insert).toList();
      final usage = BrainUsage();
      final target = before.last;
      for (var i = 0; i < 12; i++) {
        usage.record(target);
      }
      final after = m.complete('acti', usage: usage).map((h) => h.insert).toList();
      expect(after.indexOf(target) <= before.indexOf(target), isTrue);
      expect(usage.acceptedTotal, equals(12));
    });

    test('usage survives a JSON round trip', () {
      final u = BrainUsage()
        ..record('Hyperlocal')
        ..shown = 5;
      final back = BrainUsage.fromJson(u.toJson());
      expect(back.accepted['hyperlocal'], equals(1));
      expect(back.shown, equals(5));
      expect(back.acceptRate > 0, isTrue);
    });

    test('ranks and recommends the sections the user usually writes', () {
      final m = BrainModel.build(_corpus(5), sectionAliases: _aliases);
      final hints = m.rankBlocks('Role: You are an expert.');
      final byId = {for (final h in hints) h.id: h};
      expect(byId['role']!.present, isTrue);
      expect(byId['task']!.recommended, isTrue);
      expect(byId['constraints']!.recommended, isTrue);
      expect(byId['task']!.present, isFalse);
    });

    test('gets a higher level as the vault grows', () {
      final small = BrainModel.build(_corpus(1), sectionAliases: _aliases);
      final big = BrainModel.build(_corpus(60), sectionAliases: _aliases);
      expect(small.level.level >= 1, isTrue);
      expect(big.level.level > small.level.level, isTrue);
      expect(big.stats.documents, equals(60));
      expect(big.stats.tokens > small.stats.tokens, isTrue);
      expect(big.level.progress >= 0 && big.level.progress <= 1, isTrue);
    });

    test('seed knowledge is never counted as learned', () {
      final m = BrainModel.build(const []);
      expect(m.stats.tokens, equals(0));
      expect(m.stats.documents, equals(0));
      expect(m.complete('act').isNotEmpty, isTrue);
    });

    test('is deterministic', () {
      final a = BrainModel.build(_corpus(3), now: 1000, sectionAliases: _aliases);
      final b = BrainModel.build(_corpus(3), now: 1000, sectionAliases: _aliases);
      expect(a.complete('hyp').map((h) => h.insert).join(','), equals(b.complete('hyp').map((h) => h.insert).join(',')));
      expect(a.stats.points, equals(b.stats.points));
    });
  });

  group('BrainSimilarity', () {
    test('links documents about the same thing and ignores unrelated ones', () {
      final edges = BrainSimilarity.related(const [
        SimDoc('a', 'python script for data analysis with pandas dataframe'),
        SimDoc('b', 'analysis of data with pandas in a python script'),
        SimDoc('c', 'write a poem about the ocean at night'),
      ]);
      expect(edges.length, equals(1));
      expect({edges.first.a, edges.first.b}.contains('c'), isFalse);
    });

    test('handles empty and single inputs', () {
      expect(BrainSimilarity.related(const []).isEmpty, isTrue);
      expect(BrainSimilarity.related(const [SimDoc('a', 'x')]).isEmpty, isTrue);
    });
  });
}
