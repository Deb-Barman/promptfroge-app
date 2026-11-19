// Graph layout and flexible date parsing must match the ORIGINAL JavaScript (goldens).
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_forge/core/date_parse.dart';
import 'package:prompt_forge/domain/engines/graph_layout.dart';

import '../support/golden.dart';

void main() {
  final g = Goldens.load();

  group('parseFlexibleDate matches the original', () {
    final inputs = (g['dates']['inputs'] as List).cast<String>();
    final parsed = g['dates']['parsed'] as List;
    for (var i = 0; i < inputs.length; i++) {
      test('"${inputs[i]}"', () {
        final d = parseFlexibleDate(inputs[i]);
        final want = parsed[i];
        if (want == null) {
          expect(d, isNull);
        } else if (want == 'relative') {
          expect(d, isNotNull);
          expect(d!.hour, 0);
        } else {
          expect(d, isNotNull);
          expect([d!.year, d.month, d.day], (want as List).cast<int>());
        }
      });
    }
    test('today / yesterday are local midnights, a day apart', () {
      final now = DateTime(2026, 3, 1, 15, 30);
      expect(parseFlexibleDate('today', now: now), DateTime(2026, 3, 1));
      expect(parseFlexibleDate('yesterday', now: now), DateTime(2026, 2, 28));
    });
    test('picker text round-trips', () {
      final d = DateTime(2026, 9, 3);
      expect(parseFlexibleDate(dateToFlexibleText(d)), d);
    });
  });

  group('GraphLayout matches the original force layout', () {
    final cases = (g['graph'] as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < cases.length; i++) {
      test('case #$i (${(cases[i]['nodes'] as List).length} nodes)', () {
        final c = cases[i];
        final ids = (c['nodes'] as List).cast<String>();
        final edges = [for (final e in (c['edges'] as List)) ((e as List)[0] as String, e[1] as String)];
        final pos = GraphLayout.layout(ids, edges, (c['w'] as num).toDouble(), (c['h'] as num).toDouble());
        final want = c['pos'] as Map<String, dynamic>;
        expect(pos.length, want.length);
        for (final id in ids) {
          final w = want[id] as List;
          expect(pos[id]!.x, closeTo((w[0] as num).toDouble(), 1e-6), reason: '$id.x');
          expect(pos[id]!.y, closeTo((w[1] as num).toDouble(), 1e-6), reason: '$id.y');
        }
      });
    }
  });
}
