import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../core/constants.dart';
import '../../core/util.dart';
import '../../domain/engines/brain.dart';
import '../../domain/engines/graph_sim.dart';
import '../../domain/engines/search_engine.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/pf_chrome.dart';

/// The prompt graph, Obsidian style: a live force-directed simulation you can drag, pin, pan and zoom, with
/// highlight-on-select, a forces panel, a local-graph focus mode, a time-lapse of how your vault grew, and the
/// editor brain's "related" links (dashed) so prompts that were never linked by hand still find each other.
/// A plain list (outgoing / incoming / broken links) stays one tab away.
class GraphScreen extends ConsumerStatefulWidget {
  const GraphScreen({super.key});

  @override
  ConsumerState<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends ConsumerState<GraphScreen> {
  String _filter = 'linked'; // linked | orphans | all
  String _view = 'graph'; // graph | list

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final d = ref.watch(vaultProvider).data;
    final active = d.prompts.values.where((x) => !x.archived).toList();
    final g = LinkGraphBuilder.build(active);
    final prompts = {for (final x in active) x.id: x};
    return Scaffold(
      backgroundColor: p.editorBg,
      body: Column(children: [
        Container(
          color: p.bg,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            const Expanded(child: Text('Prompt graph', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4))),
            _Seg(value: _view, options: const [('graph', 'Graph', Icons.hub_outlined), ('list', 'List', Icons.view_list_outlined)], onChanged: (v) => setState(() => _view = v)),
          ]),
        ),
        Expanded(
          child: IndexedStack(index: _view == 'graph' ? 0 : 1, children: [
            _GraphCanvas(graph: g, prompts: prompts, onOpen: (id) => openInEditor(context, ref, promptId: id)),
            _list(context, g),
          ]),
        ),
      ]),
    );
  }

  Widget _list(BuildContext context, LinkGraph g) {
    final p = context.pf;
    final out = <String, List<String>>{};
    final inc = <String, List<String>>{};
    for (final e in g.edges) {
      (out[e.source] ??= []).add(e.target);
      (inc[e.target] ??= []).add(e.source);
    }
    final titles = {for (final n in g.nodes) n.id: n.title};
    var nodes = g.nodes.toList();
    nodes = nodes.where((n) {
      final deg = (out[n.id]?.length ?? 0) + (inc[n.id]?.length ?? 0);
      return _filter == 'all' || (_filter == 'linked' ? deg > 0 : deg == 0);
    }).toList()
      ..sort((a, b) => ((out[b.id]?.length ?? 0) + (inc[b.id]?.length ?? 0)).compareTo((out[a.id]?.length ?? 0) + (inc[a.id]?.length ?? 0)));

    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Text('Type [[Prompt title]] inside a prompt to link to another one. ${g.edges.length} links across ${g.nodes.length} prompts.', style: TextStyle(color: p.textSecondary, fontSize: 13)),
        const SizedBox(height: 10),
        PfTabs<String>(value: _filter, options: const [MapEntry('linked', 'Linked'), MapEntry('orphans', 'Orphans'), MapEntry('all', 'All')], onChanged: (v) => setState(() => _filter = v)),
        if (g.brokenLinks.isNotEmpty) ...[
          SectionTitle('Broken links (${g.brokenLinks.length})'),
          for (final b in g.brokenLinks)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.link_off, color: p.amber, size: 20),
              title: Text('[[${b.targetTitle}]]'),
              subtitle: Text('in ${b.sourceTitle}'),
              onTap: () => openInEditor(context, ref, promptId: b.sourceId),
            ),
        ],
        SectionTitle(_filter == 'orphans' ? 'Prompts with no links' : 'Prompts'),
        if (nodes.isEmpty) const Padding(padding: EdgeInsets.only(top: 24), child: EmptyState(icon: Icons.hub_outlined, title: 'Nothing here', body: 'No prompts match this filter.')),
        for (final n in nodes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PfCard(
              onTap: () => openInEditor(context, ref, promptId: n.id),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                if ((out[n.id] ?? const []).isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text('→ ${out[n.id]!.map((id) => titles[id] ?? id).join(', ')}', style: TextStyle(color: p.blue, fontSize: 12.5))),
                if ((inc[n.id] ?? const []).isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text('← ${inc[n.id]!.map((id) => titles[id] ?? id).join(', ')}', style: TextStyle(color: p.green, fontSize: 12.5))),
              ]),
            ),
          ),
      ]);
  }
}

