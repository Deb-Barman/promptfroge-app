import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../domain/engines/brain.dart';
import '../../../domain/engines/cleaner.dart';
import '../../../domain/engines/tools.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'editor_tools.dart';

/// One round-cornered icon button of the editor's action rail.
class RailButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final Color? color;
  final Widget? badge;

  const RailButton({super.key, required this.icon, required this.tooltip, this.onTap, this.active = false, this.color, this.badge});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final enabled = onTap != null;
    final fg = !enabled ? p.textTertiary.withValues(alpha: 0.5) : (color ?? (active ? p.amber : p.textSecondary));
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? p.amber.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(alignment: Alignment.center, children: [
              Icon(icon, size: 21, color: fg),
              if (badge != null) Positioned(right: 5, top: 5, child: badge!),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Thin separator between groups on the action rail.
class RailDivider extends StatelessWidget {
  const RailDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 11), child: SizedBox(width: 1, child: ColoredBox(color: context.pf.border)));
}

/// The editor's primary action rail: a single horizontally scrolling row (no wrapping, no overlap).
class EditorActionRail extends StatelessWidget {
  final List<Widget> children;
  const EditorActionRail({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Container(
      height: 48,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.borderSubtle))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: children,
      ),
    );
  }
}

/// The text transformations of the web editor, as one scrollable row of compact chips with icons.
class EditorQuickTools extends StatelessWidget {
  final EditorHost host;
  const EditorQuickTools({super.key, required this.host});

  void _apply(BuildContext c, String result, String msg) {
    if (result == host.text) {
      toast(c, 'No change');
      return;
    }
    host.replaceText(result);
    toast(c, '$msg — undo from the toolbar');
  }

  static void shortcuts(BuildContext context) {
    final p = context.pf;
    const rows = [
      ['/', 'Insert a snippet'],
      ['//', 'Insert a saved prompt'],
      ['///', 'Insert a pattern'],
      ['\\', 'Insert a template'],
      ['\\\\', 'Insert a prompt block'],
      ['@', 'Link to another prompt'],
      ['{{', 'Add a variable'],
    ];
    showPfSheet<void>(
      context,
      title: 'Typing shortcuts',
      builder: (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              SizedBox(width: 56, child: Text(r[0], style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontWeight: FontWeight.w700, color: p.amber))),
              Expanded(child: Text(r[1])),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, VoidCallback)>[
      (Icons.cleaning_services_outlined, 'Clean', () => _apply(context, PromptCleaner.autoClean(host.text), 'Cleaned')),
      (Icons.auto_awesome_outlined, 'Improve', () => showEditorTools(context, host, initialTab: 0)),
      (Icons.shield_outlined, 'Security check', () => showEditorTools(context, host, initialTab: 1)),
      (Icons.ios_share_outlined, 'Copy as…', () => showEditorTools(context, host, initialTab: 4)),
      (Icons.data_object, 'Wrap XML', () => _apply(context, ModelAdapter.wrapInXml(host.text, host.format), 'Wrapped in XML tags')),
      (Icons.tune, 'Adapt for…', () => showEditorTools(context, host, initialTab: 2)),
      (Icons.data_array, 'Extract variables', () => showEditorTools(context, host, initialTab: 3)),
      (Icons.compress, 'Shorten', () => _apply(context, PromptTools.shorten(host.text), 'Shortened')),
      (Icons.format_list_bulleted, 'Bulletify', () => _apply(context, PromptTools.bulletify(host.text), 'Bulletified')),
      (Icons.psychology_outlined, 'Reasoning', () {
        host.insertAtCursor(PromptTools.chainOfThoughtBlock());
        toast(context, 'Inserted at cursor');
      }),
      (Icons.apps, 'More tools', () => showEditorTools(context, host)),
      (Icons.keyboard_command_key, 'Shortcuts', () => shortcuts(context)),
    ];
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        children: [for (final t in items) Padding(padding: const EdgeInsets.only(right: 6), child: _ToolChip(icon: t.$1, label: t.$2, onTap: t.$3))],
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ToolChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Material(
      color: p.surface3,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: p.borderSubtle)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: p.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.textSecondary)),
          ]),
        ),
      ),
    );
  }
}

/// The coloured prompt-section chips (+ Role, + Context …) as one scrollable row. The brain orders them by
/// what this user normally writes next and marks the sections their prompts usually have but this one lacks.
class EditorBlocksRow extends StatelessWidget {
  final EditorHost host;
  final List<BlockHint>? hints;
  const EditorBlocksRow({super.key, required this.host, this.hints});

  static String seedFor(BlockType b) {
    switch (b.id) {
      case 'constraints':
        return 'Constraints:\n- ';
      case 'examples':
        return 'Examples:\nInput: \nOutput: ';
      case 'edgecases':
        return 'Edge Cases:\n- ';
      case 'instructions':
        return 'Instructions:\n1. ';
      default:
        return '${b.label}:\n';
    }
  }

  void _insert(BlockType b) {
    final empty = host.text.trim().isEmpty;
    host.insertAtCursor('${empty ? '' : '\n\n'}${seedFor(b)}');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final byId = {for (final h in hints ?? const <BlockHint>[]) h.id: h};
    final blocks = [...kBlockTypes];
    if (byId.isNotEmpty) {
      int rank(BlockType b) {
        final h = byId[b.id];
        if (h == null) return 1;
        if (h.present) return 2;
        return h.recommended ? 0 : 1;
      }

      final order = {for (var i = 0; i < kBlockTypes.length; i++) kBlockTypes[i].id: i};
      blocks.sort((a, b) {
        final c = rank(a).compareTo(rank(b));
        if (c != 0) return c;
        if (rank(a) == 1) {
          final s = (byId[b.id]?.score ?? 0).compareTo(byId[a.id]?.score ?? 0);
          if (s != 0) return s;
        }
        return order[a.id]!.compareTo(order[b.id]!);
      });
    }
    return Container(
      height: 46,
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.borderSubtle), bottom: BorderSide(color: p.borderSubtle))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        children: [
          for (final b in blocks)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: _BlockPill(block: b, color: pfColor(b.color), present: byId[b.id]?.present ?? false, recommended: byId[b.id]?.recommended ?? false, onTap: () => _insert(b)),
            ),
        ],
      ),
    );
  }
}

class _BlockPill extends StatelessWidget {
  final BlockType block;
  final Color color;
  final bool present;
  final bool recommended;
  final VoidCallback onTap;
  const _BlockPill({required this.block, required this.color, required this.present, required this.recommended, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = present ? color.withValues(alpha: 0.55) : color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: present ? 0.06 : (recommended ? 0.2 : 0.12)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: recommended ? color : color.withValues(alpha: present ? 0.3 : 0.55), width: recommended ? 1.4 : 1),
          boxShadow: recommended ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8)] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (present) Icon(Icons.check, size: 14, color: fg) else if (recommended) Icon(Icons.auto_awesome, size: 13, color: fg) else Text('+', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
          const SizedBox(width: 4),
          Text(block.label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
        ]),
      ),
    );
  }
}
