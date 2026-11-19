import 'dart:io';

import 'package:path/path.dart' as p;

/// Minimal file-system abstraction over the vault folder. All paths are
/// relative to the vault root and use forward slashes.
abstract class VaultFs {
  String get rootPath;
  Future<bool> exists(String rel);
  Future<String?> readString(String rel);
  Future<void> writeString(String rel, String content);
  Future<void> delete(String rel);
  Future<void> deleteDir(String rel);
  Future<void> rename(String from, String to);

  /// Lists files (not directories) directly inside [dir]. Returns relative paths.
  Future<List<String>> listFiles(String dir);

  /// Lists sub-directory names directly inside [dir].
  Future<List<String>> listDirs(String dir);
  Future<void> ensureDir(String rel);
  Future<int> modifiedMs(String rel);
}

class IoVaultFs implements VaultFs {
  @override
  final String rootPath;
  IoVaultFs(this.rootPath);

  String _abs(String rel) => p.joinAll([rootPath, ...rel.split('/').where((e) => e.isNotEmpty)]);

  @override
  Future<bool> exists(String rel) async {
    final path = _abs(rel);
    return await File(path).exists() || await Directory(path).exists();
  }

  @override
  Future<String?> readString(String rel) async {
    final f = File(_abs(rel));
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  /// Atomic-ish write: write to a temp file next to the target, then rename over it.
  @override
  Future<void> writeString(String rel, String content) async {
    final target = File(_abs(rel));
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.pftmp');
    await tmp.writeAsString(content, flush: true);
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      // Some providers can't rename over an existing file: fall back to delete + rename.
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
    }
  }

  @override
  Future<void> delete(String rel) async {
    final f = File(_abs(rel));
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> deleteDir(String rel) async {
    final d = Directory(_abs(rel));
    if (await d.exists()) await d.delete(recursive: true);
  }

  @override
  Future<void> rename(String from, String to) async {
    final src = File(_abs(from));
    if (!await src.exists()) return;
    await File(_abs(to)).parent.create(recursive: true);
    await src.rename(_abs(to));
  }

  @override
  Future<List<String>> listFiles(String dir) async {
    final d = Directory(_abs(dir));
    if (!await d.exists()) return <String>[];
    final out = <String>[];
    await for (final e in d.list(followLinks: false)) {
      if (e is File) {
        final name = p.basename(e.path);
        if (name.endsWith('.pftmp') || name.startsWith('.')) continue;
        out.add(dir.isEmpty ? name : '$dir/$name');
      }
    }
    out.sort();
    return out;
  }

  @override
  Future<List<String>> listDirs(String dir) async {
    final d = Directory(_abs(dir));
    if (!await d.exists()) return <String>[];
    final out = <String>[];
    await for (final e in d.list(followLinks: false)) {
      if (e is Directory) out.add(p.basename(e.path));
    }
    out.sort();
    return out;
  }

  @override
  Future<void> ensureDir(String rel) async {
    await Directory(_abs(rel)).create(recursive: true);
  }

  @override
  Future<int> modifiedMs(String rel) async {
    final f = File(_abs(rel));
    if (!await f.exists()) return 0;
    return (await f.lastModified()).millisecondsSinceEpoch;
  }
}

/// In-memory implementation used by tests (no disk access).
class MemoryVaultFs implements VaultFs {
  final Map<String, String> files = <String, String>{};
  final Set<String> dirs = <String>{};

  @override
  String get rootPath => '/memory';

  @override
  Future<bool> exists(String rel) async => files.containsKey(rel) || dirs.contains(rel) || files.keys.any((k) => k.startsWith('$rel/'));

  @override
  Future<String?> readString(String rel) async => files[rel];

  @override
  Future<void> writeString(String rel, String content) async {
    files[rel] = content;
  }

  @override
  Future<void> delete(String rel) async {
    files.remove(rel);
  }

  @override
  Future<void> deleteDir(String rel) async {
    files.removeWhere((k, _) => k.startsWith('$rel/'));
    dirs.remove(rel);
  }

  @override
  Future<void> rename(String from, String to) async {
    final v = files.remove(from);
    if (v != null) files[to] = v;
  }

  @override
  Future<List<String>> listFiles(String dir) async {
    final prefix = dir.isEmpty ? '' : '$dir/';
    final out = files.keys.where((k) => k.startsWith(prefix) && !k.substring(prefix.length).contains('/') && !k.substring(prefix.length).startsWith('.')).toList();
    out.sort();
    return out;
  }

  @override
  Future<List<String>> listDirs(String dir) async {
    final prefix = dir.isEmpty ? '' : '$dir/';
    final names = <String>{};
    for (final k in files.keys) {
      if (!k.startsWith(prefix)) continue;
      final rest = k.substring(prefix.length);
      final i = rest.indexOf('/');
      if (i > 0) names.add(rest.substring(0, i));
    }
    final out = names.toList()..sort();
    return out;
  }

  @override
  Future<void> ensureDir(String rel) async {
    dirs.add(rel);
  }

  @override
  Future<int> modifiedMs(String rel) async => files.containsKey(rel) ? 1 : 0;
}