class _Seg extends StatelessWidget {
  final String value;
  final List<(String, String, IconData)> options;
  final ValueChanged<String> onChanged;
  const _Seg({required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final o in options)
          GestureDetector(
            onTap: () => onChanged(o.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: value == o.$1 ? p.amber.withValues(alpha: 0.16) : Colors.transparent, borderRadius: BorderRadius.circular(9)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(o.$3, size: 16, color: value == o.$1 ? p.amber : p.textTertiary),
                const SizedBox(width: 6),
                Text(o.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: value == o.$1 ? p.amber : p.textSecondary)),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- canvas

List<SimEdge> _relatedIsolate(List<SimDoc> docs) => BrainSimilarity.related(docs);

class _GraphCanvas extends StatefulWidget {
  final LinkGraph graph;
  final Map<String, Prompt> prompts;
  final ValueChanged<String> onOpen;
  const _GraphCanvas({required this.graph, required this.prompts, required this.onOpen});

  @override
  State<_GraphCanvas> createState() => _GraphCanvasState();
}

class _GraphCanvasState extends State<_GraphCanvas> with TickerProviderStateMixin {
  // simulation
  GraphSim? _sim;
  List<String> _ids = const [];
  Map<String, int> _index = const {};
  List<SimEdge> _related = const [];
  String _sig = '';
  String _relSig = '';
  int _relGen = 0;
  int _explicitCount = 0;
  List<int> _created = const [];
  final ForceConfig _cfg = ForceConfig();
  final Set<String> _pinned = {};
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  // view
  double _k = 1;
  Offset _t = Offset.zero;
  Size? _size;
  bool _needsFit = true;
  bool _userMoved = false;
  late final AnimationController _viewCtl;
  double _fromK = 1, _toK = 1;
  Offset _fromT = Offset.zero, _toT = Offset.zero;
  double _startK = 1;
  Offset _startT = Offset.zero;
  Offset _startFocal = Offset.zero;
  int? _dragNode;

  // options
  bool _showLabels = true;
  bool _showOrphans = true;
  bool _showRelated = true;
  bool _colorByCategory = true;
  double _nodeScale = 1;
  double _labelFade = 0.5;
  bool _hintDismissed = false;

  // selection / search / focus
  String? _sel;
  Set<int> _focusSet = const {};
  int _depth = 0;
  final TextEditingController _search = TextEditingController();
  Set<int> _matches = const {};

  // time-lapse
  double? _tl;
  Ticker? _tlTicker;
  int _minC = 0, _maxC = 1;

  final _Labels _labels = _Labels();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _viewCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..addListener(_onViewAnim);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tlTicker?.dispose();
    _viewCtl.dispose();
    _frame.dispose();
    _search.dispose();
    _labels.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ data

  void _ensureData() {
    final g = widget.graph;
    final sig = '${g.nodes.map((n) => n.id).join(',')}|${g.edges.map((e) => '${e.source}>${e.target}').join(',')}';
    if (sig != _sig) {
      _sig = sig;
      _buildSim();
    }
    final rsig = g.nodes.map((n) => '${n.id}:${n.updatedAt}').join(',');
    if (rsig != _relSig) {
      _relSig = rsig;
      unawaited(_computeRelated());
    }
  }

  Future<void> _computeRelated() async {
    final gen = ++_relGen;
    final docs = <SimDoc>[
      for (final n in widget.graph.nodes)
        if (widget.prompts[n.id] != null) SimDoc(n.id, '${widget.prompts[n.id]!.title} ${widget.prompts[n.id]!.tags.join(' ')} ${widget.prompts[n.id]!.body}'),
    ];
    final out = docs.length > 80 ? await compute(_relatedIsolate, docs) : _relatedIsolate(docs);
    if (!mounted || gen != _relGen) return;
    setState(() {
      _related = out;
      _buildSim();
    });
    // the new soft links shift the layout: re-frame it unless the user has already moved the view
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted && !_userMoved) _fit();
    });
  }

