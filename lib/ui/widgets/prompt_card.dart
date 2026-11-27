import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/util.dart';
import '../../domain/engines/analyzer.dart';
import '../../domain/models.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// The quick actions a library card offers without opening a menu.
class PromptCardActions {
  final String profileId;
  final VoidCallback onCopy;
  final VoidCallback onFavorite;
  final VoidCallback onBestOf;
  final VoidCallback onPin;
  final VoidCallback onDuplicate;
  final VoidCallback onArchive;
  const PromptCardActions({
    required this.profileId,
    required this.onCopy,
    required this.onFavorite,
    required this.onBestOf,
    required this.onPin,
    required this.onDuplicate,
    required this.onArchive,
  });
}

final Map<String, int> _scoreCache = {};

/// Analyzer score for a prompt, cached until the prompt (or the scoring profile) changes.
int promptScore(Prompt p, String profileId) {
  final key = '${p.id}|${p.updatedAt}|$profileId';
  final hit = _scoreCache[key];
  if (hit != null) return hit;
  if (_scoreCache.length > 800) _scoreCache.clear();
  return _scoreCache[key] = Analyzer.analyze(p.body, profileId: profileId).overall;
}

/// A prompt as a card. With [actions] it becomes the full library card: score badge, "date · words · used"
/// line, one-tap favourite / best-of / pin / duplicate / archive and a Copy button. Without it (dashboard) it
/// stays the compact summary.
class PromptCard extends StatelessWidget {
  final Prompt prompt;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMenu;
  final bool selected;
  final bool selectionMode;
  final PromptCardActions? actions;

  const PromptCard({
    super.key,
    required this.prompt,
    required this.onTap,
    this.onLongPress,
    this.onMenu,
    this.selected = false,
    this.selectionMode = false,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final cat = categoryById(prompt.category);
    final st = statusById(prompt.status);
    final rich = actions != null && !selectionMode;
    return PfCard(
      onTap: onTap,
      onLongPress: onLongPress,
      borderColor: selected ? p.amber : null,
      color: selected ? p.amber.withValues(alpha: 0.07) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (selectionMode) ...[
            Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: selected ? p.amber : p.textTertiary),
            const SizedBox(width: 10),
          ],
          Container(width: 9, height: 9, decoration: BoxDecoration(color: pfColor(cat.color), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(prompt.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
          if (!rich) ...[
            if (prompt.pinned) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.push_pin, size: 15, color: p.amber)),
            if (prompt.favorite) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.star, size: 16, color: p.amber)),
            if (prompt.bestOf) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.emoji_events, size: 15, color: p.violet)),
          ],
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
          Text(prompt.body.trim().replaceAll(RegExp(r'\s+'), ' '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.35, color: p.textSecondary)),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          StatusBadge(cat.label, pfColor(cat.color)),
          if (prompt.status != 'draft') StatusBadge(st.label, pfColor(st.color)),
          for (final t in prompt.tags.take(3)) Text('#$t', style: TextStyle(fontSize: 11.5, color: p.textTertiary)),
          if (prompt.tags.length > 3) Text('+${prompt.tags.length - 3}', style: TextStyle(fontSize: 11.5, color: p.textTertiary)),
          if (!rich) Text('v${prompt.currentVersion} · ${Utils.timeAgo(prompt.updatedAt)}', style: TextStyle(fontSize: 11.5, color: p.textTertiary)),
        ]),
        if (rich) ...[
          const SizedBox(height: 10),
          _MetaRow(prompt: prompt, profileId: actions!.profileId),
          const SizedBox(height: 8),
          _ActionRow(prompt: prompt, actions: actions!),
        ],
      ]),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final Prompt prompt;
  final String profileId;
  const _MetaRow({required this.prompt, required this.profileId});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final score = promptScore(prompt, profileId);
    final c = scoreColor(context, score);
    final words = Utils.countWords(prompt.body);
    return Row(children: [
      Tooltip(
        message: 'Analyzer score',
        child: Container(
          constraints: const BoxConstraints(minWidth: 34),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withValues(alpha: 0.55))),
          child: Text('$score', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          '${Utils.formatDate(prompt.updatedAt, withTime: false)} · ${words}w${prompt.useCount > 0 ? ' · used ${prompt.useCount}×' : ''} · v${prompt.currentVersion}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: p.textTertiary, fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback),
        ),
      ),
    ]);
  }
}

class _ActionRow extends StatelessWidget {
  final Prompt prompt;
  final PromptCardActions actions;
  const _ActionRow({required this.prompt, required this.actions});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    Widget btn(IconData icon, IconData onIcon, bool on, Color onColor, String tip, VoidCallback fn) => Tooltip(
          message: tip,
          child: InkResponse(
            onTap: fn,
            radius: 20,
            child: SizedBox(width: 36, height: 36, child: Icon(on ? onIcon : icon, size: 20, color: on ? onColor : p.textTertiary)),
          ),
        );
    return Row(children: [
      btn(Icons.star_border, Icons.star, prompt.favorite, p.amber, prompt.favorite ? 'Remove favorite' : 'Favorite', actions.onFavorite),
      btn(Icons.emoji_events_outlined, Icons.emoji_events, prompt.bestOf, p.violet, prompt.bestOf ? 'Remove “best of”' : 'Mark as best of', actions.onBestOf),
      btn(Icons.push_pin_outlined, Icons.push_pin, prompt.pinned, p.blue, prompt.pinned ? 'Unpin' : 'Pin to top', actions.onPin),
      btn(Icons.copy_all_outlined, Icons.copy_all_outlined, false, p.text, 'Duplicate', actions.onDuplicate),
      btn(prompt.archived ? Icons.unarchive_outlined : Icons.archive_outlined, Icons.archive, false, p.text, prompt.archived ? 'Unarchive' : 'Archive', actions.onArchive),
      const Spacer(),
      FilledButton.tonalIcon(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), visualDensity: VisualDensity.compact),
        icon: const Icon(Icons.content_copy, size: 16),
        label: const Text('Copy'),
        onPressed: actions.onCopy,
      ),
    ]);
  }
}
