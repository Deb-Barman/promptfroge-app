import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/device_settings.dart';
import 'theme/app_theme.dart';

const List<(IconData, String, String)> _features = [
  (Icons.edit_note, 'Editor', 'Live analyzer scoring, readability, risk linting, and model-aware token and cost estimates as you type.'),
  (Icons.compare_arrows, 'Compare', 'Put two or more saved prompts side by side with a word-level diff.'),
  (Icons.account_tree_outlined, 'Chains', "Plan multi-step workflows — one prompt's output feeding the next."),
  (Icons.view_agenda_outlined, 'Patterns & Builder', 'Start from a proven structure, or put together labelled blocks visually.'),
  (Icons.bolt, 'Quick capture', 'Jot an idea straight into your Inbox without opening the editor (the bolt button on the Dashboard).'),
  (Icons.search, 'Search', 'Jump to any prompt, template or action from the search button, or search by date.'),
];

class _TourStep {
  final IconData icon;
  final String title;
  final String body;
  final String? route; // where "Go there" leads (null: no button)
  const _TourStep(this.icon, this.title, this.body, [this.route]);
}

const List<_TourStep> _tour = [
  _TourStep(Icons.space_dashboard_outlined, 'Dashboard', 'Your recent prompts, quick actions and stats live here.', '/dashboard'),
  _TourStep(Icons.folder_copy_outlined, 'Library', 'Every saved prompt, searchable and filterable. Long-press a card to select several at once.', '/library'),
  _TourStep(Icons.pattern, 'Patterns', 'Reusable prompt structures — start from one instead of a blank page.', '/patterns'),
  _TourStep(Icons.account_tree_outlined, 'Chains', "Plan a multi-step workflow: one prompt's output feeding the next.", '/chains'),
  _TourStep(Icons.search, 'Search', 'The search button in the top bar finds prompts and runs actions from anywhere.'),
  _TourStep(Icons.check_circle_outline, "You're set", 'Everything is a plain file in your vault folder, so you can open it in Obsidian too. Have a look around — this is your working space now.'),
];

/// First-run welcome. Marks onboarding as seen however it is dismissed.
Future<void> showWelcome(BuildContext context, WidgetRef ref) async {
  void markSeen() {
    final dev = ref.read(deviceSettingsProvider.notifier);
    final ds = ref.read(deviceSettingsProvider);
    if (!ds.onboardingSeen) dev.update(ds.copyWith(onboardingSeen: true));
  }

  final takeTour = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final p = ctx.pf;
      final ds = ref.watch(deviceSettingsProvider);
      final dev = ref.read(deviceSettingsProvider.notifier);
      final maxH = MediaQuery.of(ctx).size.height - 48;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520, maxHeight: maxH),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // everything that can grow scrolls; the buttons below never leave the dialog
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Welcome to Prompt Forge', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  const SizedBox(height: 6),
                  Text("Everything here runs locally — nothing you write ever leaves this device.", style: TextStyle(color: p.textSecondary, fontSize: 13, height: 1.4)),
                  const SizedBox(height: 14),
                  Text('INTERFACE SIZE', style: TextStyle(fontSize: 10.5, letterSpacing: 1, fontWeight: FontWeight.w800, color: p.textTertiary)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final z in const [(0.6, 'Tiny'), (0.75, 'Small'), (0.9, 'Compact'), (1.0, 'Standard'), (1.15, 'Large')])
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(z.$2),
                        selected: (ds.uiZoom - z.$1).abs() < 0.03,
                        onSelected: (_) => dev.update(ds.copyWith(uiZoom: z.$1)),
                      ),
                  ]),
                  const SizedBox(height: 4),
                  Text('Changes instantly. You can change it any time in Settings.', style: TextStyle(color: p.textTertiary, fontSize: 11.5)),
                  const SizedBox(height: 14),
                  for (final f in _features)
                    Container(
                      margin: const EdgeInsets.only(bottom: 7),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(border: Border.all(color: p.borderSubtle), borderRadius: BorderRadius.circular(12), color: p.surface2),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(f.$1, color: p.amber, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(f.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                            const SizedBox(height: 2),
                            Text(f.$3, style: TextStyle(color: p.textSecondary, fontSize: 12.5, height: 1.35)),
                          ]),
                        ),
                      ]),
                    ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Take the 30-second tour')),
                const SizedBox(height: 4),
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Skip, I'll explore")),
              ]),
            ),
          ]),
        ),
      );
    }),
  );
  markSeen();
  if (takeTour == true && context.mounted) await showTour(context);
}

/// Step-by-step tour (the original highlighted rail items; on a phone each step is a card with a "Go there" shortcut).
Future<void> showTour(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      var i = 0;
      return StatefulBuilder(builder: (ctx, setState) {
        final p = ctx.pf;
        final s = _tour[i];
        final last = i == _tour.length - 1;
        return AlertDialog(
          title: Row(children: [
            Icon(s.icon, color: p.amber),
            const SizedBox(width: 10),
            Expanded(child: Text(s.title)),
            Text('${i + 1}/${_tour.length}', style: TextStyle(color: p.textTertiary, fontSize: 12)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.body, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 14),
            Row(children: [
              for (var k = 0; k < _tour.length; k++)
                Container(
                  width: k == i ? 18 : 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(color: k == i ? p.amber : p.border, borderRadius: BorderRadius.circular(4)),
                ),
            ]),
          ]),
          actions: [
            if (i > 0) TextButton(onPressed: () => setState(() => i--), child: const Text('Back')),
            if (s.route != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.go(s.route!);
                },
                child: const Text('Go there'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            FilledButton(onPressed: last ? () => Navigator.pop(ctx) : () => setState(() => i++), child: Text(last ? 'Done' : 'Next')),
          ],
        );
      });
    },
  );
}