  void _buildSim() {
    final g = widget.graph;
    final ids = [for (final n in g.nodes) n.id];
    final index = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    final links = <SimLink>[];
    final seen = <String>{};
    String key(int a, int b) => a < b ? '$a|$b' : '$b|$a';
    for (final e in g.edges) {
      final a = index[e.source], b = index[e.target];
      if (a == null || b == null || a == b) continue;
      if (seen.add(key(a, b))) links.add(SimLink(a, b));
    }
    _explicitCount = links.length;
    if (_showRelated) {
      for (final r in _related) {
        final a = index[r.a], b = index[r.b];
        if (a == null || b == null || a == b) continue;
        if (seen.add(key(a, b))) links.add(SimLink(a, b, soft: true));
      }
    }
    final initial = <String, (double, double)>{for (final n in _sim?.nodes ?? const <SimNode>[]) n.id: (n.x, n.y)};
    final sim = GraphSim.create(ids, List.filled(ids.length, 6.0), links, initial: initial, config: _cfg);
    for (final n in sim.nodes) {
      n.radius = _radiusFor(n.degree);
      n.pinned = _pinned.contains(n.id);
    }
    if (initial.isEmpty) {
      sim.warmup(ids.length <= 120 ? 160 : (ids.length <= 300 ? 80 : 30));
      _needsFit = true;
    } else {
      sim.reheat(0.5);
    }
    _sim = sim;
    _ids = ids;
    _index = index;
    _created = [for (final id in ids) widget.prompts[id]?.createdAt ?? 0];
    if (_created.isNotEmpty) {
      _minC = _created.reduce(math.min);
      _maxC = _created.reduce(math.max);
      if (_maxC <= _minC) _maxC = _minC + 1;
    }
    if (_sel != null && !index.containsKey(_sel)) _sel = null;
    _recomputeSets();
    _applyActive();
    _wake();
  }

  double _radiusFor(int degree) => (4.2 + 2.0 * math.sqrt(degree)).clamp(4.2, 16.0) * _nodeScale;

