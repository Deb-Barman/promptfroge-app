import 'dart:convert';

import '../../core/util.dart';
import '../../domain/models.dart';
import 'frontmatter.dart';
import 'vault_fs.dart';

const String kPromptsDir = 'Prompts';
const String kTemplatesDir = 'Templates';
const String kPatternsDir = 'Patterns';
const String kSnippetsDir = 'Snippets';
const String kChainsDir = 'Chains';
const String kMetaDir = '.promptforge';
const String kVersionsDir = '.promptforge/versions';

/// Everything loaded from a vault folder.
class VaultData {
  final Map<String, Prompt> prompts;
  final Map<String, Template> templates;
  final Map<String, Snippet> snippets;
  final Map<String, PromptPattern> customPatterns;
  final Map<String, Chain> chains;
  final Map<String, Group> groups;
  final Map<String, SavedSearch> savedSearches;
  final Map<String, BuilderStructure> builderStructures;
  final VaultSettings settings;

  VaultData({
    Map<String, Prompt>? prompts,
    Map<String, Template>? templates,
    Map<String, Snippet>? snippets,
    Map<String, PromptPattern>? customPatterns,
    Map<String, Chain>? chains,
    Map<String, Group>? groups,
    Map<String, SavedSearch>? savedSearches,
    Map<String, BuilderStructure>? builderStructures,
    VaultSettings? settings,
  })  : prompts = prompts ?? <String, Prompt>{},
        templates = templates ?? <String, Template>{},
        snippets = snippets ?? <String, Snippet>{},
        customPatterns = customPatterns ?? <String, PromptPattern>{},
        chains = chains ?? <String, Chain>{},
        groups = groups ?? <String, Group>{},
        savedSearches = savedSearches ?? <String, SavedSearch>{},
        builderStructures = builderStructures ?? <String, BuilderStructure>{},
        settings = settings ?? VaultSettings();

  VaultData copyWith({
    Map<String, Prompt>? prompts,
    Map<String, Template>? templates,
    Map<String, Snippet>? snippets,
    Map<String, PromptPattern>? customPatterns,
    Map<String, Chain>? chains,
    Map<String, Group>? groups,
    Map<String, SavedSearch>? savedSearches,
    Map<String, BuilderStructure>? builderStructures,
    VaultSettings? settings,
  }) =>
      VaultData(
        prompts: prompts ?? this.prompts,
        templates: templates ?? this.templates,
        snippets: snippets ?? this.snippets,
        customPatterns: customPatterns ?? this.customPatterns,
        chains: chains ?? this.chains,
        groups: groups ?? this.groups,
        savedSearches: savedSearches ?? this.savedSearches,
        builderStructures: builderStructures ?? this.builderStructures,
        settings: settings ?? this.settings,
      );
}

/// Reads and writes the vault folder. Every entity is a real file:
///
///   Prompts/<title>.md          frontmatter + prompt body
///   Templates/<name>.md
///   Patterns/<name>.md          user-defined patterns
///   Snippets/<trigger>.md
///   Chains/<name>.md            frontmatter holds the steps, body is the description
///   .promptforge/               app metadata (settings, groups, saved searches, versions)
class VaultRepository {
  final VaultFs fs;
  VaultRepository(this.fs);

  /// id -> relative file path for every loaded file entity.
  final Map<String, String> _pathById = <String, String>{};

  String get rootPath => fs.rootPath;

  Future<void> init() async {
    for (final d in [kPromptsDir, kTemplatesDir, kPatternsDir, kSnippetsDir, kChainsDir, kMetaDir]) {
      await fs.ensureDir(d);
    }
    if (!await fs.exists('$kMetaDir/vault.json')) {
      await fs.writeString(
          '$kMetaDir/vault.json', const JsonEncoder.withIndent('  ').convert({'app': 'prompt-forge', 'schemaVersion': 1, 'createdAt': Utils.nowMs()}));
    }
  }

  // ---------------------------------------------------------------- loading

