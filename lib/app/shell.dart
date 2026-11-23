import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/models.dart';
import '../ui/widgets/pf_chrome.dart';
import '../ui/quick_capture.dart';
import '../ui/search_sheet.dart';

export '../ui/widgets/pf_chrome.dart' show zenModeProvider;

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

const List<String> _tabPaths = ['/dashboard', '/editor', '/library', '/builder', '/settings'];

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hardware-keyboard shortcuts (tablets, Chromebooks): Ctrl+K opens search, Alt+N captures an idea.
    Widget keys(Widget child) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => showSearchSheet(context, ref),
            const SingleActivator(LogicalKeyboardKey.keyN, alt: true): () => showQuickCapture(context, ref),
          },
          child: Focus(autofocus: true, child: child),
        );
    // Same frame as the web app on every size: top bar + page + status bar; navigation lives in the drawer.
    return keys(PfChrome(currentPath: _tabPaths[navigationShell.currentIndex], child: navigationShell));
  }
}