  void _recomputeSets() {
    final sim = _sim;
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty || sim == null) {
      _matches = const {};
    } else {
      _matches = {
        for (var i = 0; i < _ids.length; i++)
          if ((widget.prompts[_ids[i]]?.title.toLowerCase().contains(q) ?? false) || (widget.prompts[_ids[i]]?.tags.any((t) => t.toLowerCase().contains(q)) ?? false)) i,
      };
    }
    final s = _sel == null ? null : _index[_sel];
    if (s == null || sim == null) {
      _focusSet = const {};
    } else {
      final f = <int>{s};
      for (final l in sim.links) {
        if (l.a == s) f.add(l.b);
        if (l.b == s) f.add(l.a);
      }
      _focusSet = f;
    }
  }

  /// Applies the visibility filters: orphans, local-graph depth, time-lapse.
  void _applyActive({bool placeNew = false}) {
    final sim = _sim;
    if (sim == null) return;
    Set<int>? focus;
    final s = _sel == null ? null : _index[_sel];
    if (s != null && _depth > 0) {
      focus = {s};
      var frontier = <int>{s};
      for (var d = 0; d < _depth; d++) {
        final next = <int>{};
        for (final l in sim.links) {
          if (frontier.contains(l.a) && focus.add(l.b)) next.add(l.b);
          if (frontier.contains(l.b) && focus.add(l.a)) next.add(l.a);
        }
        frontier = next;
      }
    }
    final cutoff = _tl == null ? null : _minC + (_maxC - _minC) * _tl!;
    var changed = false;
    for (var i = 0; i < sim.nodes.length; i++) {
      final n = sim.nodes[i];
      var on = true;
      if (!_showOrphans && n.degree == 0) on = false;
      if (focus != null && !focus.contains(i)) on = false;
      if (cutoff != null && _created[i] > cutoff) on = false;
      if (on != n.active) {
        changed = true;
        if (on && placeNew) _placeNearNeighbour(sim, i);
        n.active = on;
      }
    }
    if (changed) {
      sim.reheat(0.4);
      _wake();
    }
  }

  void _placeNearNeighbour(GraphSim sim, int i) {
    final n = sim.nodes[i];
    for (final l in sim.links) {
      final o = l.a == i ? l.b : (l.b == i ? l.a : -1);
      if (o >= 0 && sim.nodes[o].active) {
        final a = i * 2.399963;
        n.x = sim.nodes[o].x + math.cos(a) * 26;
        n.y = sim.nodes[o].y + math.sin(a) * 26;
        n.vx = 0;
        n.vy = 0;
        return;
      }
    }
    final a = i * 2.399963;
    n.x = math.cos(a) * 30;
    n.y = math.sin(a) * 30;
    n.vx = 0;
    n.vy = 0;
  }

  // ------------------------------------------------------------- animation

  void _wake() {
    if (!mounted) return;
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration _) {
    final sim = _sim;
    if (sim == null) return;
    final steps = sim.nodes.length > 400 ? 1 : 2;
    for (var i = 0; i < steps; i++) {
      sim.tick();
    }
    _frame.value++;
    if (sim.settled && _dragNode == null && _tlTicker == null) _ticker.stop();
  }

  void _animateView(double k, Offset t) {
    _fromK = _k;
    _fromT = _t;
    _toK = k;
    _toT = t;
    _viewCtl.forward(from: 0);
  }

  void _onViewAnim() {
    final v = Curves.easeOutCubic.transform(_viewCtl.value);
    _k = _fromK + (_toK - _fromK) * v;
    _t = Offset.lerp(_fromT, _toT, v)!;
    _frame.value++;
  }

  void _fit({bool animate = true}) {
    final sim = _sim, size = _size;
    if (sim == null || size == null) return;
    final b = sim.bounds();
    if (b == null) return;
    final bw = math.max(b.$3 - b.$1, 60.0), bh = math.max(b.$4 - b.$2, 60.0);
    const topPad = 128.0;
    final bottomPad = _sel != null ? 196.0 : 96.0;
    final availW = math.max(size.width - 48, 80.0), availH = math.max(size.height - topPad - bottomPad, 80.0);
    final k = math.min(availW / bw, availH / bh).clamp(0.2, 1.8).toDouble();
    final cx = (b.$1 + b.$3) / 2, cy = (b.$2 + b.$4) / 2;
    final t = Offset(size.width / 2 - cx * k, topPad + availH / 2 - cy * k);
    if (animate) {
      _animateView(k, t);
    } else {
      _k = k;
      _t = t;
      _frame.value++;
    }
  }

  void _zoomAt(Offset focal, double factor) {
    _userMoved = true;
    final k = (_k * factor).clamp(0.12, 6.0).toDouble();
    final world = (focal - _t) / _k;
    _k = k;
    _t = focal - world * k;
    _frame.value++;
  }

  // -------------------------------------------------------------- gestures

  Offset _toWorld(Offset s) => (s - _t) / _k;

  void _onScaleStart(ScaleStartDetails d) {
    _viewCtl.stop();
    _startK = _k;
    _startT = _t;
    _startFocal = d.localFocalPoint;
    _dragNode = null;
    final sim = _sim;
    if (sim != null && d.pointerCount == 1) {
      final w = _toWorld(d.localFocalPoint);
      final hit = sim.hit(w.dx, w.dy, slop: 12 / _k);
      if (hit != null) {
        _dragNode = hit;
        sim.nodes[hit].pinned = true;
        sim.alphaTarget = 0.25;
        sim.reheat(0.4);
        _wake();
        _select(sim.nodes[hit].id);
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    _userMoved = true;
    final sim = _sim;
    final dn = _dragNode;
    if (dn != null && sim != null) {
      final w = _toWorld(d.localFocalPoint);
      final n = sim.nodes[dn];
      n.x = w.dx;
      n.y = w.dy;
      n.vx = 0;
      n.vy = 0;
      _frame.value++;
      return;
    }
    final k = (_startK * d.scale).clamp(0.12, 6.0).toDouble();
    final worldAtStart = (_startFocal - _startT) / _startK;
    _k = k;
    _t = d.localFocalPoint - worldAtStart * k;
    _frame.value++;
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final sim = _sim;
    final dn = _dragNode;
    if (dn != null && sim != null) {
      sim.nodes[dn].pinned = _pinned.contains(sim.nodes[dn].id);
      sim.alphaTarget = 0;
      _wake();
    }
    _dragNode = null;
  }

  void _onTapUp(TapUpDetails d) {
    final sim = _sim;
    if (sim == null) return;
    final w = _toWorld(d.localPosition);
    final hit = sim.hit(w.dx, w.dy, slop: 14 / _k);
    _select(hit == null ? null : (sim.nodes[hit].id == _sel ? null : sim.nodes[hit].id));
  }

  void _select(String? id) {
    if (id == _sel) return;
    setState(() {
      _sel = id;
      if (id == null) _depth = 0;
      _recomputeSets();
      _applyActive();
    });
    _frame.value++;
  }

  // --------------------------------------------------------------- actions

  void _toggleTimelapse() {
    if (_tlTicker != null) {
      _tlTicker!.dispose();
      _tlTicker = null;
      setState(() => _tl = null);
      _applyActive();
      return;
    }
    setState(() {
      _tl = 0;
      _sel = null;
      _depth = 0;
      _recomputeSets();
    });
    _applyActive();
    final total = math.max(4000, math.min(14000, _ids.length * 450));
    _tlTicker = createTicker((e) {
      final t = e.inMilliseconds / total;
      if (t >= 1) {
        _tlTicker?.dispose();
        _tlTicker = null;
        if (mounted) {
          setState(() => _tl = null);
          _applyActive();
        }
        return;
      }
      _tl = t;
      _applyActive(placeNew: true);
      if (mounted) setState(() {});
    })
      ..start();
    _wake();
  }

  void _openForces() {
    showPfSheet<void>(
      context,
      title: 'Graph forces',
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        Widget slider(String label, double v, double min, double max, ValueChanged<double> on) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                SizedBox(width: 118, child: Text(label, style: TextStyle(fontSize: 13.5, color: context.pf.textSecondary))),
                Expanded(
                  child: Slider(
                    value: v.clamp(min, max).toDouble(),
                    min: min,
                    max: max,
                    onChanged: (x) {
                      setSheet(() {});
                      on(x);
                    },
                  ),
                ),
              ]),
            );
        void kick() {
          _sim?.reheat(0.7);
          _wake();
          setState(() {});
        }

        return ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 20), children: [
          slider('Center force', _cfg.center, 0, 2.5, (x) {
            _cfg.center = x;
            kick();
          }),
          slider('Repel force', _cfg.repel, 0, 3, (x) {
            _cfg.repel = x;
            kick();
          }),
          slider('Link force', _cfg.link, 0, 2.5, (x) {
            _cfg.link = x;
            kick();
          }),
          slider('Link distance', _cfg.distance, 0.4, 2.8, (x) {
            _cfg.distance = x;
            kick();
          }),
          slider('Node size', _nodeScale, 0.6, 2.2, (x) {
            _nodeScale = x;
            for (final n in _sim?.nodes ?? const <SimNode>[]) {
              n.radius = _radiusFor(n.degree);
            }
            kick();
          }),
          slider('Label fade', _labelFade, 0, 1.2, (x) {
            _labelFade = x;
            _frame.value++;
            setState(() {});
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset forces'),
              onPressed: () {
                _cfg
                  ..center = 1
                  ..repel = 1
                  ..link = 1
                  ..distance = 1;
                _nodeScale = 1;
                _labelFade = 0.5;
                for (final n in _sim?.nodes ?? const <SimNode>[]) {
                  n.radius = _radiusFor(n.degree);
                }
                setSheet(() {});
                kick();
              },
            ),
          ),
        ]);
      }),
    );
  }

  // ----------------------------------------------------------------- build

  Color _nodeColor(PfPalette p, int i) {
    final sim = _sim!;
    final id = _ids[i];
    if (_colorByCategory) {
      final pr = widget.prompts[id];
      return pfColor(categoryById(pr?.category ?? 'custom').color);
    }
    return sim.nodes[i].degree > 0 ? p.amber : p.textTertiary;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final g = widget.graph;
    if (g.nodes.isEmpty) {
      return const EmptyState(icon: Icons.hub_outlined, title: 'No prompts yet', body: 'Save a few prompts, then link them with [[Title]] to see the graph.');
    }
    _ensureData();
    final sim = _sim!;
    return LayoutBuilder(builder: (context, c) {
      _size = Size(c.maxWidth, c.maxHeight);
      if (_needsFit && c.maxWidth > 0 && c.maxHeight > 0) {
        _needsFit = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fit(animate: false);
        });
      }
      final colors = [for (var i = 0; i < _ids.length; i++) _nodeColor(p, i)];
      final titles = [for (final id in _ids) widget.prompts[id]?.title.isEmpty ?? true ? 'Untitled prompt' : widget.prompts[id]!.title];
      final softCount = sim.links.where((l) => l.soft).length;
      final orphans = _ids.length - {for (final l in sim.links.where((l) => !l.soft)) ...[l.a, l.b]}.length;
      return Stack(children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) _zoomAt(e.localPosition, math.exp(-e.scrollDelta.dy / 320));
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              onTapUp: _onTapUp,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _GraphPainter(
                    repaint: _frame,
                    sim: sim,
                    colors: colors,
                    titles: titles,
                    k: () => _k,
                    t: () => _t,
                    selected: _sel == null ? null : _index[_sel],
                    focusSet: _focusSet,
                    matches: _matches,
                    searching: _search.text.trim().isNotEmpty,
                    showLabels: _showLabels,
                    labelFade: _labelFade,
                    labels: _labels,
                    palette: p,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
        Positioned(top: 8, left: 10, right: 10, child: _topBar(p, softCount)),
        Positioned(right: 10, bottom: _sel != null ? 188 : 66, child: _zoomButtons(p)),
        Positioned(left: 10, right: 10, bottom: 10, child: _bottom(p, orphans, softCount)),
      ]);
    });
  }

  Widget _glass({required Widget child, double radius = 14, EdgeInsets? padding}) {
    final p = context.pf;
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: p.surface.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(radius), border: Border.all(color: p.border), boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 14, offset: Offset(0, 4))]),
      child: child,
    );
  }

  Widget _topBar(PfPalette p, int softCount) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          child: _glass(
            child: TextField(
              controller: _search,
              onChanged: (_) {
                setState(_recomputeSets);
                _frame.value++;
              },
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search prompts or tags',
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                prefixIcon: Icon(Icons.search, size: 20, color: p.textTertiary),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(_recomputeSets);
                          _frame.value++;
                        },
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _roundBtn(Icons.tune, 'Forces', _openForces),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 34,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          _pill('Labels', Icons.label_outline, _showLabels, () => setState(() => _showLabels = !_showLabels)),
          _pill('Orphans', Icons.radio_button_unchecked, _showOrphans, () {
            setState(() => _showOrphans = !_showOrphans);
            _applyActive();
          }),
          _pill('Related', Icons.auto_awesome, _showRelated, () {
            setState(() {
              _showRelated = !_showRelated;
              _buildSim();
            });
          }, color: p.violet),
          _pill(_colorByCategory ? 'Color: category' : 'Color: links', Icons.palette_outlined, true, () => setState(() => _colorByCategory = !_colorByCategory)),
          _pill(_tlTicker != null ? 'Stop' : 'Time-lapse', _tlTicker != null ? Icons.stop : Icons.play_arrow_rounded, _tlTicker != null, _toggleTimelapse, color: p.green),
          _pill('Fit', Icons.center_focus_strong_outlined, false, () => _fit()),
        ]),
      ),
    ]);
  }

  Widget _roundBtn(IconData icon, String tip, VoidCallback onTap) {
    final p = context.pf;
    return Tooltip(
      message: tip,
      child: _glass(
        radius: 14,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 21, color: p.textSecondary)),
        ),
      ),
    );
  }

  Widget _pill(String label, IconData icon, bool on, VoidCallback onTap, {Color? color}) {
    final p = context.pf;
    final c = color ?? p.amber;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on ? c.withValues(alpha: 0.18) : p.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: on ? c.withValues(alpha: 0.7) : p.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: on ? c : p.textTertiary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? c : p.textSecondary)),
          ]),
        ),
      ),
    );
  }

  Widget _zoomButtons(PfPalette p) {
    final size = _size ?? const Size(300, 500);
    final mid = Offset(size.width / 2, size.height / 2);
    Widget b(IconData i, double f) => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _zoomAt(mid, f),
          child: SizedBox(width: 42, height: 42, child: Icon(i, size: 22, color: p.textSecondary)),
        );
    return _glass(radius: 14, child: Column(mainAxisSize: MainAxisSize.min, children: [b(Icons.add, 1.35), Container(height: 1, width: 24, color: p.border), b(Icons.remove, 1 / 1.35)]));
  }

  Widget _bottom(PfPalette p, int orphans, int softCount) {
    final g = widget.graph;
    final stats = '${g.nodes.length} note${g.nodes.length == 1 ? '' : 's'} · $_explicitCount link${_explicitCount == 1 ? '' : 's'} · $orphans orphan${orphans == 1 ? '' : 's'}${_showRelated && softCount > 0 ? ' · $softCount related' : ''}';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_sel != null) _selectionCard(p) else if (_explicitCount == 0 && !_hintDismissed) _hint(p),
      const SizedBox(height: 8),
      if (_tl != null)
        _glass(
          radius: 12,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            Icon(Icons.history_toggle_off, size: 16, color: p.green),
            const SizedBox(width: 8),
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: _tl, minHeight: 5, color: p.green, backgroundColor: p.surface3))),
            const SizedBox(width: 10),
            Text(Utils.formatDate((_minC + (_maxC - _minC) * _tl!).round()), style: TextStyle(fontSize: 11.5, color: p.textSecondary)),
          ]),
        )
      else
        Align(
          alignment: Alignment.centerLeft,
          child: _glass(radius: 12, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text(stats, style: TextStyle(fontSize: 12, color: p.textSecondary, fontWeight: FontWeight.w600))),
        ),
    ]);
  }

  Widget _hint(PfPalette p) {
    return _glass(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(children: [
        Icon(Icons.lightbulb_outline, size: 18, color: p.amber),
        const SizedBox(width: 10),
        Expanded(child: Text('No [[links]] yet. Type @ in the editor to link prompts. Dashed violet lines are prompts the brain thinks are related.', style: TextStyle(fontSize: 12, height: 1.4, color: p.textSecondary))),
        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _hintDismissed = true)),
      ]),
    );
  }

  Widget _selectionCard(PfPalette p) {
    final sim = _sim!;
    final id = _sel!;
    final i = _index[id]!;
    final pr = widget.prompts[id];
    final cat = categoryById(pr?.category ?? 'custom');
    var links = 0, rel = 0;
    for (final l in sim.links) {
      if (l.a == i || l.b == i) {
        if (l.soft) {
          rel++;
        } else {
          links++;
        }
      }
    }
    final pinned = _pinned.contains(id);
    final title = (pr?.title.isEmpty ?? true) ? 'Untitled prompt' : pr!.title;
    return _glass(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: pfColor(cat.color), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 18), onPressed: () => _select(null)),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: Text('${cat.label} · $links link${links == 1 ? '' : 's'}${rel > 0 ? ' · $rel related' : ''}${(pr?.tags.isNotEmpty ?? false) ? ' · ${pr!.tags.take(3).map((t) => '#$t').join(' ')}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.textSecondary)),
        ),
        Row(children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14)),
            icon: const Icon(Icons.edit_note, size: 18),
            label: const Text('Open'),
            onPressed: () => widget.onOpen(id),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 12)),
            icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 17),
            label: Text(pinned ? 'Unpin' : 'Pin'),
            onPressed: () {
              setState(() {
                if (pinned) {
                  _pinned.remove(id);
                } else {
                  _pinned.add(id);
                }
                sim.nodes[i].pinned = !pinned;
              });
              _wake();
            },
          ),
          const Spacer(),
          PopupMenuButton<int>(
            tooltip: 'Local graph',
            onSelected: (v) {
              setState(() => _depth = v);
              _applyActive();
              if (v > 0) {
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) _fit();
                });
              } else {
                _fit();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0, child: Text('Whole graph')),
              PopupMenuItem(value: 1, child: Text('Local graph · 1 step')),
              PopupMenuItem(value: 2, child: Text('Local graph · 2 steps')),
              PopupMenuItem(value: 3, child: Text('Local graph · 3 steps')),
            ],
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: _depth > 0 ? p.blue.withValues(alpha: 0.16) : Colors.transparent, borderRadius: BorderRadius.circular(20), border: Border.all(color: _depth > 0 ? p.blue : p.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.filter_center_focus, size: 16, color: _depth > 0 ? p.blue : p.textSecondary),
                const SizedBox(width: 6),
                Text(_depth > 0 ? 'Local · $_depth' : 'Focus', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _depth > 0 ? p.blue : p.textSecondary)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
}