  Future<VaultData> loadAll() async {
    await init();
    _pathById.clear();
    final data = VaultData();

    final seenIds = <String>{};
    for (final path in await fs.listFiles(kPromptsDir)) {
      if (!path.endsWith('.md')) continue;
      final note = await _readNote(path);
      if (note == null) continue;
      final fallbackTitle = _baseName(path);
      final meta = Map<String, dynamic>.from(note.meta);
      var needsWrite = false;
      if (meta['title'] == null) {
        meta['title'] = fallbackTitle;
        needsWrite = true;
      }
      var prompt = Prompt.fromMap(meta, bodyOverride: note.body, path: path);
      if (meta['id'] == null || seenIds.contains(prompt.id)) {
        if (seenIds.contains(prompt.id)) prompt.id = Utils.uid('pr');
        needsWrite = true;
      }
      seenIds.add(prompt.id);
      _pathById[prompt.id] = path;
      data.prompts[prompt.id] = prompt;
      if (needsWrite) await _writeNote(path, prompt.metaMap(), prompt.body);
    }

    for (final path in await fs.listFiles(kTemplatesDir)) {
      if (!path.endsWith('.md')) continue;
      final note = await _readNote(path);
      if (note == null) continue;
      final meta = Map<String, dynamic>.from(note.meta);
      final noId = meta['id'] == null;
      meta['name'] ??= _baseName(path);
      final t = Template.fromMap(meta, bodyOverride: note.body, path: path);
      if (seenIds.contains(t.id)) t.id = Utils.uid('tpl');
      seenIds.add(t.id);
      _pathById[t.id] = path;
      data.templates[t.id] = t;
      if (noId) await _writeNote(path, t.metaMap(), t.body);
    }

    for (final path in await fs.listFiles(kPatternsDir)) {
      if (!path.endsWith('.md')) continue;
      final note = await _readNote(path);
      if (note == null) continue;
      final meta = Map<String, dynamic>.from(note.meta);
      final noId = meta['id'] == null;
      meta['name'] ??= _baseName(path);
      final pat = PromptPattern.fromMap(meta, bodyOverride: note.body, path: path);
      if (seenIds.contains(pat.id)) pat.id = Utils.uid('cpat');
      seenIds.add(pat.id);
      _pathById[pat.id] = path;
      data.customPatterns[pat.id] = pat;
      if (noId) await _writeNote(path, pat.metaMap(), pat.template);
    }

    for (final path in await fs.listFiles(kSnippetsDir)) {
      if (!path.endsWith('.md')) continue;
      final note = await _readNote(path);
      if (note == null) continue;
      final meta = Map<String, dynamic>.from(note.meta);
      final noId = meta['id'] == null;
      meta['trigger'] ??= '/${_baseName(path)}';
      final s = Snippet.fromMap(meta, bodyOverride: note.body, path: path);
      if (seenIds.contains(s.id)) s.id = Utils.uid('snip');
      seenIds.add(s.id);
      _pathById[s.id] = path;
      data.snippets[s.id] = s;
      if (noId) await _writeNote(path, s.metaMap(), s.body);
    }

    for (final path in await fs.listFiles(kChainsDir)) {
      if (!path.endsWith('.md')) continue;
      final note = await _readNote(path);
      if (note == null) continue;
      final meta = Map<String, dynamic>.from(note.meta);
      final noId = meta['id'] == null;
      meta['name'] ??= _baseName(path);
      meta['description'] = note.body;
      final c = Chain.fromMap(meta, path: path);
      if (seenIds.contains(c.id)) c.id = Utils.uid('chain');
      seenIds.add(c.id);
      _pathById[c.id] = path;
      data.chains[c.id] = c;
      if (noId) await _writeNote(path, _chainMeta(c), c.description);
    }

    for (final g in await _readJsonList('$kMetaDir/groups.json')) {
      final grp = Group.fromMap(g);
      data.groups[grp.id] = grp;
    }
    for (final s in await _readJsonList('$kMetaDir/saved-searches.json')) {
      final ss = SavedSearch.fromMap(s);
      data.savedSearches[ss.id] = ss;
    }
    for (final s in await _readJsonList('$kMetaDir/builder-structures.json')) {
      final bs = BuilderStructure.fromMap(s);
      data.builderStructures[bs.id] = bs;
    }
    final settingsRaw = await fs.readString('$kMetaDir/settings.json');
    VaultSettings settings = VaultSettings();
    if (settingsRaw != null) {
      try {
        settings = VaultSettings.fromMap(Map<String, dynamic>.from(jsonDecode(settingsRaw) as Map));
      } catch (_) {}
    }
    return data.copyWith(settings: settings);
  }

  // --------------------------------------------------------------- prompts

  Future<Prompt> writePrompt(Prompt p) async {
    final path = await _allocate(kPromptsDir, Utils.fileSafe(p.title), p.id, '.md');
    await _writeNote(path, p.metaMap(), p.body);
    await _moveIfRenamed(p.id, path);
    p.path = path;
    _pathById[p.id] = path;
    return p;
  }

  Future<void> removePrompt(String id) async {
    await _removeFile(id);
    await fs.deleteDir('$kVersionsDir/$id');
  }

  // ------------------------------------------------------------- templates

  Future<Template> writeTemplate(Template t) async {
    final path = await _allocate(kTemplatesDir, Utils.fileSafe(t.name), t.id, '.md');
    await _writeNote(path, t.metaMap(), t.body);
    await _moveIfRenamed(t.id, path);
    t.path = path;
    _pathById[t.id] = path;
    return t;
  }

  Future<void> removeTemplate(String id) => _removeFile(id);

  // -------------------------------------------------------------- patterns

  Future<PromptPattern> writePattern(PromptPattern p) async {
    final path = await _allocate(kPatternsDir, Utils.fileSafe(p.name), p.id, '.md');
    await _writeNote(path, p.metaMap(), p.template);
    await _moveIfRenamed(p.id, path);
    p.path = path;
    _pathById[p.id] = path;
    return p;
  }

