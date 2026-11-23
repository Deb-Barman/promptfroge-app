import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'widgets/pf_chrome.dart';
import 'onboarding.dart';
import 'quick_capture.dart';

import 'theme/app_theme.dart';
import 'widgets/common.dart';

class _MoreItem {
  final IconData icon;
  final String label;
  final String route;
  final String hint;
  const _MoreItem(this.icon, this.label, this.route, this.hint);
}

const List<_MoreItem> _items = [
  _MoreItem(Icons.article_outlined, 'Templates', '/templates', 'Reusable prompts with variables'),
  _MoreItem(Icons.pattern, 'Patterns', '/patterns', 'Proven prompt patterns'),
  _MoreItem(Icons.account_tree_outlined, 'Chains', '/chains', 'Multi-step workflows'),
  _MoreItem(Icons.history, 'History', '/history', 'Versions, diff and restore'),
  _MoreItem(Icons.insights_outlined, 'Analytics', '/analytics', 'Stats, quality and activity'),
  _MoreItem(Icons.compare_arrows, 'Compare', '/compare', 'Side-by-side prompt diff'),
  _MoreItem(Icons.school_outlined, 'Learn', '/learn', 'Tips and challenges'),
  _MoreItem(Icons.hub_outlined, 'Links', '/graph', '[[wiki-link]] graph'),
  _MoreItem(Icons.event_note_outlined, 'Search by date', '/date-search', 'What changed on a day or range'),
  _MoreItem(Icons.import_export, 'Import / Export', '/data', 'Backup, restore, export'),
];

/// AppBar action that opens the list of secondary screens.
class MoreMenuButton extends ConsumerWidget {
  const MoreMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Inside the app frame the top bar already has the menu button; only show this where there is no frame.
    if (PfChromeScope.maybeOf(context) != null) return const SizedBox.shrink();
    return IconButton(tooltip: 'More', icon: const Icon(Icons.menu_rounded), onPressed: () => showMoreSheet(context, ref));
  }
}

Future<void> showMoreSheet(BuildContext context, WidgetRef ref) {
  return showPfSheet<void>(
    context,
    title: 'More',
    builder: (ctx) {
      final p = ctx.pf;
      return ListView(shrinkWrap: true, children: [
      GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        crossAxisCount: MediaQuery.of(ctx).size.width > 600 ? 3 : 2,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.7,
        children: [
          for (final it in _items)
            PfCard(
              onTap: () {
                Navigator.pop(ctx);
                context.push(it.route);
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(it.icon, color: p.amber),
                const SizedBox(height: 6),
                Text(it.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(it.hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.textTertiary)),
              ]),
            ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(
            avatar: const Icon(Icons.bolt, size: 18),
            label: const Text('Quick capture'),
            onPressed: () {
              Navigator.pop(ctx);
              showQuickCapture(context, ref);
            },
          ),
          ActionChip(
            avatar: const Icon(Icons.waving_hand_outlined, size: 18),
            label: const Text('Welcome tour'),
            onPressed: () {
              Navigator.pop(ctx);
              showWelcome(context, ref);
            },
          ),
        ]),
      ),
      ]);
    },
  );
}
