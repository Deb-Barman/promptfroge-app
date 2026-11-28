import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../domain/models.dart';
import '../../state/vault_notifier.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Groups exist separately for prompts ('library'), templates and patterns, exactly like the original app.
String groupKindNoun(String kind) => kind == 'templates' ? 'templates' : (kind == 'patterns' ? 'patterns' : 'prompts');

Future<int?> _pickColor(BuildContext context, int current) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Group colour'),
      content: Wrap(spacing: 12, runSpacing: 12, children: [
        for (final c in kGroupColors)
          GestureDetector(
            onTap: () => Navigator.pop(ctx, c),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: c == current ? Colors.white : Colors.transparent, width: 3)),
              child: c == current ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
            ),
          ),
      ]),
    ),
  );
}

/// Create / rename / recolour / delete groups of one kind. [onSelect] (optional) lets the caller filter by a group.
Future<void> showGroupsManager(BuildContext context, {required String kind, String? selectedId, ValueChanged<String?>? onSelect}) {
  final noun = groupKindNoun(kind);
  return showPfSheet<void>(
    context,
    title: 'Manage groups',
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final p = ctx.pf;
      final vn = ref.read(vaultProvider.notifier);
      final groups = ref.watch(vaultProvider).data.groups.values.where((g) => g.kind == kind).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 0, 8, 24), children: [
        if (groups.isEmpty)
          Padding(padding: const EdgeInsets.all(20), child: Text('No groups yet. A group is a named, coloured set of $noun you can filter by.', style: TextStyle(color: p.textSecondary))),
        for (final g in groups)
          ListTile(
            leading: GestureDetector(
              onTap: () async {
                final c = await _pickColor(ctx, g.color);
                if (c != null) await vn.saveGroup(g.clone()..color = c);
              },
              child: CircleAvatar(radius: 14, backgroundColor: Color(g.color)),
            ),
            title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${g.memberIds.length} ${g.memberIds.length == 1 ? 'item' : 'items'}', style: TextStyle(color: p.textTertiary, fontSize: 12)),
            selected: g.id == selectedId,
            onTap: onSelect == null
                ? null
                : () {
                    onSelect(g.id == selectedId ? null : g.id);
                    Navigator.pop(ctx);
                  },
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'rename') {
                  final n = await textPrompt(ctx, title: 'Rename group', label: 'Name', initial: g.name);
                  if (n != null && n.trim().isNotEmpty) await vn.saveGroup(g.clone()..name = n.trim());
                } else if (v == 'color') {
                  final c = await _pickColor(ctx, g.color);
                  if (c != null) await vn.saveGroup(g.clone()..color = c);
                } else if (v == 'delete') {
                  final ok = await confirmDialog(ctx, title: 'Delete group?', message: 'The $noun in "${g.name}" are kept; only the group is removed.', confirmLabel: 'Delete', destructive: true);
                  if (ok) {
                    if (selectedId == g.id) onSelect?.call(null);
                    await vn.deleteGroup(g.id);
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'color', child: Text('Change colour')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        ListTile(
          leading: Icon(Icons.add_circle_outline, color: p.amber),
          title: const Text('New group'),
          onTap: () async {
            final n = await textPrompt(ctx, title: 'New group', label: 'Name', confirmLabel: 'Create');
            if (n != null && n.trim().isNotEmpty) {
              await vn.saveGroup(Group(kind: kind, name: n.trim(), color: kGroupColors[groups.length % kGroupColors.length]));
            }
          },
        ),
      ]);
    }),
  );
}

/// Tick the groups that [ids] should belong to. With several ids a tick adds all of them, an un-tick removes all.
Future<void> showGroupMembership(BuildContext context, {required String kind, required List<String> ids}) {
  return showPfSheet<void>(
    context,
    title: 'Add to groups',
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final vn = ref.read(vaultProvider.notifier);
      final groups = ref.watch(vaultProvider).data.groups.values.where((g) => g.kind == kind).toList();
      if (groups.isEmpty) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('No groups yet.', style: TextStyle(color: ctx.pf.textSecondary)),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: () => showGroupsManager(ctx, kind: kind), child: const Text('Create a group')),
          ]),
        );
      }
      return ListView(shrinkWrap: true, children: [
        for (final g in groups)
          CheckboxListTile(
            secondary: CircleAvatar(radius: 10, backgroundColor: Color(g.color)),
            title: Text(g.name),
            value: ids.isNotEmpty && ids.every(g.memberIds.contains),
            onChanged: (v) async {
              for (final id in ids) {
                await vn.setGroupMembership(g.id, id, v ?? false);
              }
            },
          ),
        const SizedBox(height: 16),
      ]);
    }),
  );
}

/// Horizontal chip row: "All" + one chip per group of [kind]. Hidden when there are no groups.
class GroupFilterBar extends ConsumerWidget {
  final String kind;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final EdgeInsets padding;
  const GroupFilterBar({super.key, required this.kind, required this.selectedId, required this.onChanged, this.padding = const EdgeInsets.symmetric(horizontal: 16)});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(vaultProvider).data.groups.values.where((g) => g.kind == kind).toList();
    if (groups.isEmpty) return const SizedBox.shrink();
    final p = context.pf;
    return SizedBox(
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, padding: padding, children: [
        Padding(padding: const EdgeInsets.only(right: 8), child: PfChip(label: 'All groups', icon: Icons.folder_open, selected: selectedId == null, color: p.amber, onTap: () => onChanged(null))),
        for (final g in groups)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PfChip(label: '${g.name} · ${g.memberIds.length}', selected: selectedId == g.id, color: Color(g.color), onTap: () => onChanged(selectedId == g.id ? null : g.id)),
          ),
      ]),
    );
  }
}