// --------------------------------------------------------------- painter

/// Cache of laid-out label text, so labels are not re-measured on every frame.
class _Labels {
  final Map<String, TextPainter> _m = {};

  TextPainter get(String key, String text, TextStyle style) {
    var tp = _m[key];
    if (tp == null) {
      if (_m.length > 500) {
        for (final t in _m.values) {
          t.dispose();
        }
        _m.clear();
      }
      tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…')..layout(maxWidth: 160);
      _m[key] = tp;
    }
    return tp;
  }

  void dispose() {
    for (final t in _m.values) {
      t.dispose();
    }
    _m.clear();
  }
}

class _GraphPainter extends CustomPainter {
  final GraphSim sim;
  final List<Color> colors;
  final List<String> titles;
  final double Function() k;
  final Offset Function() t;
  final int? selected;
  final Set<int> focusSet;
  final Set<int> matches;
  final bool searching;
  final bool showLabels;
  final double labelFade;
  final _Labels labels;
  final PfPalette palette;

  _GraphPainter({
    required Listenable repaint,
    required this.sim,
    required this.colors,
    required this.titles,
    required this.k,
    required this.t,
    required this.selected,
    required this.focusSet,
    required this.matches,
    required this.searching,
    required this.showLabels,
    required this.labelFade,
    required this.labels,
    required this.palette,
  }) : super(repaint: repaint);

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;

