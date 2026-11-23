import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../domain/engines/cleaner.dart';
import '../../../domain/engines/tools.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'editor_tools.dart';

/// The always-visible action rows from the original web editor:
/// one-tap rewrites (Clean, Shorten, Wrap XML …) and the coloured "+ Role / + Context …" block chips.
class EditorQuickActions extends StatelessWidget {
  final EditorHost host;

  /// Show the second row of block chips (hidden while the keyboard is open to save space).
  final bool showBlocks;

  /// Icon strip appended to the first row (find, undo, redo, zen, new, menu).
  final List<Widget> trailing;
  const EditorQuickActions({super.key, required this.host, this.showBlocks = true, this.trailing = const []});

  void _apply(BuildContext c, String result, String msg) {
    if (result == host.text) {
      toast(c, 'No change');
      return;
    }
    host.replaceText(result);
    toast(c, '$msg — undo from the toolbar');
  }

  void _block(BlockType b) {
    final empty = host.text.trim().isEmpty;
    host.insertAtCursor('${empty ? '' : '\n\n'}${b.label}:\n');
  }

  Widget _action(BuildContext c, PfPalette p, String label, VoidCallback onTap, {IconData? icon}) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ActionChip(
          avatar: icon == null ? null : Icon(icon, size: 15, color: p.textSecondary),
          label: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
            _action(context, p, 'Clean', () => _apply(context, PromptCleaner.autoClean(host.text), 'Cleaned'), icon: Icons.cleaning_services_outlined),
            _action(context, p, 'Improve', () => showEditorTools(context, host, initialTab: 0), icon: Icons.auto_fix_high),
            _action(context, p, 'Security check', () => showEditorTools(context, host, initialTab: 1), icon: Icons.shield_outlined),
            _action(context, p, 'Copy as…', () => showEditorTools(context, host, initialTab: 4), icon: Icons.copy_all_outlined),
            _action(context, p, 'Wrap XML', () => _apply(context, ModelAdapter.wrapInXml(host.text, host.format), 'Wrapped in XML tags'), icon: Icons.code),
            _action(context, p, 'Adapt for…', () => showEditorTools(context, host, initialTab: 2), icon: Icons.tune),
            _action(context, p, 'Extract variables', () => showEditorTools(context, host, initialTab: 3), icon: Icons.data_object),
            _action(context, p, 'Shorten', () => _apply(context, PromptTools.shorten(host.text), 'Shortened'), icon: Icons.compress),
            _action(context, p, 'Bulletify', () => _apply(context, PromptTools.bulletify(host.text), 'Bulletified'), icon: Icons.format_list_bulleted),
            _action(context, p, '+ Reasoning', () {
              host.insertAtCursor(PromptTools.chainOfThoughtBlock());
              toast(context, 'Inserted at cursor');
            }, icon: Icons.psychology_outlined),
            _action(context, p, 'More tools', () => showEditorTools(context, host), icon: Icons.more_horiz),
            ...trailing,
          ]),
        ),
        if (showBlocks)
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
              for (final b in kBlockTypes)
                Padding(
                  padding: const EdgeInsets.only(right: 6, top: 4, bottom: 6),
                  child: PfChip(label: '+ ${b.label}', color: pfColor(b.color), selected: true, onTap: () => _block(b)),
                ),
            ]),
          ),
      ]),
    );
  }
}
