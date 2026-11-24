import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_drawer.dart';
import '../../state/device_settings.dart';
import '../../state/vault_notifier.dart';
import '../search_sheet.dart';
import '../theme/app_theme.dart';
import 'brand_logo.dart';
import 'common.dart';

/// Word count of the document open in the editor (shown in the status bar like the web app).
final editorWordsProvider = StateProvider<int>((ref) => 0);

/// True while the editor is in Zen mode (hides the app chrome).
final zenModeProvider = StateProvider<bool>((ref) => false);

/// Lets any screen open the navigation drawer of the surrounding [PfChrome].
class PfChromeScope extends InheritedWidget {
  final VoidCallback openDrawer;
  const PfChromeScope({super.key, required this.openDrawer, required super.child});

  static PfChromeScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PfChromeScope>();

  @override
  bool updateShouldNotify(PfChromeScope oldWidget) => false;
}

const Map<String, String> kViewLabels = {
  '/dashboard': 'Dashboard',
  '/editor': 'Editor',
  '/builder': 'Builder',
  '/library': 'Library',
  '/compare': 'Compare',
  '/templates': 'Templates',
  '/patterns': 'Patterns',
  '/chains': 'Chains',
  '/history': 'History',
  '/analytics': 'Analytics',
  '/learn': 'Learn',
  '/settings': 'Settings',
  '/graph': 'Graph',
  '/data': 'Import / Export',
  '/date-search': 'Search by date',
};

/// The app frame of the original web app: a 52px top bar (menu, logo, search, theme, export),
/// the page, and a 26px status bar. The navigation drawer lives here too.
class PfChrome extends ConsumerStatefulWidget {
  final String currentPath;
  final Widget child;
  const PfChrome({super.key, required this.currentPath, required this.child});

  @override
  ConsumerState<PfChrome> createState() => _PfChromeState();
}

class _PfChromeState extends ConsumerState<PfChrome> {
  final GlobalKey<ScaffoldState> _key = GlobalKey<ScaffoldState>();

  void _openDrawer() => _key.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final zen = ref.watch(zenModeProvider);
    final kb = MediaQuery.of(context).viewInsets.bottom > 0;
    final page = PfChromeScope(openDrawer: _openDrawer, child: widget.child);
    if (zen) {
      return Scaffold(key: _key, resizeToAvoidBottomInset: false, backgroundColor: p.bg, body: page);
    }
    return Scaffold(
      key: _key,
      backgroundColor: p.bg,
      resizeToAvoidBottomInset: false,
      drawer: AppDrawer(currentPath: widget.currentPath),
      body: Column(children: [
        PfTopBar(onMenu: _openDrawer),
        Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, removeBottom: !kb, child: page)),
        if (!kb) PfStatusBar(path: widget.currentPath),
      ]),
    );
  }
}

class PfTopBar extends ConsumerWidget {
  final VoidCallback onMenu;
  const PfTopBar({super.key, required this.onMenu});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pf;
    final top = MediaQuery.of(context).padding.top;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ds = ref.watch(deviceSettingsProvider);
    return Container(
      height: 52 + top,
      padding: EdgeInsets.only(top: top, left: 4, right: 4),
      decoration: BoxDecoration(color: p.surface, border: Border(bottom: BorderSide(color: p.borderSubtle))),
      child: Row(children: [
        IconButton(tooltip: 'Toggle navigation', icon: const Icon(Icons.menu_rounded), onPressed: onMenu),
        const BrandMarkTile(size: 30, glow: false),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showSearchSheet(context, ref),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.borderSubtle)),
              child: Row(children: [
                Icon(Icons.search, size: 17, color: p.textTertiary),
                const SizedBox(width: 8),
                Expanded(child: Text('Search…', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.textTertiary))),
              ]),
            ),
          ),
        ),
        IconButton(
          tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
          icon: Icon(dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined, size: 21),
          onPressed: () => ref.read(deviceSettingsProvider.notifier).update(ds.copyWith(themeMode: dark ? ThemeMode.light : ThemeMode.dark)),
        ),
        IconButton(tooltip: 'Export data', icon: const Icon(Icons.file_download_outlined, size: 22), onPressed: () => context.go('/data')),
      ]),
    );
  }
}

