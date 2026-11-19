import 'dart:convert';
import 'dart:io';

/// Goldens are produced by running the ORIGINAL JavaScript (tool/golden/gen_goldens.js).
/// They are never hand-edited; regenerate with:
///   node tool/golden/gen_goldens.js path/to/PromptForge.html > test/goldens/engines.json
class Goldens {
  Goldens._(this.fixtures, this.results);
  final Map<String, dynamic> fixtures;
  final Map<String, dynamic> results;

  static Goldens? _cached;

  static Goldens load() {
    if (_cached != null) return _cached!;
    final f = File('test/goldens/engines.json');
    if (!f.existsSync()) {
      throw StateError('test/goldens/engines.json is missing - run tool/golden/gen_goldens.js (see tool/golden/README.md).');
    }
    final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return _cached = Goldens._(m['fixtures'] as Map<String, dynamic>, m['results'] as Map<String, dynamic>);
  }

  List<String> get prompts => (fixtures['prompts'] as List).cast<String>();
  List<dynamic> list(String key) => results[key] as List<dynamic>;
  dynamic operator [](String key) => results[key];
}
