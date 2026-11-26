import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_forge/domain/engines/graph_sim.dart';

double _dist(SimNode a, SimNode b) => math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

GraphSim _sim() {
  final ids = [for (var i = 0; i < 12; i++) 'n$i'];
  final links = [const SimLink(0, 1), const SimLink(1, 2), const SimLink(0, 2), const SimLink(3, 4), const SimLink(4, 5), const SimLink(3, 5)];
  return GraphSim.create(ids, List.filled(12, 6.0), links)..warmup(200);
}

void main() {
  group('GraphSim', () {
    test('is deterministic', () {
      final a = _sim(), b = _sim();
      for (var i = 0; i < a.nodes.length; i++) {
        expect((a.nodes[i].x - b.nodes[i].x).abs() < 1e-9, isTrue);
        expect((a.nodes[i].y - b.nodes[i].y).abs() < 1e-9, isTrue);
      }
    });

    test('linked nodes end up closer than unlinked ones', () {
      final s = _sim();
      expect(_dist(s.nodes[0], s.nodes[1]) < _dist(s.nodes[0], s.nodes[8]), isTrue);
    });

    test('settles by itself', () {
      final s = _sim();
      var ticks = 0;
      while (!s.settled && ticks < 5000) {
        s.tick();
        ticks++;
      }
      expect(s.settled, isTrue);
    });

    test('pinned nodes stay put and inactive nodes are frozen', () {
      final s = _sim();
      s.nodes[0].pinned = true;
      s.nodes[11].active = false;
      final x0 = s.nodes[0].x, y0 = s.nodes[0].y, x11 = s.nodes[11].x;
      s.reheat();
      for (var i = 0; i < 50; i++) {
        s.tick();
      }
      expect(s.nodes[0].x == x0 && s.nodes[0].y == y0, isTrue);
      expect(s.nodes[11].x == x11, isTrue);
    });

    test('hit finds the node under a point and ignores empty space', () {
      final s = _sim();
      expect(s.hit(s.nodes[3].x, s.nodes[3].y), equals(3));
      expect(s.hit(99999, 99999), isNull);
    });

    test('bounds cover the active nodes only', () {
      final s = _sim();
      final all = s.bounds()!;
      for (var i = 1; i < s.nodes.length; i++) {
        s.nodes[i].active = false;
      }
      final one = s.bounds()!;
      expect(one.$3 - one.$1 < all.$3 - all.$1, isTrue);
      s.nodes[0].active = false;
      expect(s.bounds(), isNull);
    });

    test('keeps the positions of existing nodes when rebuilt', () {
      final s = _sim();
      final initial = {for (final n in s.nodes) n.id: (n.x, n.y)};
      final again = GraphSim.create([for (final n in s.nodes) n.id], List.filled(12, 6.0), s.links, initial: initial);
      expect(again.nodes[5].x == s.nodes[5].x && again.nodes[5].y == s.nodes[5].y, isTrue);
    });
  });
}
