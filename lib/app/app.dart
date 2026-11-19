import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/device_settings.dart';
import '../state/tokenizer_provider.dart';
import '../state/vault_notifier.dart';
import '../ui/theme/app_theme.dart';
import 'router.dart';

class PromptForgeApp extends ConsumerStatefulWidget {
  const PromptForgeApp({super.key});

  @override
  ConsumerState<PromptForgeApp> createState() => _PromptForgeAppState();
}

class _PromptForgeAppState extends ConsumerState<PromptForgeApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(vaultProvider.notifier).bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Like Obsidian: pick up files that were changed outside the app when we come back to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ref.read(vaultProvider).isReady) {
      ref.read(vaultProvider.notifier).rescan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(deviceSettingsProvider);
    final router = ref.watch(routerProvider);
    ref.watch(tokenizerProvider); // warm the exact tokenizer in the background
    return MaterialApp.router(
      title: 'Prompt Forge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeMode,
      routerConfig: router,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(settings.uiScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
