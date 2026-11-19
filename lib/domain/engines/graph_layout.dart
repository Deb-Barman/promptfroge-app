import 'dart:math' as math;

class GraphPoint {
  double x;
  double y;
  GraphPoint(this.x, this.y);
}

/// Force-directed layout for the link graph. A direct port of the original `_layoutLinkGraph`: nodes start on a
/// circle, repel each other, edges act as springs, and everything is gently pulled to the centre. Deterministic,
/// so the same vault always lays out the same way (and the result is verified against the original JavaScript).
class GraphLayout {
  GraphLayout._();

  static const double repulsion = 6000;
  static const double spring = 0.02;
  static const double idealDist = 110;
  static const double damping = 0.85;
  static const int iterations = 180;

  static Map<String, GraphPoint> layout(List<String> nodeIds, List<(String, String)> edges, double width, double height) {
    final positions = <String, GraphPoint>{};
    final n = nodeIds.length;
    if (n == 0) return positions;
    final seedR = math.min(width, height) * 0.32;
    for (var i = 0; i < n; i++) {
      final angle = (i / n) * math.pi * 2;
      positions[nodeIds[i]] = GraphPoint(width / 2 + math.cos(angle) * seedR, height / 2 + math.sin(angle) * seedR);
    }
    final vx = <String, double>{for (final id in nodeIds) id: 0};
    final vy = <String, double>{for (final id in nodeIds) id: 0};
    for (var iter = 0; iter < iterations; iter++) {
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          final a = positions[nodeIds[i]]!, b = positions[nodeIds[j]]!;
          final dx = a.x - b.x, dy = a.y - b.y;
          var dist = math.sqrt(dx * dx + dy * dy);
          if (dist == 0) dist = 0.01;
          final force = repulsion / (dist * dist);
          final fx = (dx / dist) * force, fy = (dy / dist) * force;
          vx[nodeIds[i]] = vx[nodeIds[i]]! + fx;
          vy[nodeIds[i]] = vy[nodeIds[i]]! + fy;
          vx[nodeIds[j]] = vx[nodeIds[j]]! - fx;
          vy[nodeIds[j]] = vy[nodeIds[j]]! - fy;
        }
      }
      for (final (source, target) in edges) {
        final a = positions[source], b = positions[target];
        if (a == null || b == null) continue;
        final dx = b.x - a.x, dy = b.y - a.y;
        var dist = math.sqrt(dx * dx + dy * dy);
        if (dist == 0) dist = 0.01;
        final force = (dist - idealDist) * spring;
        final fx = (dx / dist) * force, fy = (dy / dist) * force;
        vx[source] = vx[source]! + fx;
        vy[source] = vy[source]! + fy;
        vx[target] = vx[target]! - fx;
        vy[target] = vy[target]! - fy;
      }
      for (final id in nodeIds) {
        vx[id] = vx[id]! * damping;
        vy[id] = vy[id]! * damping;
        final p = positions[id]!;
        p.x += vx[id]! * 0.02;
        p.y += vy[id]! * 0.02;
        p.x += (width / 2 - p.x) * 0.001;
        p.y += (height / 2 - p.y) * 0.001;
        p.x = math.max(24, math.min(width - 24, p.x));
        p.y = math.max(24, math.min(height - 24, p.y));
      }
    }
    return positions;
  }
}
