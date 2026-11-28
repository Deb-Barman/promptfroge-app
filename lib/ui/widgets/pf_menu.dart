import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One row of a [showPfMenu] dropdown.
class PfMenuItem<T> {
  final T? value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Color? color;

  /// A non-selectable section heading.
  final bool header;
  const PfMenuItem(T this.value, this.label, {this.subtitle, this.icon, this.color}) : header = false;
  const PfMenuItem.header(this.label)
      : value = null,
        subtitle = null,
        icon = null,
        color = null,
        header = true;
}

const double _kRow = 42;
const double _kRowWithSub = 54;
const double _kHeader = 32;

/// Opens a dropdown panel anchored to the widget that owns [anchorContext]: directly under it when there is room,
/// over it otherwise. It has the same width as the anchor (at least [minWidth]), scrolls when long, marks the
/// current choice, and for long lists ([searchable], or more than 9 items) offers a search box.
///
/// Positions are worked out in the overlay's own coordinate space, so this stays exact when the whole interface is
/// zoomed (Settings → Interface size). Returns the chosen value, or null when dismissed.
Future<T?> showPfMenu<T>(
  BuildContext anchorContext, {
  required List<PfMenuItem<T>> items,
  T? selected,
  double minWidth = 180,
  double maxWidth = 420,
  bool? searchable,
}) {
  final overlay = Overlay.of(anchorContext);
  final overlayBox = overlay.context.findRenderObject() as RenderBox?;
  final anchorBox = anchorContext.findRenderObject() as RenderBox?;
  if (overlayBox == null || anchorBox == null || !anchorBox.hasSize) return Future.value(null);
  final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
  final anchor = topLeft & anchorBox.size;
  final media = MediaQuery.of(anchorContext);

  final completer = Completer<T?>();
  late OverlayEntry entry;
  var closed = false;
  void close([T? value]) {
    if (closed) return;
    closed = true;
    entry.remove();
    completer.complete(value);
  }

  entry = OverlayEntry(
    builder: (ctx) => _MenuLayer<T>(
      anchor: anchor,
      overlaySize: overlayBox.size,
      keyboard: media.viewInsets.bottom,
      topInset: media.padding.top,
      items: items,
      selected: selected,
      minWidth: minWidth,
      maxWidth: maxWidth,
      searchable: searchable ?? items.length > 9,
      onPick: close,
      onDismiss: () => close(),
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _MenuLayer<T> extends StatefulWidget {
  final Rect anchor;
  final Size overlaySize;
  final double keyboard;
  final double topInset;
  final List<PfMenuItem<T>> items;
  final T? selected;
  final double minWidth;
  final double maxWidth;
  final bool searchable;
  final ValueChanged<T> onPick;
  final VoidCallback onDismiss;
  const _MenuLayer({
    required this.anchor,
    required this.overlaySize,
    required this.keyboard,
    required this.topInset,
    required this.items,
    required this.selected,
    required this.minWidth,
    required this.maxWidth,
    required this.searchable,
    required this.onPick,
    required this.onDismiss,
  });

  @override
  State<_MenuLayer<T>> createState() => _MenuLayerState<T>();
}

class _MenuLayerState<T> extends State<_MenuLayer<T>> {
  final _query = TextEditingController();
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    final i = widget.items.indexWhere((e) => !e.header && e.value == widget.selected);
    _scroll = ScrollController(initialScrollOffset: i <= 2 ? 0 : (i - 2) * _kRow);
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final q = _query.text.trim().toLowerCase();
    final shown = q.isEmpty ? widget.items : widget.items.where((e) => e.label.toLowerCase().contains(q) || (e.subtitle ?? '').toLowerCase().contains(q)).toList();

    final width = widget.anchor.width.clamp(widget.minWidth, widget.maxWidth).toDouble().clamp(0.0, widget.overlaySize.width - 16).toDouble();
    final left = widget.anchor.left.clamp(8.0, math.max(8.0, widget.overlaySize.width - width - 8)).toDouble();

    var contentH = widget.searchable ? 56.0 : 0.0;
    for (final e in shown) {
      contentH += e.header ? _kHeader : (e.subtitle == null ? _kRow : _kRowWithSub);
    }
    contentH = math.max(contentH, _kRow) + 12;

    final bottomLimit = widget.overlaySize.height - widget.keyboard - 10;
    final below = bottomLimit - widget.anchor.bottom - 6;
    final above = widget.anchor.top - widget.topInset - 14;
    final fitsBelow = contentH <= below;
    final goUp = !fitsBelow && above > below;
    final maxH = math.max(120.0, math.min(goUp ? above : below, 380.0));
    final height = math.min(contentH, maxH);
    final top = goUp ? widget.anchor.top - height - 6 : widget.anchor.bottom + 6;

    return BackButtonListener(
      onBackButtonPressed: () async {
        widget.onDismiss();
        return true;
      },
      child: Stack(children: [
        Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onDismiss, child: const SizedBox.expand())),
        Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (goUp ? 6 : -6) * (1 - v)), child: child)),
            child: Material(
              color: p.raised,
              elevation: 10,
              shadowColor: const Color(0xAA000000),
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.borderStrong)),
                child: Column(children: [
                  if (widget.searchable)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _query,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 13.5),
                          decoration: InputDecoration(
                            hintText: 'Search…',
                            isDense: true,
                            prefixIcon: Icon(Icons.search, size: 18, color: p.textTertiary),
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: shown.isEmpty
                        ? Center(child: Text('No matches', style: TextStyle(color: p.textTertiary, fontSize: 13)))
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemExtentBuilder: (i, _) => shown[i].header ? _kHeader : (shown[i].subtitle == null ? _kRow : _kRowWithSub),
                            itemCount: shown.length,
                            itemBuilder: (c, i) => _Row<T>(item: shown[i], selected: !shown[i].header && shown[i].value == widget.selected, onTap: () {
                              final v = shown[i].value;
                              if (!shown[i].header && v != null) widget.onPick(v);
                            }),
                          ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Row<T> extends StatelessWidget {
  final PfMenuItem<T> item;
  final bool selected;
  final VoidCallback onTap;
  const _Row({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    if (item.header) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Text(item.label.toUpperCase(), style: TextStyle(fontSize: 10.5, letterSpacing: 1, fontWeight: FontWeight.w800, color: p.textTertiary)),
      );
    }
    final color = selected ? p.amber : (item.color ?? p.text);
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: selected ? p.amber.withValues(alpha: 0.12) : null, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          if (item.icon != null) ...[Icon(item.icon, size: 18, color: selected ? p.amber : p.textTertiary), const SizedBox(width: 10)],
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color)),
              if (item.subtitle != null) Text(item.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.textTertiary)),
            ]),
          ),
          if (selected) Icon(Icons.check, size: 18, color: p.amber),
        ]),
      ),
    );
  }
}

