import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/vault/vault_location.dart';
import '../../state/vault_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/common.dart';

/// First-run / reconnect screen: choose or create the folder that holds all prompts and data.
class VaultSetupScreen extends ConsumerStatefulWidget {
  const VaultSetupScreen({super.key});

  @override
  ConsumerState<VaultSetupScreen> createState() => _VaultSetupScreenState();
}

class _VaultSetupScreenState extends ConsumerState<VaultSetupScreen> {
  String? _message;
  bool _busy = false;

  Future<void> _run(Future<void> Function() task) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await task();
    } on VaultAccessException catch (e) {
      _message = e.message;
    } catch (e) {
      _message = 'Something went wrong: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final vault = ref.watch(vaultProvider);
    final loading = _busy || vault.status == VaultStatus.loading;
    final error = _message ?? (vault.status == VaultStatus.error ? vault.error : null);
    final notifier = ref.read(vaultProvider.notifier);
    final remembered = notifier.location.savedPath;

    if (loading) {
      return const Scaffold(
        body: SafeArea(
          child: BrandSplash(
            tip: 'Tip: pick a folder inside iCloud Drive, Dropbox, Syncthing or any synced location to use your vault on more than one device.',
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Center(child: BrandMarkTile(size: 84)),
                const SizedBox(height: 22),
                const Text('Prompt Forge', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'Your prompts and data live in a folder you own, as plain Markdown and JSON files — just like an Obsidian vault. No account, no server, works fully offline.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textSecondary, height: 1.45),
                ),
                const SizedBox(height: 28),
                ...[
                  FilledButton.icon(
                    onPressed: () => _run(() => notifier.createDefaultVault()),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Create a new vault'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _run(() async {
                      await notifier.pickAndOpen();
                    }),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open an existing folder'),
                  ),
                  if (remembered != null) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () => _run(() => notifier.openVault(remembered)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reconnect last folder'),
                    ),
                  ],
                ],
                if (error != null) ...[
                  const SizedBox(height: 18),
                  PfCard(
                    borderColor: p.red.withOpacity(0.5),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.error_outline, color: p.red, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(error, style: TextStyle(color: p.textSecondary, height: 1.4))),
                    ]),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Tip: pick a folder inside iCloud Drive, Dropbox, Syncthing or any synced location to use your vault on more than one device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textTertiary, fontSize: 12.5, height: 1.4),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
