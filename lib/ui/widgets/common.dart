import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

Color pfColor(int argb) => Color(argb);

/// Monospace style helper (JetBrains Mono if bundled, otherwise platform monospace).
const List<String> kMonoFallback = ['JetBrains Mono', 'Menlo', 'Roboto Mono', 'monospace'];

class PfCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;

  const PfCard({super.key, required this.child, this.onTap, this.onLongPress, this.padding = const EdgeInsets.all(16), this.color, this.borderColor});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Material(
      color: color ?? p.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor ?? p.borderSubtle)),
          child: child,
        ),
      ),
    );
  }
}

class PfChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  const PfChip({super.key, required this.label, this.color, this.selected = false, this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final c = color ?? p.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.16) : p.surface3,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c : p.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 5)],
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? c : p.textSecondary)),
        ]),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const StatusBadge(this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(5)),
        child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.4)),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Opacity(opacity: 0.5, child: Icon(icon, size: 44, color: p.textTertiary)),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.textSecondary)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: TextStyle(color: p.textTertiary, fontSize: 13, height: 1.5)),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: TextStyle(fontSize: 11.5, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: p.textTertiary))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

Color scoreColor(BuildContext context, num v) {
  final p = context.pf;
  if (v >= 75) return p.green;
  if (v >= 50) return p.amber;
  return p.red;
}

class ScoreRing extends StatelessWidget {
  final int value;
  final double size;
  const ScoreRing(this.value, {super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final c = scoreColor(context, value);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(value: value / 100, strokeWidth: size / 10, color: c, backgroundColor: context.pf.surface2),
        ),
        Text('$value', style: TextStyle(fontSize: size * 0.32, fontWeight: FontWeight.w800, color: c)),
      ]),
    );
  }
}

class ScoreBar extends StatelessWidget {
  final String label;
  final int value;
  const ScoreBar(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final c = scoreColor(context, value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 92, child: Text(label, style: TextStyle(fontSize: 12.5, color: p.textSecondary))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: value / 100, minHeight: 7, color: c, backgroundColor: p.surface2),
          ),
        ),
        SizedBox(width: 34, child: Text('$value', textAlign: TextAlign.right, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c))),
      ]),
    );
  }
}

void toast(BuildContext context, String message) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 2200)));
}

Future<void> copyToClipboard(BuildContext context, String text, {String message = 'Copied to clipboard'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, message);
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, String confirmLabel = 'Confirm', bool destructive = false}) async {
  final p = context.pf;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: p.textSecondary))),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel, style: TextStyle(color: destructive ? p.red : p.amber, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> textPrompt(BuildContext context,
    {required String title, String label = '', String initial = '', String confirmLabel = 'Save', int maxLines = 1}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label.isEmpty ? null : label),
        onSubmitted: maxLines == 1 ? (v) => Navigator.pop(ctx, v) : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(confirmLabel)),
      ],
    ),
  );
}

/// Standard bottom sheet: drag handle + optional title + scrollable content.
Future<T?> showPfSheet<T>(BuildContext context, {String? title, required Widget Function(BuildContext) builder, bool full = false}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxWidth: 720, maxHeight: MediaQuery.of(context).size.height * (full ? 0.95 : 0.88)),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Align(alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          ),
        Flexible(child: builder(ctx)),
      ]),
    ),
  );
}

class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const SearchField({super.key, required this.controller, required this.onChanged, this.hint = 'Search'});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        isDense: true,
      ),
    );
  }
}

class KeyValueRow extends StatelessWidget {
  final String k;
  final String v;
  const KeyValueRow(this.k, this.v, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(k, style: TextStyle(color: p.textTertiary, fontSize: 13))),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 13.5))),
      ]),
    );
  }
}
