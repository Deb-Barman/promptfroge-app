import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../domain/engines/graph_layout.dart';
import '../../domain/engines/search_engine.dart';
import '../../state/vault_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Obsidian-style link overview of [[wiki link]] relationships: a pan/zoom force-directed graph (the original's
/// layout, ported exactly) plus a plain list (outgoing / incoming) that stays readable with a screen reader.
class GraphScreen extends ConsumerStatefulWidget {
  const GraphScreen({super.key});

  @override
  ConsumerState<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends ConsumerState<GraphScreen> {
  String _filter = 'linked'; // linked | orphans | all

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(vaultProvider).data;
    final g = LinkGraphBuilder.build(d.prompts.values.where((x) => !x.archived));
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Prompt graph'), bottom: const TabBar(tabs: [Tab(text: 'Graph'), Tab(text: 'List')])),
        body: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
          _GraphCanvasTab(graph: g, onOpen: (id) => openInEditor(context, ref, promptId: id)),
          _list(context, g),
        ]),
      ),
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
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'linked', label: Text('Linked')), ButtonSegment(value: 'orphans', label: Text('Orphans')), ButtonSegment(value: 'all', label: Text('All'))],
          selected: {_filter},
          onSelectionChanged: (s) => setState(() => _filter = s.first),
        ),
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


// ---------------------------------------------------------------- canvas

List<List<double>> _layoutIsolate(Map<String, dynamic> a) {
  final ids = (a['ids'] as List).cast<String>();
  final e = (a['edges'] as List).cast<List<dynamic>>();
  final pos = GraphLayout.layout(ids, [for (final x in e) (x[0] as String, x[1] as String)], a['w'] as double, a['h'] as double);
  return [for (final id in ids) [pos[id]!.x, pos[id]!.y]];
}

class _GraphCanvasTab extends StatefulWidget {
  final LinkGraph graph;
  final ValueChanged<String> onOpen;
  const _GraphCanvasTab({required this.graph, required this.onOpen});

  @override
  State<_GraphCanvasTab> createState() => _GraphCanvasTabState();
}

class _GraphCanvasTabState extends State<_GraphCanvasTab> {
  static const double _height = 560;
  Map<String, Offset> _pos = const {};
  String _sig = '';
  double _w = 0;
  String? _selected;
  int _gen = 0;

  String _signature(double w) => '${widget.graph.nodes.map((n) => n.id).join(',')}|${widget.graph.edges.map((e) => '${e.source}>${e.target}').join(',')}|${w.round()}';

  Future<void> _relayout(double w, {bool force = false}) async {
    final sig = _signature(w);
    if (!force && sig == _sig) return;
    _sig = sig;
    final gen = ++_gen;
    final ids = widget.graph.nodes.map((n) => n.id).toList();
    final args = <String, dynamic>{
      'ids': ids,
      'edges': [for (final e in widget.graph.edges) [e.source, e.target]],
      'w': w,
      'h': _height,
    };
    final out = ids.length > 120 ? await compute(_layoutIsolate, args) : _layoutIsolate(args);
    if (!mounted || gen != _gen) return;
    setState(() => _pos = {for (var i = 0; i < ids.length; i++) ids[i]: Offset(out[i][0], out[i][1])});
  }

