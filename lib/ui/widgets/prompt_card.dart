import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/util.dart';
import '../../domain/models.dart';
import '../theme/app_theme.dart';
import 'common.dart';

class PromptCard extends StatelessWidget {
  final Prompt prompt;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMenu;
  final bool selected;
  final bool selectionMode;

  const PromptCard({
    super.key,
    required this.prompt,
    required this.onTap,
    this.onLongPress,
    this.onMenu,
    this.selected = false,
    this.selectionMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final cat = categoryById(prompt.category);
    final st = statusById(prompt.status);
    return PfCard(
      onTap: onTap,
      onLongPress: onLongPress,
      borderColor: selected ? p.amber : null,
      color: selected ? p.amber.withOpacity(0.07) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (selectionMode) ...[
            Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: selected ? p.amber : p.textTertiary),
            const SizedBox(width: 10),
          ],
          Container(width: 9, height: 9, decoration: BoxDecoration(color: pfColor(cat.color), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(prompt.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
          ),
          if (prompt.pinned) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.push_pin, size: 15, color: p.amber)),
          if (prompt.favorite) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.star, size: 16, color: p.amber)),
          if (prompt.bestOf) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.emoji_events, size: 15, color: p.violet)),
          if (prompt.needsRevisit != null) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.flag, size: 15, color: p.red)),
          if (onMenu != null && !selectionMode)
            InkWell(
              onTap: onMenu,
              borderRadius: BorderRadius.circular(20),
              child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.more_vert, size: 20, color: p.textTertiary)),
            ),
        ]),
        if (prompt.body.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            prompt.body.trim().replaceAll(RegExp(r'\s+'), ' '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, height: 1.35, color: p.textSecondary),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          StatusBadge(cat.label, pfColor(cat.color)),
          if (prompt.status != 'draft') StatusBadge(st.label, pfColor(st.color)),
          for (final t in prompt.tags.take(3)) Text('#$t', style: TextStyle(fontSize: 11.5, color: p.textTertiary)),
          Text('v${prompt.currentVersion} · ${Utils.timeAgo(prompt.updatedAt)}', style: TextStyle(fontSize: 11.5, color: p.textTertiary)),
        ]),
      ]),
    );
  }
}
