import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/shell.dart';
import '../domain/models.dart';
import '../state/vault_notifier.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

/// Quick capture: jot an idea straight into the Inbox category without opening the editor.
Future<void> showQuickCapture(BuildContext context, WidgetRef ref) {
  return showPfSheet<void>(
    context,
    title: 'Quick capture',
    builder: (ctx) => _QuickCaptureForm(outerContext: context, ref: ref),
  );
}

class _QuickCaptureForm extends StatefulWidget {
  final BuildContext outerContext;
  final WidgetRef ref;
  const _QuickCaptureForm({required this.outerContext, required this.ref});

  @override
  State<_QuickCaptureForm> createState() => _QuickCaptureFormState();
}

class _QuickCaptureFormState extends State<_QuickCaptureForm> {
  final _body = TextEditingController();
  final _title = TextEditingController();

  @override
  void dispose() {
    _body.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<Prompt?> _save() async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      toast(context, 'Nothing to save yet — type something first.');
      return null;
    }
    return widget.ref.read(vaultProvider.notifier).savePrompt(Prompt(title: _title.text.trim(), body: body, category: 'inbox'));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
      Text("Jot the idea down now — it's saved to your Inbox category, ready to refine in the full editor later.", style: TextStyle(color: p.textTertiary, fontSize: 12.5)),
      const SizedBox(height: 12),
      TextField(controller: _body, autofocus: true, minLines: 5, maxLines: 10, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Type a prompt idea, a rough draft, a fragment worth keeping…')),
      const SizedBox(height: 10),
      TextField(controller: _title, maxLength: 200, decoration: const InputDecoration(labelText: 'Title (optional)', counterText: '')),
      const SizedBox(height: 8),
      Row(children: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        const Spacer(),
        OutlinedButton(
          onPressed: () async {
            final saved = await _save();
            if (saved == null || !context.mounted) return;
            Navigator.pop(context);
            if (widget.outerContext.mounted) openInEditor(widget.outerContext, widget.ref, promptId: saved.id);
          },
          child: const Text('Save & open'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () async {
            final saved = await _save();
            if (saved == null || !context.mounted) return;
            Navigator.pop(context);
            if (widget.outerContext.mounted) toast(widget.outerContext, 'Saved to Inbox.');
          },
          child: const Text('Save to Inbox'),
        ),
      ]),
    ]);
  }
}
