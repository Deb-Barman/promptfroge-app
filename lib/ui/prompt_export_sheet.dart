import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/util.dart';
import '../domain/engines/exporter.dart';
import '../domain/models.dart';
import '../state/vault_notifier.dart';
import 'export_helpers.dart';
import 'widgets/common.dart';

/// Copy / save-to-vault / share a single prompt in one of the export formats.
Future<void> showPromptExportSheet(BuildContext context, WidgetRef ref, Prompt p) {
  const formats = [
    ['txt', 'Plain text (.txt)'],
    ['md', 'Markdown (.md)'],
    ['json', 'JSON (.json)'],
    ['html', 'HTML (.html)'],
  ];
  return showPfSheet<void>(
    context,
    title: 'Export "${p.displayTitle}"',
    builder: (ctx) => ListView(shrinkWrap: true, children: [
      for (final f in formats)
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(f[1]),
          subtitle: const Text('Tap to save into Exports/ and share'),
          trailing: IconButton(tooltip: 'Copy', icon: const Icon(Icons.copy), onPressed: () => copyToClipboard(ctx, Exporter.promptToFormat(p, f[0]))),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            Navigator.pop(ctx);
            final root = ref.read(vaultProvider).rootPath;
            if (root == null) return;
            final name = '${Utils.fileSafe(p.displayTitle)}.${Exporter.fileExt(f[0])}';
            try {
              final file = await saveExportFile(root, name, Exporter.promptToFormat(p, f[0]));
              messenger.showSnackBar(SnackBar(content: Text('Saved to Exports/$name')));
              await shareFilePath(file.path);
            } catch (e) {
              messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
            }
          },
        ),
    ]),
  );
}