  void _dashed(Canvas c, Offset a, Offset b, Paint paint, double dash, double gap) {
    final d = b - a;
    final len = d.distance;
    if (len < 1e-3) return;
    if (len < dash * 2) {
      c.drawLine(a, b, paint);
      return;
    }
    final dir = d / len;
    var pos = 0.0;
    while (pos < len) {
      final end = math.min(pos + dash, len);
      c.drawLine(a + dir * pos, a + dir * end, paint);
      pos += dash + gap;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final kk = k();
    final tt = t();
    final rect = Offset.zero & size;

    // background: soft vignette + dot grid
    canvas.drawRect(rect, Paint()..shader = RadialGradient(center: Alignment.center, radius: 0.95, colors: [Color.lerp(p.editorBg, p.surface2, 0.7)!, p.editorBg]).createShader(rect));
    final spacing = 30 * kk;
    if (spacing >= 14) {
      final pts = <Offset>[];
      for (var x = tt.dx % spacing; x < size.width; x += spacing) {
        for (var y = tt.dy % spacing; y < size.height; y += spacing) {
          pts.add(Offset(x, y));
        }
      }
      canvas.drawPoints(PointMode.points, pts, Paint()
        ..color = p.border.withValues(alpha: 0.5)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round);
    }

    final nodes = sim.nodes;
    final focusing = selected != null;
    bool dimmed(int i) => (focusing && !focusSet.contains(i)) || (searching && !matches.contains(i));

    canvas.save();
    canvas.translate(tt.dx, tt.dy);
    canvas.scale(kk);

    // links
    final base = Path();
    final hotPath = Path();
    final softPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1 / kk
      ..color = p.violet.withValues(alpha: focusing ? 0.18 : 0.5);
    final hotSoft = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 / kk
      ..color = p.violet.withValues(alpha: 0.95);
    for (final l in sim.links) {
      final a = nodes[l.a], b = nodes[l.b];
      if (!a.active || !b.active) continue;
      final hot = focusing && (l.a == selected || l.b == selected);
      final pa = Offset(a.x, a.y), pb = Offset(b.x, b.y);
      if (l.soft) {
        _dashed(canvas, pa, pb, hot ? hotSoft : softPaint, 5 / kk, 5 / kk);
      } else if (hot) {
        hotPath
          ..moveTo(pa.dx, pa.dy)
          ..lineTo(pb.dx, pb.dy);
      } else {
        base
          ..moveTo(pa.dx, pa.dy)
          ..lineTo(pb.dx, pb.dy);
      }
    }
    canvas.drawPath(
        base,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 / kk
          ..color = p.textTertiary.withValues(alpha: focusing || searching ? 0.22 : 0.55));
    canvas.drawPath(
        hotPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 / kk
          ..strokeCap = StrokeCap.round
          ..color = p.amber);

    // nodes
    var glows = 0;
    final fill = Paint();
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      if (!n.active) continue;
      final dim = dimmed(i);
      final isSel = i == selected;
      final isMatch = matches.contains(i);
      final c = colors[i];
      final o = Offset(n.x, n.y);
      if (!dim && glows < 70 && (isSel || isMatch || n.degree >= 3)) {
        glows++;
        canvas.drawCircle(
            o,
            n.radius * 1.7,
            Paint()
              ..color = c.withValues(alpha: isSel ? 0.6 : 0.34)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, n.radius * 0.9));
      }
      fill.color = dim ? c.withValues(alpha: 0.22) : c;
      canvas.drawCircle(o, n.radius, fill);
      if (isSel || isMatch) {
        canvas.drawCircle(
            o,
            n.radius + 3 / kk,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2 / kk
              ..color = isSel ? Colors.white : p.amber);
      } else if (n.pinned && !dim) {
        canvas.drawCircle(
            o,
            n.radius + 2.5 / kk,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2 / kk
              ..color = Colors.white.withValues(alpha: 0.7));
      }
    }
    canvas.restore();

