import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/device_settings.dart';
import '../ui/onboarding.dart';
import '../ui/quick_capture.dart';
import '../ui/search_sheet.dart';
import '../ui/theme/app_theme.dart';
import '../ui/widgets/brand_logo.dart';

/// Key of the shell Scaffold, so any screen can open the navigation drawer.
final GlobalKey<ScaffoldState> shellScaffoldKey = GlobalKey<ScaffoldState>(debugLabel: 'pf-shell');

class _Item {
  final IconData icon;
  final String label;

  /// Index of a bottom-bar tab (goBranch) …
  final int? tab;

  /// … or a pushed route.
  final String? route;
  const _Item(this.icon, this.label, {this.tab, this.route});
}

// Same order as the original PromptForge.html side rail.
const List<_Item> _main = [
  _Item(Icons.space_dashboard_outlined, 'Dashboard', tab: 0),
  _Item(Icons.edit_outlined, 'Editor', tab: 1),
  _Item(Icons.view_agenda_outlined, 'Builder', tab: 3),
  _Item(Icons.menu_book_outlined, 'Library', tab: 2),
  _Item(Icons.vertical_split_outlined, 'Compare', route: '/compare'),
  _Item(Icons.dashboard_customize_outlined, 'Templates', route: '/templates'),
  _Item(Icons.bubble_chart_outlined, 'Patterns', route: '/patterns'),
  _Item(Icons.account_tree_outlined, 'Chains', route: '/chains'),
  _Item(Icons.history, 'History', route: '/history'),
  _Item(Icons.bar_chart_rounded, 'Analytics', route: '/analytics'),
  _Item(Icons.school_outlined, 'Learn', route: '/learn'),
];

const List<_Item> _extra = [
  _Item(Icons.hub_outlined, 'Links graph', route: '/graph'),
  _Item(Icons.event_note_outlined, 'Search by date', route: '/date-search'),
  _Item(Icons.import_export, 'Import / Export', route: '/data'),
];

const _Item _settings = _Item(Icons.settings_outlined, 'Settings', tab: 4);

/// Slide-in navigation drawer that mirrors the side rail of the original web app.
class AppDrawer extends ConsumerWidget {
  final int currentTab;
  final ValueChanged<int> onTab;
  const AppDrawer({super.key, required this.currentTab, required this.onTab});

  void _open(BuildContext context, _Item it) {
    Navigator.of(context).pop(); // close the drawer
    if (it.tab != null) {
      onTab(it.tab!);
    } else if (it.route != null) {
      context.push(it.route!);
    }
  }

  Widget _tile(BuildContext context, PfPalette p, _Item it) {
    final selected = it.tab != null && it.tab == currentTab;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1.5),
      child: Material(
        color: selected ? p.amber.withOpacity(0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _open(context, it),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Icon(it.icon, size: 20, color: selected ? p.amber : p.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(it.label, style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? p.amber : p.text)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pf;
    final ds = ref.watch(deviceSettingsProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      backgroundColor: p.surface,
      width: 292,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Row(children: [
              const BrandMarkTile(size: 42, glow: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Prompt Forge', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('Local-first · works offline', style: TextStyle(fontSize: 11.5, color: p.textTertiary)),
                ]),
              ),
              IconButton(
                tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
                icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                onPressed: () => ref.read(deviceSettingsProvider.notifier).update(ds.copyWith(themeMode: dark ? ThemeMode.light : ThemeMode.dark)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: Material(
              color: p.surface2,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  Navigator.of(context).pop();
                  showSearchSheet(context, ref);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
                  child: Row(children: [
                    Icon(Icons.search, size: 18, color: p.textTertiary),
                    const SizedBox(width: 10),
                    Text('Search everything…', style: TextStyle(fontSize: 14, color: p.textTertiary)),
                  ]),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.only(top: 4, bottom: 8), children: [
              for (final it in _main) _tile(context, p, it),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), child: Divider(height: 1, color: p.border)),
              for (final it in _extra) _tile(context, p, it),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  ActionChip(
                    avatar: const Icon(Icons.bolt, size: 16),
                    label: const Text('Quick capture'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      showQuickCapture(context, ref);
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.waving_hand_outlined, size: 16),
                    label: const Text('Welcome tour'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      showWelcome(context, ref);
                    },
                  ),
                ]),
              ),
            ]),
          ),
          Divider(height: 1, color: p.border),
          Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: _tile(context, p, _settings)),
        ]),
      ),
    );
  }
}
