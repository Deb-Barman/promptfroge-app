import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/vault_notifier.dart';
import '../ui/screens/analytics_screen.dart';
import '../ui/screens/builder_screen.dart';
import '../ui/screens/chains_screen.dart';
import '../ui/screens/compare_screen.dart';
import '../ui/screens/dashboard_screen.dart';
import '../ui/screens/data_screen.dart';
import '../ui/screens/date_search_screen.dart';
import '../ui/screens/editor/editor_screen.dart';
import '../ui/screens/graph_screen.dart';
import '../ui/screens/history_screen.dart';
import '../ui/screens/learn_screen.dart';
import '../ui/screens/library_screen.dart';
import '../ui/screens/patterns_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/screens/templates_screen.dart';
import '../ui/screens/vault_setup_screen.dart';
import '../ui/widgets/pf_chrome.dart';
import 'shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<VaultState>(vaultProvider, (prev, next) {
    if (prev?.status != next.status) refresh.value++;
  });
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    redirect: (context, state) {
      final ready = ref.read(vaultProvider).isReady;
      final atSetup = state.matchedLocation == '/vault';
      if (!ready && !atSetup) return '/vault';
      if (ready && atSetup) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/vault', builder: (c, s) => const VaultSetupScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/dashboard', builder: (c, s) => const DashboardScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/editor', builder: (c, s) => const EditorScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/library', builder: (c, s) => const LibraryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/builder', builder: (c, s) => const BuilderScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen())]),
        ],
      ),
      GoRoute(path: '/templates', builder: (c, s) => PfChrome(currentPath: '/templates', child: const TemplatesScreen())),
      GoRoute(path: '/patterns', builder: (c, s) => PfChrome(currentPath: '/patterns', child: const PatternsScreen())),
      GoRoute(path: '/chains', builder: (c, s) => PfChrome(currentPath: '/chains', child: const ChainsScreen())),
      GoRoute(path: '/history', builder: (c, s) => PfChrome(currentPath: '/history', child: HistoryScreen(initialPromptId: s.uri.queryParameters['id']))),
      GoRoute(path: '/analytics', builder: (c, s) => PfChrome(currentPath: '/analytics', child: const AnalyticsScreen())),
      GoRoute(path: '/compare', builder: (c, s) => PfChrome(currentPath: '/compare', child: const CompareScreen())),
      GoRoute(path: '/learn', builder: (c, s) => PfChrome(currentPath: '/learn', child: const LearnScreen())),
      GoRoute(path: '/graph', builder: (c, s) => PfChrome(currentPath: '/graph', child: const GraphScreen())),
      GoRoute(path: '/data', builder: (c, s) => PfChrome(currentPath: '/data', child: const DataScreen())),
      GoRoute(path: '/date-search', builder: (c, s) => PfChrome(currentPath: '/date-search', child: const DateSearchScreen())),
    ],
  );
});
