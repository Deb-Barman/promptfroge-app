import 'package:flutter/material.dart';

import '../../core/util.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Word-level diff rendering: additions highlighted green, removals struck through red.
class DiffView extends StatelessWidget {
  final String before;
  final String after;
  const DiffView({super.key, required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final ops = Utils.diffWords(before, after);
    final base = TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 12.5, height: 1.5, color: p.text);
    return SelectableText.rich(
      TextSpan(style: base, children: [
        for (final o in ops)
          TextSpan(
            text: o.text,
            style: o.type == 'add'
                ? TextStyle(backgroundColor: p.green.withOpacity(0.22), color: p.green)
                : o.type == 'remove'
                    ? TextStyle(backgroundColor: p.red.withOpacity(0.18), color: p.red, decoration: TextDecoration.lineThrough)
                    : null,
          ),
      ]),
    );
  }
}

/// Counts of added/removed words between two texts (for a one-line summary).
({int added, int removed}) diffCounts(String before, String after) {
  var a = 0, r = 0;
  for (final o in Utils.diffWords(before, after)) {
    if (o.text.trim().isEmpty) continue;
    if (o.type == 'add') a += Utils.countWords(o.text);
    if (o.type == 'remove') r += Utils.countWords(o.text);
  }
  return (added: a, removed: r);
}