/// The web app's `.select`: a bordered box with the current choice; tap opens a [showPfMenu] panel.
class PfSelect<T> extends StatelessWidget {
  final T value;
  final List<MapEntry<T, String>> options;
  final ValueChanged<T> onChanged;
  final double? width;
  final String? hint;
  const PfSelect({super.key, required this.value, required this.options, required this.onChanged, this.width, this.hint});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final match = options.where((o) => o.key == value);
    final label = match.isNotEmpty ? match.first.value : (hint ?? (options.isEmpty ? '' : options.first.value));
    return Builder(
      builder: (ctx) => SizedBox(
        width: width,
        child: Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: options.isEmpty
                ? null
                : () async {
                    final v = await showPfMenu<T>(ctx, items: [for (final o in options) PfMenuItem<T>(o.key, o.value)], selected: value);
                    if (v != null) onChanged(v);
                  },
            child: Container(
              height: 40,
              padding: const EdgeInsets.only(left: 12, right: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
              child: Row(children: [
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5))),
                Icon(Icons.expand_more, size: 20, color: p.textTertiary),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled select that looks like the app's text fields (replaces `DropdownButtonFormField`).
class PfField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<PfMenuItem<T>> items;
  final ValueChanged<T> onChanged;
  final String? helper;
  const PfField({super.key, required this.label, required this.value, required this.items, required this.onChanged, this.helper});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final match = items.where((o) => !o.header && o.value == value);
    return Builder(
      builder: (ctx) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: items.isEmpty
            ? null
            : () async {
                final v = await showPfMenu<T>(ctx, items: items, selected: value);
                if (v != null) onChanged(v);
              },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, helperText: helper, suffixIcon: Icon(Icons.expand_more, color: p.textTertiary)),
          isEmpty: match.isEmpty,
          child: Text(match.isNotEmpty ? match.first.label : '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5)),
        ),
      ),
    );
  }
}
