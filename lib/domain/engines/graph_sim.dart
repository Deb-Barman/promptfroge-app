import 'dart:math' as math;

/// A node in the live graph simulation.
class SimNode {
  final String id;
  double x;
  double y;
  double vx = 0;
  double vy = 0;
  double radius;

  /// Pinned nodes do not move (while a finger drags them, or when the user pins them).
  bool pinned = false;

  /// Inactive nodes take no part in the physics and are not drawn (filters, local graph, time-lapse).
  bool active = true;
  int degree = 0;
  SimNode(this.id, this.x, this.y, this.radius);
}

/// A link between two nodes (indexes into the node list). Soft links are the brain's "related" links.
class SimLink {
  final int a;
  final int b;
  final bool soft;
  const SimLink(this.a, this.b, {this.soft = false});
}

/// The four sliders of Obsidian's graph "Forces" panel (1.0 = default).
class ForceConfig {
  double center;
  double repel;
  double link;
  double distance;
  ForceConfig({this.center = 1, this.repel = 1, this.link = 1, this.distance = 1});

  ForceConfig copy() => ForceConfig(center: center, repel: repel, link: link, distance: distance);
}

/// A small force-directed simulation in the style of d3-force: springs along links, every node repelling every
/// other, a gentle pull to the centre, soft collisions, and a cooling "alpha" so it settles on its own.
/// Deterministic: the same input always ends up in the same place.
class GraphSim {
  final List<SimNode> nodes;
  final List<SimLink> links;
  final ForceConfig config;

  double alpha = 1;
  double alphaTarget = 0;
  static const double alphaMin = 0.0015;
  static const double alphaDecay = 0.0228;
  static const double velocityDecay = 0.6;
  static const double baseDistance = 58;
  static const double repelStrength = 70;
  static const double maxRepelDist = 520;

  GraphSim(this.nodes, this.links, {ForceConfig? config}) : config = config ?? ForceConfig() {
    recountDegrees();
  }

  /// Builds a simulation. Nodes found in [initial] start where they were, the rest on a golden-angle spiral.
  factory GraphSim.create(List<String> ids, List<double> radii, List<SimLink> links, {Map<String, (double, double)>? initial, ForceConfig? config}) {
    final nodes = <SimNode>[];
    const golden = 2.399963229728653;
    for (var i = 0; i < ids.length; i++) {
      final init = initial?[ids[i]];
      if (init != null) {
        nodes.add(SimNode(ids[i], init.$1, init.$2, radii[i]));
      } else {
        final r = 34 * math.sqrt(i + 0.5);
        nodes.add(SimNode(ids[i], math.cos(i * golden) * r, math.sin(i * golden) * r, radii[i]));
      }
    }
    return GraphSim(nodes, links, config: config);
  }

  void recountDegrees() {
    for (final n in nodes) {
      n.degree = 0;
    }
    for (final l in links) {
      nodes[l.a].degree++;
      nodes[l.b].degree++;
    }
  }

  bool get settled => alphaTarget == 0 && alpha <= alphaMin;

  void reheat([double a = 0.6]) {
    if (alpha < a) alpha = a;
  }

  /// Runs [ticks] iterations at full energy (used once so the graph does not "explode" on screen).
  void warmup(int ticks) {
    alpha = 1;
    for (var i = 0; i < ticks; i++) {
      tick(force: true);
    }
  }

  void tick({bool force = false}) {
    if (!force && alpha <= alphaMin && alphaTarget == 0) return;
    alpha += (alphaTarget - alpha) * alphaDecay;
    final n = nodes.length;
    final cfg = config;

    // springs
    for (final l in links) {
      final a = nodes[l.a], b = nodes[l.b];
      if (!a.active || !b.active) continue;
      var dx = (b.x + b.vx) - (a.x + a.vx);
      var dy = (b.y + b.vy) - (a.y + a.vy);
      var len = math.sqrt(dx * dx + dy * dy);
      if (len < 0.01) {
        dx = 0.01;
        len = 0.01;
      }
      final dist = baseDistance * cfg.distance * (l.soft ? 1.7 : 1.0);
      final strength = (l.soft ? 0.18 : 0.9) * cfg.link / math.max(1, math.min(a.degree, b.degree));
      final k = (len - dist) / len * alpha * strength;
      dx *= k;
      dy *= k;
      final total = a.degree + b.degree;
      final bias = total == 0 ? 0.5 : a.degree / total;
      b.vx -= dx * bias;
      b.vy -= dy * bias;
      a.vx += dx * (1 - bias);
      a.vy += dy * (1 - bias);
    }

    // repulsion + soft collisions (every pair; fine for a few hundred nodes)
    final maxD2 = maxRepelDist * maxRepelDist;
    final rep = repelStrength * cfg.repel * alpha;
    for (var i = 0; i < n; i++) {
      final a = nodes[i];
      if (!a.active) continue;
      for (var j = i + 1; j < n; j++) {
        final b = nodes[j];
        if (!b.active) continue;
        var dx = a.x - b.x;
        var dy = a.y - b.y;
        var d2 = dx * dx + dy * dy;
        if (d2 > maxD2) continue;
        if (d2 < 1) {
          dx = (i - j) * 0.01 + 0.01;
          dy = (j - i) * 0.01 - 0.01;
          d2 = dx * dx + dy * dy;
        }
        final w = rep / d2;
        a.vx += dx * w;
        a.vy += dy * w;
        b.vx -= dx * w;
        b.vy -= dy * w;
        final minD = a.radius + b.radius + 6;
        if (d2 < minD * minD) {
          final d = math.sqrt(d2);
          final push = (minD - d) / d * 0.35 * math.max(alpha, 0.05);
          a.vx += dx * push;
          a.vy += dy * push;
          b.vx -= dx * push;
          b.vy -= dy * push;
        }
      }
    }

    // centre pull + integrate
    final pull = 0.05 * cfg.center * alpha;
    for (final a in nodes) {
      if (!a.active) continue;
      if (a.pinned) {
        a.vx = 0;
        a.vy = 0;
        continue;
      }
      a.vx -= a.x * pull;
      a.vy -= a.y * pull;
      a.vx *= (1 - velocityDecay);
      a.vy *= (1 - velocityDecay);
      a.x += a.vx;
      a.y += a.vy;
    }
  }

  /// Bounding box (minX, minY, maxX, maxY) of the active nodes, or null when none are active.
  (double, double, double, double)? bounds() {
    double? minX, minY, maxX, maxY;
    for (final a in nodes) {
      if (!a.active) continue;
      minX = minX == null ? a.x - a.radius : math.min(minX, a.x - a.radius);
      minY = minY == null ? a.y - a.radius : math.min(minY, a.y - a.radius);
      maxX = maxX == null ? a.x + a.radius : math.max(maxX, a.x + a.radius);
      maxY = maxY == null ? a.y + a.radius : math.max(maxY, a.y + a.radius);
    }
    if (minX == null) return null;
    return (minX, minY!, maxX!, maxY!);
  }

  /// The node whose circle (plus [slop]) contains the world point, nearest first; null if none.
  int? hit(double wx, double wy, {double slop = 8}) {
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < nodes.length; i++) {
      final a = nodes[i];
      if (!a.active) continue;
      final dx = a.x - wx, dy = a.y - wy;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d <= a.radius + slop && d < bestD) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }
}