  void _tap(Offset local) {
    String? best;
    var bestD = 22.0;
    _pos.forEach((id, o) {
      final d = (o - local).distance;
      if (d < bestD) {
        bestD = d;
        best = id;
      }
    });
    setState(() => _selected = best == _selected ? null : best);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final g = widget.graph;
    if (g.nodes.isEmpty) {
      return const EmptyState(icon: Icons.hub_outlined, title: 'No prompts yet', body: 'Save a few prompts, then link them with [[Title]] to see the graph.');
    }
    final linked = <String>{for (final e in g.edges) ...[e.source, e.target]};
    final isolated = g.nodes.length - linked.length;
    final titles = {for (final n in g.nodes) n.id: n.title};
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth < 320 ? 320.0 : c.maxWidth;
      if (w != _w || _pos.isEmpty) {
        _w = w;
        WidgetsBinding.instance.addPostFrameCallback((_) => _relayout(w));
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _relayout(w));
      }
      final sel = _selected;
      final neighbours = <String>{};
      if (sel != null) {
        for (final e in g.edges) {
          if (e.source == sel) neighbours.add(e.target);
          if (e.target == sel) neighbours.add(e.source);
        }
      }
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text('${g.nodes.length} prompt${g.nodes.length == 1 ? '' : 's'} · ${g.edges.length} link${g.edges.length == 1 ? '' : 's'}${isolated > 0 ? ' · $isolated isolated' : ''}', style: TextStyle(color: p.textSecondary, fontSize: 13)),
            ),
            TextButton.icon(icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh layout'), onPressed: () {
              setState(() => _selected = null);
              _relayout(w, force: true);
            }),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Align(alignment: Alignment.centerLeft, child: Text('Type @ in the editor to link a prompt. Amber nodes are linked, grey ones are not. Pinch to zoom, drag to pan, tap a node.', style: TextStyle(color: p.textTertiary, fontSize: 11.5))),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: p.editorBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
            clipBehavior: Clip.antiAlias,
            child: _pos.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : InteractiveViewer(
                    minScale: 0.4,
                    maxScale: 5,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(240),
                    child: GestureDetector(
                      onTapUp: (d) => _tap(d.localPosition),
                      child: CustomPaint(
                        size: Size(w, _height),
                        painter: _GraphPainter(
                          pos: _pos,
                          edges: [for (final e in g.edges) (e.source, e.target)],
                          titles: titles,
                          linked: linked,
                          selected: sel,
                          neighbours: neighbours,
                          amber: p.amber,
                          blue: p.blue,
                          edgeColor: p.border,
                          dim: p.textTertiary,
                          label: p.textSecondary,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        if (sel != null && titles[sel] != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titles[sel]!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(neighbours.isEmpty ? 'No links' : '${neighbours.length} linked: ${neighbours.map((id) => titles[id] ?? id).take(3).join(', ')}${neighbours.length > 3 ? '…' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 12)),
                ]),
              ),
              FilledButton(onPressed: () => widget.onOpen(sel), child: const Text('Open')),
            ]),
          ),
        if (g.brokenLinks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text('${g.brokenLinks.length} broken link${g.brokenLinks.length == 1 ? '' : 's'} — see the List tab', style: TextStyle(color: p.amber, fontSize: 12))),
          )
        else
          const SizedBox(height: 8),
      ]);
    });
  }
}

class _GraphPainter extends CustomPainter {
  final Map<String, Offset> pos;
  final List<(String, String)> edges;
  final Map<String, String> titles;
  final Set<String> linked;
  final String? selected;
  final Set<String> neighbours;
  final Color amber, blue, edgeColor, dim, label;

  _GraphPainter({
    required this.pos,
    required this.edges,
    required this.titles,
    required this.linked,
    required this.selected,
    required this.neighbours,
    required this.amber,
    required this.blue,
    required this.edgeColor,
    required this.dim,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final (a, b) in edges) {
      final pa = pos[a], pb = pos[b];
      if (pa == null || pb == null) continue;
      final hot = selected != null && (a == selected || b == selected);
      line.color = hot ? amber : (selected != null ? edgeColor.withAlpha(90) : edgeColor);
      line.strokeWidth = hot ? 2 : 1.2;
      canvas.drawLine(pa, pb, line);
    }
    final fill = Paint();
    for (final entry in pos.entries) {
      final id = entry.key;
      final o = entry.value;
      final isLinked = linked.contains(id);
      final r = isLinked ? 8.0 : 5.0;
      final isSel = id == selected;
      final faded = selected != null && !isSel && !neighbours.contains(id);
      fill.color = isSel ? blue : (isLinked ? amber : dim);
      if (faded) fill.color = fill.color.withAlpha(80);
      canvas.drawCircle(o, isSel ? r + 3 : r, fill);
      final t = titles[id] ?? '';
      final text = t.length > 22 ? '${t.substring(0, 22)}…' : t;
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(fontSize: 10, color: faded ? label.withAlpha(90) : label, fontWeight: isSel ? FontWeight.w700 : FontWeight.w400)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(o.dx - tp.width / 2, o.dy + r + 4));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => old.pos != pos || old.selected != selected || old.edges.length != edges.length || old.amber != amber;
}