    // labels (screen space, so the text stays crisp at any zoom)
    var drawn = 0;
    for (var i = 0; i < nodes.length && drawn < 140; i++) {
      final n = nodes[i];
      if (!n.active) continue;
      final sx = n.x * kk + tt.dx, sy = n.y * kk + tt.dy;
      if (sx < -80 || sy < -40 || sx > size.width + 80 || sy > size.height + 40) continue;
      final dim = dimmed(i);
      final emphasised = i == selected || (focusing && focusSet.contains(i)) || matches.contains(i);
      double alpha;
      if (emphasised) {
        alpha = 1;
      } else if (!showLabels) {
        continue;
      } else {
        final threshold = labelFade * (1.25 - math.min(1.0, n.degree / 6) * 0.75);
        alpha = ((kk - threshold) * 3).clamp(0.0, 1.0).toDouble();
        if (dim) alpha *= 0.35;
      }
      if (alpha < 0.12) continue;
      final level = (alpha * 4).round().clamp(1, 4);
      final bold = i == selected;
      final color = (bold ? p.text : p.textSecondary).withValues(alpha: level / 4);
      final tp = labels.get('$i|${titles[i]}|$level|$bold|${p.brightness.index}', titles[i], TextStyle(fontSize: bold ? 12.5 : 11, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color));
      tp.paint(canvas, Offset(sx - tp.width / 2, sy + n.radius * kk + 4));
      drawn++;
    }
  }
}
