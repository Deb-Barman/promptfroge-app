import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/util.dart';
import '../../../domain/engines/brain.dart';
import '../../../domain/engines/search_engine.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// The floating completion list shown right under the caret, like the web editor: compact rows, the best match
/// highlighted with an amber edge, a small WORD / PHRASE / SNIPPET tag on the right, and a thin scrollbar when
/// there are more than [maxRows] matches.
class SuggestionPopup extends StatefulWidget {
  final List<SuggestionItem> items;
  final ValueChanged<SuggestionItem> onPick;

  /// Shown instead of the list when a trigger (like `//`) has nothing to offer yet.
  final String? hint;
  const SuggestionPopup({super.key, required this.items, required this.onPick, this.hint});

  static const double hintHeight = 58;
  static const double rowHeight = 32;
  static const int maxRows = 7;

  /// Height the popup will take (also used by the editor to decide whether it fits below the caret).
  static double heightFor(int count) => math.min(count, maxRows) * rowHeight + 2;

  /// Width that fits the longest label, within [minW]..[maxW].
  static double widthFor(List<SuggestionItem> items, double maxW, {double minW = 190}) {
    var longest = 0;
    for (final i in items.take(maxRows)) {
      final len = math.min(i.label.replaceAll('\n', ' ').length, 40);
      if (len > longest) longest = len;
    }
    return (longest * 8.4 + 96).clamp(minW, math.max(minW, maxW));
  }

  @override
  State<SuggestionPopup> createState() => _SuggestionPopupState();
}

class _SuggestionPopupState extends State<SuggestionPopup> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final items = widget.items;
    final mono = TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 13.5, color: p.text);
    if (items.isEmpty && widget.hint != null) {
      return Container(
        height: SuggestionPopup.hintHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.borderStrong), boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 20, offset: Offset(0, 8))]),
        child: Row(children: [
          Icon(Icons.info_outline, size: 17, color: p.textTertiary),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.hint!, style: TextStyle(fontSize: 12.5, height: 1.35, color: p.textSecondary))),
        ]),
      );
    }
    final h = SuggestionPopup.heightFor(items.length);
    return Container(
      height: h,
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.borderStrong),
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 20, offset: Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: items.length > SuggestionPopup.maxRows,
        child: ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.zero,
          itemExtent: SuggestionPopup.rowHeight,
          itemCount: items.length,
          itemBuilder: (context, i) {
            final s = items[i];
            final best = i == 0;
            return InkWell(
              onTap: () => widget.onPick(s),
              child: Container(
                padding: const EdgeInsets.only(left: 11, right: 12),
                decoration: BoxDecoration(
                  color: best ? p.amber.withValues(alpha: 0.11) : null,
                  border: Border(left: BorderSide(color: best ? p.amber : Colors.transparent, width: 3)),
                ),
                child: Row(children: [
                  Expanded(child: Text(Utils.truncate(s.label.replaceAll('\n', ' '), 40), maxLines: 1, overflow: TextOverflow.ellipsis, style: mono)),
                  const SizedBox(width: 10),
                  Text(s.src.toUpperCase(), style: TextStyle(fontSize: 9.5, letterSpacing: 0.9, fontWeight: FontWeight.w700, color: p.textTertiary)),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A row of the brain's next-word predictions, shown above the keyboard (tap to insert).
class BrainStrip extends StatelessWidget {
  final List<BrainHit> hits;
  final ValueChanged<BrainHit> onPick;
  const BrainStrip({super.key, required this.hits, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final mono = TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 13, color: p.text, fontWeight: FontWeight.w500);
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: Icon(Icons.auto_awesome, size: 15, color: p.amber)),
          ),
          for (final h in hits)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: p.surface3,
                shape: StadiumBorder(side: BorderSide(color: p.border)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onPick(h),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Center(child: Text(Utils.truncate(h.label, 34), style: mono))),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
