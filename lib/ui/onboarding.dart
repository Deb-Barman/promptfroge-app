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
    builder: (ctx) {
      final p = ctx.pf;
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Welcome to Prompt Forge', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text("Everything here runs locally — nothing you write ever leaves this device. A quick look at what's available:", style: TextStyle(color: p.textSecondary, fontSize: 13.5, height: 1.4)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final f in _features)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(12)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(f.$1, color: p.amber, size: 22),
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
              const SizedBox(height: 8),
              Row(children: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Skip, I'll explore")),
                const Spacer(),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Take the 30-second tour')),
              ]),
            ]),
          ),
        ),
      );
    },
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
