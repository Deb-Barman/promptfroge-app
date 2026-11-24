import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../domain/engines/cleaner.dart';
import '../../../domain/engines/tools.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'editor_tools.dart';

/// The editor action area of the original web app: Save / Download / Save version buttons followed by plain
/// text actions (Clean, Improve, Security check …) that wrap onto several lines, then the coloured block chips.
/// While the keyboard is open it collapses into one horizontally scrolling row so the text keeps its room.
class EditorQuickActions extends StatelessWidget {
  final EditorHost host;

  /// Buttons at the start of the area (Save, Download, Save version, save state).
  final List<Widget> leading;

  /// Icon strip at the end (find, undo, redo, zen, new, menu).
  final List<Widget> trailing;

  /// True while the keyboard is open.
  final bool compact;
  const EditorQuickActions({super.key, required this.host, this.leading = const [], this.trailing = const [], this.compact = false});

  void _apply(BuildContext c, String result, String msg) {
    if (result == host.text) {
      toast(c, 'No change');
      return;
    }
    host.replaceText(result);
    toast(c, '$msg — undo from the toolbar');
  }

  void _insertBlock(String text) {
    final empty = host.text.trim().isEmpty;
    host.insertAtCursor('${empty ? '' : '\n\n'}$text');
  }

  void _block(BlockType b) => _insertBlock('${b.label}:\n');

  Widget _link(BuildContext c, PfPalette p, String label, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.textSecondary)),
        ),
      );

  void _shortcuts(BuildContext context) {
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
    final p = context.pf;
    final links = <Widget>[
      _link(context, p, 'Clean', () => _apply(context, PromptCleaner.autoClean(host.text), 'Cleaned')),
      _link(context, p, 'Improve', () => showEditorTools(context, host, initialTab: 0)),
      _link(context, p, 'Security check', () => showEditorTools(context, host, initialTab: 1)),
      _link(context, p, 'Copy as…', () => showEditorTools(context, host, initialTab: 4)),
      _link(context, p, 'Wrap XML', () => _apply(context, ModelAdapter.wrapInXml(host.text, host.format), 'Wrapped in XML tags')),
      _link(context, p, 'Adapt for…', () => showEditorTools(context, host, initialTab: 2)),
      _link(context, p, '+ Constraint', () => _insertBlock('Constraints:\n- ')),
      _link(context, p, 'Extract variables', () => showEditorTools(context, host, initialTab: 3)),
      _link(context, p, '+ Examples', () => _insertBlock('Examples:\nInput: \nOutput: ')),
      _link(context, p, 'Edge cases', () => _insertBlock('Edge Cases:\n- ')),
      _link(context, p, 'Shorten', () => _apply(context, PromptTools.shorten(host.text), 'Shortened')),
      _link(context, p, 'Bulletify', () => _apply(context, PromptTools.bulletify(host.text), 'Bulletified')),
      _link(context, p, '+ Reasoning', () {
        host.insertAtCursor(PromptTools.chainOfThoughtBlock());
        toast(context, 'Inserted at cursor');
      }),
      _link(context, p, 'More tools ▾', () => showEditorTools(context, host)),
      _link(context, p, 'Shortcuts', () => _shortcuts(context)),
    ];

    if (compact) {
      final all = [...leading, ...links, ...trailing];
      return Container(
        height: 48,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.borderSubtle))),
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
          for (final w in all) Center(child: Padding(padding: const EdgeInsets.only(right: 4), child: w)),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 12, 6),
        child: Wrap(spacing: 0, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final w in leading) Padding(padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4), child: w),
          ...links,
          ...trailing,
        ]),
      ),
      Container(
        width: double.infinity,
        decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.borderSubtle), bottom: BorderSide(color: p.borderSubtle))),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final b in kBlockTypes) PfChip(label: '+ ${b.label}', color: pfColor(b.color), selected: true, onTap: () => _block(b)),
        ]),
      ),
    ]);
  }
}
