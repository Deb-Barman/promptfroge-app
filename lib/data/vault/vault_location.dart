import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which folder is the vault and helps the user pick or create one.
class VaultLocationService {
  static const _kPath = 'vault_path';
  final SharedPreferences prefs;
  VaultLocationService(this.prefs);

  String? get savedPath => prefs.getString(_kPath);

  Future<void> savePath(String path) => prefs.setString(_kPath, path);

  Future<void> forget() => prefs.remove(_kPath);

  /// Folder created by "Create a new vault": app documents folder (visible in the iOS
  /// Files app when file sharing is enabled; app-specific external storage on Android).
  Future<String> defaultVaultPath() async {
    Directory? base;
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory();
    }
    base ??= await getApplicationDocumentsDirectory();
    return p.join(base.path, 'PromptForge Vault');
  }

  /// Lets the user choose any existing folder. Returns null if cancelled.
  /// On Android 11+ a folder outside the app's own storage needs "All files access".
  Future<String?> pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose your Prompt Forge folder');
    if (path == null) return null;
    if (Platform.isAndroid && !_isAppPrivate(path)) {
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        throw const VaultAccessException(
            'Android needs "All files access" to use a folder outside the app. Grant it in system settings, or use "Create a new vault" instead.');
      }
    }
    return path;
  }

  bool _isAppPrivate(String path) => path.contains('/Android/data/') || path.contains('/app_flutter');

  /// True when we can create the folder (if needed) and write inside it.
  Future<bool> isUsable(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) await dir.create(recursive: true);
      final probe = File(p.join(path, '.pf_write_test'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}

class VaultAccessException implements Exception {
  final String message;
  const VaultAccessException(this.message);
  @override
  String toString() => message;
}
