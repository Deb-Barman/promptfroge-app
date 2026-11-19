import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

/// Writes [content] to `<vault>/Exports/<name>` (so exports live in the vault folder too).
Future<File> saveExportFile(String vaultRoot, String name, String content) async {
  final dir = Directory(p.join(vaultRoot, 'Exports'));
  await dir.create(recursive: true);
  final f = File(p.join(dir.path, name));
  await f.writeAsString(content, flush: true);
  return f;
}

Future<void> shareFilePath(String path, {String? text}) async {
  await Share.shareXFiles([XFile(path)], text: text);
}

String exportStamp() {
  final d = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}
