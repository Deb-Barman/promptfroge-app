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
      builder: (context, child) => _UiZoom(zoom: settings.uiZoom, textScale: settings.uiScale, child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Scales the whole interface like browser zoom. The app is laid out in a virtual viewport of
/// `size / zoom` and then painted scaled by `zoom`, so text, icons, paddings and tap targets all shrink (or
/// grow) together. Insets (status bar, keyboard) are scaled to match, and overlays such as dialogs, sheets and
/// menus live inside the Navigator, so they follow along. Hit testing, scrolling and the keyboard's caret
/// tracking all use the transformed coordinates, so nothing else has to know.
class _UiZoom extends StatelessWidget {
  final double zoom;
  final double textScale;
  final Widget child;
  const _UiZoom({required this.zoom, required this.textScale, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final z = zoom.clamp(kMinUiZoom, kMaxUiZoom).toDouble();
    final data = mq.copyWith(textScaler: TextScaler.linear(textScale));
    if ((z - 1).abs() < 0.001) return MediaQuery(data: data, child: child);
    final vw = mq.size.width / z, vh = mq.size.height / z;
    return MediaQuery(
      data: data.copyWith(
        size: Size(vw, vh),
        padding: mq.padding / z,
        viewPadding: mq.viewPadding / z,
        viewInsets: mq.viewInsets / z,
        systemGestureInsets: mq.systemGestureInsets / z,
      ),
      child: SizedBox(
        width: mq.size.width,
        height: mq.size.height,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: vw,
            maxWidth: vw,
            minHeight: vh,
            maxHeight: vh,
            child: Transform.scale(scale: z, alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    );
  }
}
