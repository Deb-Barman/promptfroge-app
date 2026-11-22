import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/models.dart';
import 'app_drawer.dart';
import '../ui/quick_capture.dart';
import '../ui/search_sheet.dart';
import '../ui/theme/app_theme.dart';

/// True while the editor is in Zen mode (hides the navigation chrome).
final zenModeProvider = StateProvider<bool>((ref) => false);

/// Asks the editor tab to open a prompt (by id) or start a new one seeded with text.
class EditorRequest {
  final String? promptId;
  final String? seedBody;
  final String? seedTitle;
  final String? seedFormat;
  final List<PromptBlock>? seedBlocks;
  final int nonce;
  EditorRequest({this.promptId, this.seedBody, this.seedTitle, this.seedFormat, this.seedBlocks}) : nonce = DateTime.now().microsecondsSinceEpoch;
}

final editorRequestProvider = StateProvider<EditorRequest?>((ref) => null);

void openInEditor(BuildContext context, WidgetRef ref,
    {String? promptId, String? seedBody, String? seedTitle, String? seedFormat, List<PromptBlock>? seedBlocks}) {
  ref.read(editorRequestProvider.notifier).state =
      EditorRequest(promptId: promptId, seedBody: seedBody, seedTitle: seedTitle, seedFormat: seedFormat, seedBlocks: seedBlocks);
  context.go('/editor');
}

class _Dest {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _Dest(this.icon, this.selectedIcon, this.label);
}

const List<_Dest> _dests = [
  _Dest(Icons.space_dashboard_outlined, Icons.space_dashboard, 'Dashboard'),
  _Dest(Icons.edit_note_outlined, Icons.edit_note, 'Editor'),
  _Dest(Icons.folder_copy_outlined, Icons.folder_copy, 'Library'),
  _Dest(Icons.view_agenda_outlined, Icons.view_agenda, 'Builder'),
  _Dest(Icons.settings_outlined, Icons.settings, 'Settings'),
];

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  void _go(int i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zen = ref.watch(zenModeProvider);
    final p = context.pf;
    final wide = MediaQuery.of(context).size.width >= 840;
    // Hardware-keyboard shortcuts (tablets, Chromebooks): Ctrl+K opens search, Alt+N captures an idea.
    Widget keys(Widget child) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => showSearchSheet(context, ref),
            const SingleActivator(LogicalKeyboardKey.keyN, alt: true): () => showQuickCapture(context, ref),
          },
          child: Focus(autofocus: true, child: child),
        );
    if (wide) {
      return keys(Scaffold(
        key: shellScaffoldKey,
        drawer: AppDrawer(currentTab: navigationShell.currentIndex, onTab: _go),
        body: Row(children: [
          if (!zen)
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              destinations: [for (final d in _dests) NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label))],
            ),
          if (!zen) VerticalDivider(width: 1, color: p.border),
          Expanded(child: navigationShell),
        ]),
      ));
    }
    return keys(Scaffold(
      key: shellScaffoldKey,
      drawer: AppDrawer(currentTab: navigationShell.currentIndex, onTab: _go),
      drawerEnableOpenDragGesture: !zen,
      body: navigationShell,
      bottomNavigationBar: zen
          ? null
          : NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _go,
              destinations: [for (final d in _dests) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label)],
            ),
    ));
  }
}