class PfStatusBar extends ConsumerWidget {
  final String path;
  const PfStatusBar({super.key, required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pf;
    ref.watch(vaultProvider.select((v) => v.revision));
    final data = ref.read(vaultProvider).data;
    var chars = 0;
    for (final x in data.prompts.values) {
      chars += x.body.length + x.title.length;
    }
    for (final t in data.templates.values) {
      chars += t.body.length + t.name.length;
    }
    final mb = chars / 1048576;
    final words = path == '/editor' ? ref.watch(editorWordsProvider) : 0;
    final mono = TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 11, color: p.textTertiary);
    return Container(
      height: 26 + MediaQuery.of(context).padding.bottom,
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.borderSubtle))),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: p.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
          child: Text(kViewLabels[path] ?? '', style: mono.copyWith(color: p.amber, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Text('$words words', style: mono),
        const SizedBox(width: 8),
        Text('·', style: mono),
        const Spacer(),
        Text('${mb < 0.1 ? mb.toStringAsFixed(2) : mb.toStringAsFixed(1)} MB used locally', style: mono),
      ]),
    );
  }
}

/// Drop-in replacement for [AppBar]: the web app's big page title (+ optional subtitle) with the actions on the right.
class PfAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  const PfAppBar({super.key, this.title, this.subtitle, this.actions, this.leading, this.bottom});

  @override
  Size get preferredSize => Size.fromHeight((subtitle == null ? 60 : 82) + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Material(
      color: p.bg,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: subtitle == null ? 60 : 82,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 6, 0),
            child: Row(children: [
              if (leading != null) leading!,
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  DefaultTextStyle(
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: p.text, fontFamilyFallback: AppTheme.uiFontFallback),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: title ?? const SizedBox.shrink(),
                  ),
                  if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.textTertiary))),
                ]),
              ),
              if (actions != null) ...actions!,
            ]),
          ),
        ),
        if (bottom != null) bottom!,
      ]),
    );
  }
}

/// In-body page header (title, subtitle and a wrapping row of action buttons), like `.view-header` in the web app.
class PfPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const PfPageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: p.text)),
        if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: TextStyle(fontSize: 13, color: p.textTertiary, height: 1.4))),
        if (actions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions)),
      ]),
    );
  }
}

/// `.btn` / `.btn-primary` / `.btn-secondary` of the web app.
class PfBtn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  const PfBtn({super.key, required this.label, this.icon, this.onPressed, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final fg = primary ? const Color(0xFF1A1206) : p.text;
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: Material(
        color: primary ? p.amber : p.surface3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: primary ? p.amber : p.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 7)],
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Square icon button used next to [PfBtn]s in page headers.
class PfIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const PfIconBtn({super.key, required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: p.surface3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: p.border)),
        child: InkWell(borderRadius: BorderRadius.circular(8), onTap: onPressed, child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 19, color: p.textSecondary))),
      ),
    );
  }
}

/// `.select` of the web app: a bordered box showing the current choice; tap opens a menu.
class PfSelect<T> extends StatelessWidget {
  final T value;
  final List<MapEntry<T, String>> options;
  final ValueChanged<T> onChanged;
  final double? width;
  const PfSelect({super.key, required this.value, required this.options, required this.onChanged, this.width});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final label = options.firstWhere((o) => o.key == value, orElse: () => options.first).value;
    return SizedBox(
      width: width,
      child: PopupMenuButton<T>(
        tooltip: '',
        onSelected: onChanged,
        position: PopupMenuPosition.under,
        itemBuilder: (_) => [for (final o in options) PopupMenuItem<T>(value: o.key, child: Text(o.value, style: TextStyle(fontWeight: o.key == value ? FontWeight.w700 : FontWeight.w400, color: o.key == value ? p.amber : null)))],
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
          child: Row(children: [
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5))),
            Icon(Icons.keyboard_arrow_down, size: 18, color: p.textTertiary),
          ]),
        ),
      ),
    );
  }
}

/// Big-number stat card (`.stat-card`): icon, monospace number, small label.
class PfStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const PfStatCard({super.key, required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.borderSubtle)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 22, color: p.textTertiary.withOpacity(0.7)),
        const SizedBox(height: 10),
        Text(value, style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -1, height: 1.1, color: p.text)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12.5, color: p.textTertiary)),
      ]),
    );
  }
}

/// Small uppercase label used inside cards ("RECENTLY EDITED", "ACTIVITY — LAST 14 DAYS" …).
class PfCardLabel extends StatelessWidget {
  final String text;
  const PfCardLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: context.pf.textTertiary)),
      );
}


/// Underline tabs like the web app's `.tabs` (used instead of Material's SegmentedButton).
class PfTabs<T> extends StatelessWidget {
  final T value;
  final List<MapEntry<T, String>> options;
  final ValueChanged<T> onChanged;
  const PfTabs({super.key, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Row(children: [
      for (final o in options)
        Expanded(
          child: InkWell(
            onTap: () => onChanged(o.key),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: o.key == value ? p.amber : p.borderSubtle, width: o.key == value ? 2 : 1))),
              child: Text(o.value, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: o.key == value ? p.amber : p.textTertiary)),
            ),
          ),
        ),
    ]);
  }
}
