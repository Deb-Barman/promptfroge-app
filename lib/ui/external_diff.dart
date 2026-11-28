import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/util.dart';
import '../data/vault/vault_repository.dart' show VaultData;
import '../domain/models.dart';
import '../state/vault_notifier.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';
import 'widgets/diff_view.dart';
import 'widgets/pf_menu.dart';

/// Diff text pasted from anywhere (a chat, an email, a colleague) against a saved prompt, then either save the
/// pasted text as a new prompt or update the original (its previous text is kept as a version first).
Future<void> showExternalDiff(BuildContext context, WidgetRef ref, {String? initialPromptId}) {
  final d = ref.read(vaultProvider).data;
  if (d.prompts.isEmpty) {
    toast(context, 'Save a prompt first — nothing to diff against yet.');
    return Future.value();
  }
  return showPfSheet<void>(
    context,
    title: 'Diff pasted text against a saved prompt',
    full: true,
    builder: (ctx) => _ExternalDiff(initialPromptId: initialPromptId),
  );
}

class _ExternalDiff extends ConsumerStatefulWidget {
  final String? initialPromptId;
  const _ExternalDiff({this.initialPromptId});

  @override
  ConsumerState<_ExternalDiff> createState() => _ExternalDiffState();
}

class _ExternalDiffState extends ConsumerState<_ExternalDiff> {
  final _paste = TextEditingController();
  String? _id;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    final d = ref.read(vaultProvider).data;
    final sorted = _sorted(d);
    _id = (widget.initialPromptId != null && d.prompts.containsKey(widget.initialPromptId)) ? widget.initialPromptId : sorted.first.id;
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  List<Prompt> _sorted(VaultData d) => d.prompts.values.toList()..sort((a, b) => a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final d = ref.watch(vaultProvider).data;
    final original = d.prompts[_id];
    final vn = ref.read(vaultProvider.notifier);
    final pasted = _paste.text;
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      PfField<String>(
        label: 'Compare against',
        value: _id,
        items: [for (final x in _sorted(d)) PfMenuItem<String>(x.id, x.displayTitle)],
        onChanged: (v) => setState(() => _id = v),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _paste,
        minLines: 6,
        maxLines: 12,
        style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 12.5),
        decoration: const InputDecoration(labelText: 'Pasted text', hintText: 'Paste the other version here…', alignLabelWithHint: true),
        onChanged: (_) => setState(() => _shown = _shown && _paste.text.trim().isNotEmpty),
      ),
      const SizedBox(height: 10),
      Row(children: [
        FilledButton.icon(
          icon: const Icon(Icons.difference_outlined, size: 18),
          label: const Text('Show diff'),
          onPressed: () {
            if (_paste.text.trim().isEmpty) {
              toast(context, 'Paste some text to diff first.');
              return;
            }
            setState(() => _shown = true);
          },
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          icon: const Icon(Icons.content_paste, size: 18),
          label: const Text('Paste'),
          onPressed: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            if (data?.text != null) setState(() => _paste.text = data!.text!);
          },
        ),
      ]),
      if (_shown && original != null) ...[
        const SectionTitle('Diff'),
        if (Utils.diffWords(original.body, pasted).isEmpty)
          Text('Both are empty.', style: TextStyle(color: p.textSecondary))
        else if (original.body == pasted)
          Text('No differences — identical.', style: TextStyle(color: p.textSecondary))
        else
          PfCard(child: DiffView(before: original.body, after: pasted)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
            onPressed: () async {
              final copy = Prompt(title: '${original.title.isEmpty ? 'Untitled' : original.title} (pasted)', body: Utils.sanitizeText(pasted), category: original.category);
              await vn.savePrompt(copy);
              if (!context.mounted) return;
              Navigator.pop(context);
              toast(context, 'Saved as a new prompt.');
            },
            child: const Text('Save pasted text as new prompt'),
          ),
          OutlinedButton(
            onPressed: () async {
              final ok = await confirmDialog(context,
                  title: 'Update "${original.displayTitle}"?', message: 'Its text is replaced by the pasted text. The current text is saved to History first.', confirmLabel: 'Update');
              if (!ok) return;
              await vn.createVersion(original.id, note: 'Before update from pasted text');
              final fresh = ref.read(vaultProvider).data.prompts[original.id];
              if (fresh != null) await vn.savePrompt(fresh.clone()..body = Utils.sanitizeText(pasted));
              if (!context.mounted) return;
              Navigator.pop(context);
              toast(context, '"${original.displayTitle}" updated — previous text saved to History.');
            },
            child: Text('Update "${Utils.truncate(original.displayTitle, 22)}"'),
          ),
        ]),
      ],
    ]);
  }
}
