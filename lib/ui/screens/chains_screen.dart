import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../core/util.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/pf_chrome.dart';
import '../widgets/common.dart';
import '../widgets/fill_variables.dart';

/// Chains: ordered multi-step workflows made of saved prompts. "Run" walks through the steps
/// so you can copy each one into your tool of choice (nothing is sent anywhere).
class ChainsScreen extends ConsumerWidget {
  const ChainsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pf;
    final d = ref.watch(vaultProvider).data;
    final chains = d.chains.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Scaffold(
      appBar: PfAppBar(title: const Text('Prompt Chains'), subtitle: 'Plan multi-step workflows — one prompt’s output feeding the next.'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showPfSheet<void>(context, title: 'New chain', full: true, builder: (_) => const _ChainForm()),
        icon: const Icon(Icons.add),
        label: const Text('New chain'),
      ),
      body: chains.isEmpty
          ? const EmptyState(icon: Icons.account_tree_outlined, title: 'No chains yet', body: 'A chain strings saved prompts together as steps — for example outline → draft → critique.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: chains.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (c, i) {
                final ch = chains[i];
                final missing = ch.steps.where((s) => s.promptId == null || !d.prompts.containsKey(s.promptId)).length;
                return PfCard(
                  onTap: () => showPfSheet<void>(context, title: ch.name, full: true, builder: (_) => _ChainRunner(chainId: ch.id)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(ch.name.isEmpty ? 'Untitled chain' : ch.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                      PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') await showPfSheet<void>(context, title: 'Edit chain', full: true, builder: (_) => _ChainForm(chain: ch));
                          if (v == 'delete') {
                            final ok = await confirmDialog(context, title: 'Delete chain?', message: 'The chain file is removed. Its prompts are kept.', confirmLabel: 'Delete', destructive: true);
                            if (ok) await ref.read(vaultProvider.notifier).deleteChain(ch.id);
                          }
                        },
                        itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
                      ),
                    ]),
                    if (ch.description.isNotEmpty) Text(ch.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text('${ch.steps.length} steps${missing > 0 ? ' · $missing missing prompt${missing == 1 ? '' : 's'}' : ''} · ${Utils.timeAgo(ch.updatedAt)}', style: TextStyle(color: missing > 0 ? p.amber : p.textTertiary, fontSize: 11.5)),
                  ]),
                );
              },
            ),
    );
  }
}

class _ChainRunner extends ConsumerStatefulWidget {
  final String chainId;
  const _ChainRunner({required this.chainId});

  @override
  ConsumerState<_ChainRunner> createState() => _ChainRunnerState();
}

class _ChainRunnerState extends ConsumerState<_ChainRunner> {
  final Set<String> _done = {};

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final d = ref.watch(vaultProvider).data;
    final chain = d.chains[widget.chainId];
    if (chain == null) return const SizedBox(height: 120, child: Center(child: Text('Chain not found')));
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
      if (chain.description.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(chain.description, style: TextStyle(color: p.textSecondary))),
      Text('Work through the steps in order: copy each prompt, run it in your own tool, then tick it off.', style: TextStyle(color: p.textTertiary, fontSize: 12.5)),
      const SizedBox(height: 8),
      for (var i = 0; i < chain.steps.length; i++)
        Builder(builder: (context) {
          final s = chain.steps[i];
          final pr = s.promptId == null ? null : d.prompts[s.promptId];
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: PfCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Checkbox(value: _done.contains(s.id), onChanged: (v) => setState(() => v == true ? _done.add(s.id) : _done.remove(s.id))),
                  Expanded(child: Text('${i + 1}. ${pr?.displayTitle ?? 'Missing prompt'}', style: TextStyle(fontWeight: FontWeight.w700, color: pr == null ? p.amber : null))),
                ]),
                if (s.note.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 12, bottom: 6), child: Text(s.note, style: TextStyle(color: p.textSecondary, fontSize: 13))),
                if (pr != null)
                  Row(children: [
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy'),
                      onPressed: () async {
                        final text = await fillVariables(context, pr.body, title: pr.displayTitle, actionLabel: 'Copy');
                        if (text != null && context.mounted) {
                          await copyToClipboard(context, text);
                          await ref.read(vaultProvider.notifier).incrementUse(pr.id);
                        }
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Open'),
                      onPressed: () {
                        Navigator.pop(context);
                        openInEditor(context, ref, promptId: pr.id);
                      },
                    ),
                  ]),
              ]),
            ),
          );
        }),
    ]);
  }
}

class _ChainForm extends ConsumerStatefulWidget {
  final Chain? chain;
  const _ChainForm({this.chain});

  @override
  ConsumerState<_ChainForm> createState() => _ChainFormState();
}

class _ChainFormState extends ConsumerState<_ChainForm> {
  late final _name = TextEditingController(text: widget.chain?.name ?? '');
  late final _desc = TextEditingController(text: widget.chain?.description ?? '');
  late final List<ChainStep> _steps = widget.chain?.steps.map((s) => s.clone()).toList() ?? [];

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _addStep() async {
    final d = ref.read(vaultProvider).data;
    final prompts = d.prompts.values.where((x) => !x.archived).toList()..sort((a, b) => a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
    final id = await showPfSheet<String>(
      context,
      title: 'Choose a prompt',
      builder: (ctx) => prompts.isEmpty
          ? const SingleChildScrollView(child: EmptyState(icon: Icons.description_outlined, title: 'No prompts yet', body: 'Create a prompt first, then add it as a step.'))
          : ListView(shrinkWrap: true, children: [for (final x in prompts) ListTile(title: Text(x.displayTitle), onTap: () => Navigator.pop(ctx, x.id))]),
    );
    if (id != null) setState(() => _steps.add(ChainStep(promptId: id)));
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, 'Give the chain a name.');
      return;
    }
    if (_steps.isEmpty) {
      toast(context, 'Add at least one step.');
      return;
    }
    final base = widget.chain?.clone() ?? Chain();
    base
      ..name = _name.text.trim()
      ..description = _desc.text.trim()
      ..steps = _steps;
    await ref.read(vaultProvider.notifier).saveChain(base);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(vaultProvider).data;
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
      TextField(controller: _name, decoration: const InputDecoration(labelText: 'Chain name'), textCapitalization: TextCapitalization.sentences),
      const SizedBox(height: 12),
      TextField(controller: _desc, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Description (optional)')),
      const SectionTitle('Steps'),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        onReorder: (o, n) => setState(() {
          if (n > o) n -= 1;
          _steps.insert(n, _steps.removeAt(o));
        }),
        children: [
          for (var i = 0; i < _steps.length; i++)
            ListTile(
              key: ValueKey(_steps[i].id),
              contentPadding: EdgeInsets.zero,
              leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
              title: Text(d.prompts[_steps[i].promptId]?.displayTitle ?? 'Missing prompt'),
              subtitle: _steps[i].note.isEmpty ? const Text('Tap to add a note') : Text(_steps[i].note),
              onTap: () async {
                final n = await textPrompt(context, title: 'Step note', label: 'What happens in this step?', initial: _steps[i].note, maxLines: 3);
                if (n != null) setState(() => _steps[i].note = n.trim());
              },
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _steps.removeAt(i))),
            ),
        ],
      ),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(icon: const Icon(Icons.add), label: const Text('Add step'), onPressed: _addStep)),
      const SizedBox(height: 12),
      FilledButton(onPressed: _save, child: const Text('Save chain')),
    ]);
  }
}