  Future<void> removePattern(String id) => _removeFile(id);

  // -------------------------------------------------------------- snippets

  Future<Snippet> writeSnippet(Snippet s) async {
    final base = Utils.fileSafe(s.trigger.replaceFirst('/', ''), fallback: 'snippet');
    final path = await _allocate(kSnippetsDir, base, s.id, '.md');
    await _writeNote(path, s.metaMap(), s.body);
    await _moveIfRenamed(s.id, path);
    s.path = path;
    _pathById[s.id] = path;
    return s;
  }

  Future<void> removeSnippet(String id) => _removeFile(id);

  // ---------------------------------------------------------------- chains

  Map<String, dynamic> _chainMeta(Chain c) => {
        'id': c.id,
        'name': c.name,
        'steps': c.steps.map((s) => s.toMap()).toList(),
        'createdAt': c.createdAt,
        'updatedAt': c.updatedAt,
      };

  Future<Chain> writeChain(Chain c) async {
    final path = await _allocate(kChainsDir, Utils.fileSafe(c.name), c.id, '.md');
    await _writeNote(path, _chainMeta(c), c.description);
    await _moveIfRenamed(c.id, path);
    c.path = path;
    _pathById[c.id] = path;
    return c;
  }

  Future<void> removeChain(String id) => _removeFile(id);

  // ------------------------------------------------------------ meta files

  Future<void> writeGroups(Iterable<Group> groups) => _writeJson('$kMetaDir/groups.json', groups.map((g) => g.toMap()).toList());

  Future<void> writeSavedSearches(Iterable<SavedSearch> s) => _writeJson('$kMetaDir/saved-searches.json', s.map((e) => e.toMap()).toList());

  Future<void> writeBuilderStructures(Iterable<BuilderStructure> s) =>
      _writeJson('$kMetaDir/builder-structures.json', s.map((e) => e.toMap()).toList());

  Future<void> writeSettings(VaultSettings s) => _writeJson('$kMetaDir/settings.json', s.toMap());

  // -------------------------------------------------------------- versions

  String _versionPath(String promptId, int num) => '$kVersionsDir/$promptId/v${num.toString().padLeft(5, '0')}.md';

  Future<List<PromptVersion>> listVersions(String promptId) async {
    final out = <PromptVersion>[];
    for (final path in await fs.listFiles('$kVersionsDir/$promptId')) {
      if (!path.endsWith('.md')) continue;
      final note = await _readNote(path);
      if (note == null) continue;
      out.add(PromptVersion.fromMap(note.meta, bodyOverride: note.body));
    }
    out.sort((a, b) => a.versionNum.compareTo(b.versionNum));
    return out;
  }

  Future<void> writeVersion(PromptVersion v) => _writeNote(_versionPath(v.promptId, v.versionNum), v.metaMap(), v.body);

  Future<void> removeVersion(String promptId, int versionNum) => fs.delete(_versionPath(promptId, versionNum));

  // ----------------------------------------------------------------- utils

  Future<ParsedNote?> _readNote(String path) async {
    try {
      final raw = await fs.readString(path);
      if (raw == null) return null;
      return Frontmatter.parse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeNote(String path, Map<String, dynamic> meta, String body) =>
      fs.writeString(path, Frontmatter.serialize(meta, body));

  Future<List<Map<String, dynamic>>> _readJsonList(String path) async {
    final raw = await fs.readString(path);
    if (raw == null) return <Map<String, dynamic>>[];
    try {
      final v = jsonDecode(raw);
      if (v is List) return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  Future<void> _writeJson(String path, Object value) => fs.writeString(path, const JsonEncoder.withIndent('  ').convert(value));

  String _baseName(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// Picks a free file path in [dir] for entity [ownerId]. If the entity already owns
  /// "<base><ext>" that path is reused; otherwise " (2)", " (3)"... is appended.
  Future<String> _allocate(String dir, String base, String ownerId, String ext) async {
    var n = 1;
    while (true) {
      final name = n == 1 ? base : '$base ($n)';
      final path = '$dir/$name$ext';
      final owner = _ownerOf(path);
      if (owner == ownerId) return path;
      if (owner == null && !await fs.exists(path)) return path;
      n++;
      if (n > 500) return '$dir/$base ${Utils.uid()}$ext';
    }
  }

  String? _ownerOf(String path) {
    for (final e in _pathById.entries) {
      if (e.value == path) return e.key;
    }
    return null;
  }

  Future<void> _moveIfRenamed(String id, String newPath) async {
    final old = _pathById[id];
    if (old != null && old != newPath) {
      await fs.delete(old);
    }
  }

  Future<void> _removeFile(String id) async {
    final path = _pathById.remove(id);
    if (path != null) await fs.delete(path);
  }
}
