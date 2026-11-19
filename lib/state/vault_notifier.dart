import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/util.dart';
import '../data/vault/vault_fs.dart';
import '../data/vault/vault_location.dart';
import '../data/vault/vault_repository.dart';
import '../domain/engines/exporter.dart';
import '../domain/engines/importer.dart';
import '../domain/engines/search_engine.dart';
import '../domain/models.dart';
import 'device_settings.dart';

enum VaultStatus { none, loading, ready, error }

class VaultState {
  final VaultStatus status;
  final VaultData data;
  final String? rootPath;
  final String? error;

  /// Bumped on every change so cheap "did anything change" checks are possible.
  final int revision;

  VaultState({this.status = VaultStatus.none, VaultData? data, this.rootPath, this.error, this.revision = 0}) : data = data ?? VaultData();

  bool get isReady => status == VaultStatus.ready;
}

class RestoreSummary {
  final Map<String, int> counts;
  const RestoreSummary(this.counts);
}

/// Single source of truth for everything stored in the vault folder.
class VaultNotifier extends Notifier<VaultState> {
  VaultRepository? _repo;

  @override
  VaultState build() => VaultState();

  VaultLocationService get location => VaultLocationService(ref.read(sharedPrefsProvider));

  VaultData get _d => state.data;

  void _emit(VaultData d) {
    state = VaultState(status: VaultStatus.ready, data: d, rootPath: state.rootPath, revision: state.revision + 1);
  }

  // ----------------------------------------------------------- open / close

  /// Opens the previously used vault, if there is one and it is still accessible.
  Future<void> bootstrap() async {
    final path = location.savedPath;
    if (path == null) return;
    await openVault(path, remember: false);
  }

  Future<void> createDefaultVault() async {
    final path = await location.defaultVaultPath();
    await openVault(path);
  }

  /// Returns false if the user cancelled the picker. Throws [VaultAccessException] when access is denied.
  Future<bool> pickAndOpen() async {
    final path = await location.pickFolder();
    if (path == null) return false;
    await openVault(path);
    return true;
  }

  Future<void> openVault(String path, {bool remember = true}) async {
    state = VaultState(status: VaultStatus.loading, rootPath: path, revision: state.revision);
    try {
      if (!await location.isUsable(path)) {
        throw VaultAccessException('Cannot write to "$path". Pick the folder again or create a new vault.');
      }
      final repo = VaultRepository(IoVaultFs(path));
      final data = await repo.loadAll();
      _repo = repo;
      if (remember) await location.savePath(path);
      state = VaultState(status: VaultStatus.ready, data: data, rootPath: path, revision: state.revision + 1);
    } catch (e) {
      _repo = null;
      state = VaultState(status: VaultStatus.error, rootPath: path, error: e.toString(), revision: state.revision + 1);
    }
  }

  /// Test hook: use an in-memory file system.
  Future<void> openWithFs(VaultFs fs) async {
    final repo = VaultRepository(fs);
    final data = await repo.loadAll();
    _repo = repo;
    state = VaultState(status: VaultStatus.ready, data: data, rootPath: fs.rootPath, revision: state.revision + 1);
  }

  /// Re-reads the folder (picks up files changed outside the app, like Obsidian does).
  Future<void> rescan() async {
    final repo = _repo;
    if (repo == null) return;
    final data = await repo.loadAll();
    _emit(data);
  }

  Future<void> closeVault() async {
    await location.forget();
    _repo = null;
    state = VaultState(revision: state.revision + 1);
  }

  VaultRepository get _r {
    final r = _repo;
    if (r == null) throw StateError('No vault is open');
    return r;
  }

  // ---------------------------------------------------------------- prompts

  Prompt newPrompt({String title = '', String body = '', String category = 'custom', List<String>? tags, String format = 'text', List<PromptBlock>? blocks}) =>
      Prompt(title: title, body: body, category: category, tags: tags, format: format, blocks: blocks);

  Prompt? prompt(String id) => _d.prompts[id];

  /// Writes the prompt file and returns the stored copy. [touch] updates `updatedAt`.
  Future<Prompt> savePrompt(Prompt p, {bool touch = true}) async {
    final copy = p.clone();
    copy.title = Utils.truncate(copy.title, 200);
    if (touch) copy.updatedAt = Utils.nowMs();
    await _r.writePrompt(copy);
    final map = Map<String, Prompt>.of(_d.prompts)..[copy.id] = copy;
    _emit(_d.copyWith(prompts: map));
    return copy;
  }

  Future<void> deletePrompt(String id) async {
    await _r.removePrompt(id);
    final map = Map<String, Prompt>.of(_d.prompts)..remove(id);
    final groups = _stripFromGroups({id});
    _emit(_d.copyWith(prompts: map, groups: groups));
    await _r.writeGroups(groups.values);
  }

  Map<String, Group> _stripFromGroups(Set<String> ids) {
    final out = <String, Group>{};
    for (final g in _d.groups.values) {
      final c = g.clone()..memberIds.removeWhere(ids.contains);
      out[c.id] = c;
    }
    return out;
  }

  Future<Prompt> duplicatePrompt(String id) async {
    final src = _d.prompts[id];
    if (src == null) throw StateError('Prompt not found');
    final c = src.clone()
      ..id = Utils.uid('pr')
      ..title = '${src.displayTitle} (copy)'
      ..path = null
      ..currentVersion = 1
      ..useCount = 0
      ..favorite = false
      ..pinned = false
      ..bestOf = false
      ..createdAt = Utils.nowMs();
    return savePrompt(c);
  }

  Future<void> _mutate(String id, void Function(Prompt p) fn, {bool touch = false}) async {
    final p = _d.prompts[id];
    if (p == null) return;
    final c = p.clone();
    fn(c);
    await savePrompt(c, touch: touch);
  }

  Future<void> toggleFavorite(String id) => _mutate(id, (p) => p.favorite = !p.favorite);
  Future<void> togglePinned(String id) => _mutate(id, (p) => p.pinned = !p.pinned);
  Future<void> toggleBestOf(String id) => _mutate(id, (p) => p.bestOf = !p.bestOf);
  Future<void> setArchived(String id, bool v) => _mutate(id, (p) => p.archived = v);
  Future<void> setStatus(String id, String status) => _mutate(id, (p) => p.status = status);
  Future<void> incrementUse(String id) => _mutate(id, (p) => p.useCount++);
  Future<void> flagRevisit(String id, String note) => _mutate(id, (p) => p.needsRevisit = NeedsRevisit(note: note, flaggedAt: Utils.nowMs()));
  Future<void> clearRevisit(String id) => _mutate(id, (p) => p.needsRevisit = null);
  Future<void> setEdgeCheck(String id, String checkId, bool on) => _mutate(id, (p) {
        if (on) {
          p.edgeCaseChecks[checkId] = true;
        } else {
          p.edgeCaseChecks.remove(checkId);
        }
      });

  Future<void> bulkSetArchived(Iterable<String> ids, bool v) async {
    for (final id in ids) {
      await setArchived(id, v);
    }
  }

  Future<void> bulkDelete(Iterable<String> ids) async {
    for (final id in ids.toList()) {
      await deletePrompt(id);
    }
  }

  Future<void> bulkAddTag(Iterable<String> ids, String tag) async {
    final t = tag.trim().replaceFirst('#', '');
    if (t.isEmpty) return;
    for (final id in ids) {
      await _mutate(id, (p) {
        if (!p.tags.contains(t)) p.tags.add(t);
      });
    }
  }

  Future<void> bulkSetCategory(Iterable<String> ids, String category) async {
    for (final id in ids) {
      await _mutate(id, (p) => p.category = category);
    }
  }

  Future<void> bulkSetStatus(Iterable<String> ids, String status) async {
    for (final id in ids) {
      await setStatus(id, status);
    }
  }

  // --------------------------------------------------------------- versions

  Future<List<PromptVersion>> versionsOf(String promptId) => _r.listVersions(promptId);

  /// Snapshots the stored prompt as the next version (same rules as the HTML app).
  Future<PromptVersion?> createVersion(String promptId, {String note = ''}) async {
    final p = _d.prompts[promptId];
    if (p == null) return null;
    final existing = await _r.listVersions(promptId);
    final next = existing.isEmpty ? 1 : existing.last.versionNum + 1;
    final v = PromptVersion(promptId: promptId, versionNum: next, title: p.title, body: p.body, note: note.trim());
    await _r.writeVersion(v);
    final c = p.clone()..currentVersion = next;
    await savePrompt(c);
    final all = [...existing, v];
    final limit = _d.settings.versionRetention;
    if (limit > 0 && all.length > limit) {
      for (final old in all.sublist(0, all.length - limit)) {
        await _r.removeVersion(promptId, old.versionNum);
      }
    }
    return v;
  }

  Future<Prompt?> restoreVersion(String promptId, int versionNum) async {
    final versions = await _r.listVersions(promptId);
    PromptVersion? v;
    for (final x in versions) {
      if (x.versionNum == versionNum) v = x;
    }
    final p = _d.prompts[promptId];
    if (v == null || p == null) return null;
    // Never lose the current text: snapshot it first unless it already equals the latest version.
    if (versions.isEmpty || versions.last.body != p.body) {
      await createVersion(promptId, note: 'Before restoring v$versionNum');
    }
    final c = _d.prompts[promptId]!.clone()
      ..body = v.body
      ..title = v.title;
    await savePrompt(c);
    await createVersion(promptId, note: 'Restored from v$versionNum');
    return _d.prompts[promptId];
  }

  Future<void> deleteVersion(String promptId, int versionNum) => _r.removeVersion(promptId, versionNum);

  // -------------------------------------------------------------- templates

  Future<Template> saveTemplate(Template t) async {
    final c = t.clone()..updatedAt = Utils.nowMs();
    await _r.writeTemplate(c);
    _emit(_d.copyWith(templates: Map<String, Template>.of(_d.templates)..[c.id] = c));
    return c;
  }

  Future<void> deleteTemplate(String id) async {
    await _r.removeTemplate(id);
    final groups = _stripFromGroups({id});
    _emit(_d.copyWith(templates: Map<String, Template>.of(_d.templates)..remove(id), groups: groups));
    await _r.writeGroups(groups.values);
  }

  Future<void> incrementTemplateUse(String id) async {
    final t = _d.templates[id];
    if (t == null) return;
    final c = t.clone();
    c.useCount++;
    await _r.writeTemplate(c);
    _emit(_d.copyWith(templates: Map<String, Template>.of(_d.templates)..[c.id] = c));
  }

  // --------------------------------------------------------------- snippets

  Future<Snippet> saveSnippet(Snippet s) async {
    final c = s.clone()..updatedAt = Utils.nowMs();
    if (!c.trigger.startsWith('/')) c.trigger = '/${c.trigger}';
    await _r.writeSnippet(c);
    _emit(_d.copyWith(snippets: Map<String, Snippet>.of(_d.snippets)..[c.id] = c));
    return c;
  }

  Future<void> deleteSnippet(String id) async {
    await _r.removeSnippet(id);
    _emit(_d.copyWith(snippets: Map<String, Snippet>.of(_d.snippets)..remove(id)));
  }

  // --------------------------------------------------------------- patterns

  Future<PromptPattern> savePattern(PromptPattern p) async {
    final c = p.clone()
      ..builtin = false
      ..updatedAt = Utils.nowMs();
    await _r.writePattern(c);
    _emit(_d.copyWith(customPatterns: Map<String, PromptPattern>.of(_d.customPatterns)..[c.id] = c));
    return c;
  }

  Future<void> deletePattern(String id) async {
    await _r.removePattern(id);
    final groups = _stripFromGroups({id});
    _emit(_d.copyWith(customPatterns: Map<String, PromptPattern>.of(_d.customPatterns)..remove(id), groups: groups));
    await _r.writeGroups(groups.values);
  }

  // ----------------------------------------------------------------- chains

  Future<Chain> saveChain(Chain c) async {
    final copy = c.clone()..updatedAt = Utils.nowMs();
    await _r.writeChain(copy);
    _emit(_d.copyWith(chains: Map<String, Chain>.of(_d.chains)..[copy.id] = copy));
    return copy;
  }

  Future<void> deleteChain(String id) async {
    await _r.removeChain(id);
    _emit(_d.copyWith(chains: Map<String, Chain>.of(_d.chains)..remove(id)));
  }

  // ----------------------------------------------------------------- groups

  Future<Group> saveGroup(Group g) async {
    final c = g.clone()..updatedAt = Utils.nowMs();
    final map = Map<String, Group>.of(_d.groups)..[c.id] = c;
    _emit(_d.copyWith(groups: map));
    await _r.writeGroups(map.values);
    return c;
  }

  Future<void> deleteGroup(String id) async {
    final map = Map<String, Group>.of(_d.groups)..remove(id);
    _emit(_d.copyWith(groups: map));
    await _r.writeGroups(map.values);
  }

  Future<void> setGroupMembership(String groupId, String itemId, bool member) async {
    final g = _d.groups[groupId];
    if (g == null) return;
    final c = g.clone();
    if (member) {
      if (!c.memberIds.contains(itemId)) c.memberIds.add(itemId);
    } else {
      c.memberIds.remove(itemId);
    }
    await saveGroup(c);
  }

  // --------------------------------------------------------- saved searches

  Future<SavedSearch> saveSearch(SavedSearch s) async {
    final map = Map<String, SavedSearch>.of(_d.savedSearches)..[s.id] = s;
    _emit(_d.copyWith(savedSearches: map));
    await _r.writeSavedSearches(map.values);
    return s;
  }

  Future<void> deleteSearch(String id) async {
    final map = Map<String, SavedSearch>.of(_d.savedSearches)..remove(id);
    _emit(_d.copyWith(savedSearches: map));
    await _r.writeSavedSearches(map.values);
  }

  // ----------------------------------------------------- builder structures

  Future<BuilderStructure> saveStructure(BuilderStructure s) async {
    s.updatedAt = Utils.nowMs();
    final map = Map<String, BuilderStructure>.of(_d.builderStructures)..[s.id] = s;
    _emit(_d.copyWith(builderStructures: map));
    await _r.writeBuilderStructures(map.values);
    return s;
  }

  Future<void> deleteStructure(String id) async {
    final map = Map<String, BuilderStructure>.of(_d.builderStructures)..remove(id);
    _emit(_d.copyWith(builderStructures: map));
    await _r.writeBuilderStructures(map.values);
  }

  // --------------------------------------------------------------- settings

  Future<void> updateSettings(VaultSettings s) async {
    _emit(_d.copyWith(settings: s));
    await _r.writeSettings(s);
  }

  // ------------------------------------------------------------- clear data

  /// Deletes everything of one kind (the original's "Clear …" buttons). Returns how many items were removed.
  /// kind: prompts | templates | patterns | snippets | chains | groups | history | searches | structures
  Future<int> clearData(String kind) async {
    switch (kind) {
      case 'prompts':
        final ids = _d.prompts.keys.toList();
        await bulkDelete(ids);
        return ids.length;
      case 'templates':
        final ids = _d.templates.keys.toList();
        for (final id in ids) {
          await deleteTemplate(id);
        }
        return ids.length;
      case 'patterns':
        final ids = _d.customPatterns.keys.toList();
        for (final id in ids) {
          await deletePattern(id);
        }
        return ids.length;
      case 'snippets':
        final ids = _d.snippets.keys.toList();
        for (final id in ids) {
          await deleteSnippet(id);
        }
        return ids.length;
      case 'chains':
        final ids = _d.chains.keys.toList();
        for (final id in ids) {
          await deleteChain(id);
        }
        return ids.length;
      case 'groups':
        final ids = _d.groups.keys.toList();
        for (final id in ids) {
          await deleteGroup(id);
        }
        return ids.length;
      case 'searches':
        final ids = _d.savedSearches.keys.toList();
        for (final id in ids) {
          await deleteSearch(id);
        }
        return ids.length;
      case 'structures':
        final ids = _d.builderStructures.keys.toList();
        for (final id in ids) {
          await deleteStructure(id);
        }
        return ids.length;
      case 'history':
        var n = 0;
        for (final e in (await allVersions()).entries) {
          for (final v in e.value) {
            await deleteVersion(e.key, v.versionNum);
            n++;
          }
        }
        return n;
    }
    return 0;
  }

  /// Everything above plus Learn progress. The folder itself and your settings stay.
  Future<int> clearEverything() async {
    var n = 0;
    // History first: it is keyed by prompt id, which disappears once prompts are deleted.
    for (final k in const ['history', 'prompts', 'templates', 'patterns', 'snippets', 'chains', 'groups', 'searches', 'structures']) {
      n += await clearData(k);
    }
    await updateSettings(_d.settings.clone()
      ..challengeProgress = <String, bool>{}
      ..challengeAttempts = <String, ChallengeAttempt>{});
    return n;
  }

  // ------------------------------------------------------- backup / restore

  Future<String> exportFullBackup() async {
    final versions = <PromptVersion>[];
    for (final id in _d.prompts.keys) {
      versions.addAll(await _r.listVersions(id));
    }
    return Exporter.fullBackupJson(_d, versions);
  }

  Future<Map<String, List<PromptVersion>>> allVersions() async {
    final out = <String, List<PromptVersion>>{};
    for (final id in _d.prompts.keys) {
      out[id] = await _r.listVersions(id);
    }
    return out;
  }

  /// Restores a parsed backup into the vault folder as real files.
  /// [replace] deletes all existing prompts, templates, patterns, snippets and chains first.
  Future<RestoreSummary> restoreBackup(BackupContents c, {required bool replace}) async {
    if (replace) {
      for (final id in _d.prompts.keys.toList()) {
        await _r.removePrompt(id);
      }
      for (final id in _d.templates.keys.toList()) {
        await _r.removeTemplate(id);
      }
      for (final id in _d.customPatterns.keys.toList()) {
        await _r.removePattern(id);
      }
      for (final id in _d.snippets.keys.toList()) {
        await _r.removeSnippet(id);
      }
      for (final id in _d.chains.keys.toList()) {
        await _r.removeChain(id);
      }
    }
    final base = replace ? VaultData(settings: _d.settings) : _d;
    final prompts = Map<String, Prompt>.of(base.prompts);
    final templates = Map<String, Template>.of(base.templates);
    final snippets = Map<String, Snippet>.of(base.snippets);
    final patterns = Map<String, PromptPattern>.of(base.customPatterns);
    final chains = Map<String, Chain>.of(base.chains);
    final groups = Map<String, Group>.of(replace ? <String, Group>{} : base.groups);
    final searches = Map<String, SavedSearch>.of(replace ? <String, SavedSearch>{} : base.savedSearches);
    final structs = Map<String, BuilderStructure>.of(replace ? <String, BuilderStructure>{} : base.builderStructures);

    for (final p in c.data.prompts.values) {
      final existing = prompts[p.id];
      if (existing != null) p.path = existing.path;
      await _r.writePrompt(p);
      prompts[p.id] = p;
    }
    for (final t in c.data.templates.values) {
      await _r.writeTemplate(t);
      templates[t.id] = t;
    }
    for (final s in c.data.snippets.values) {
      await _r.writeSnippet(s);
      snippets[s.id] = s;
    }
    for (final p in c.data.customPatterns.values) {
      await _r.writePattern(p);
      patterns[p.id] = p;
    }
    for (final ch in c.data.chains.values) {
      await _r.writeChain(ch);
      chains[ch.id] = ch;
    }
    groups.addAll(c.data.groups);
    searches.addAll(c.data.savedSearches);
    structs.addAll(c.data.builderStructures);
    for (final v in c.versions) {
      await _r.writeVersion(v);
    }

    // settings: custom models merge by id, scalars come from the backup, progress merges.
    final cur = _d.settings.clone();
    final byId = <String, CustomModel>{for (final m in replace ? <CustomModel>[] : cur.customModels) m.id: m};
    for (final m in c.data.settings.customModels) {
      byId[m.id] = m;
    }
    cur.customModels = byId.values.toList();
    cur.selectedModel = c.data.settings.selectedModel;
    cur.scoringProfile = c.data.settings.scoringProfile;
    cur.challengeProgress = {...(replace ? <String, bool>{} : cur.challengeProgress), ...c.data.settings.challengeProgress};
    cur.challengeAttempts = {...(replace ? <String, ChallengeAttempt>{} : cur.challengeAttempts), ...c.data.settings.challengeAttempts};
    cur.volumeCallsPerMonth = c.data.settings.volumeCallsPerMonth;
    cur.defaultCategory = c.data.settings.defaultCategory;

    await _r.writeGroups(groups.values);
    await _r.writeSavedSearches(searches.values);
    await _r.writeBuilderStructures(structs.values);
    await _r.writeSettings(cur);

    _emit(VaultData(
      prompts: prompts,
      templates: templates,
      snippets: snippets,
      customPatterns: patterns,
      chains: chains,
      groups: groups,
      savedSearches: searches,
      builderStructures: structs,
      settings: cur,
    ));
    return RestoreSummary(c.counts);
  }

  /// Imports parsed JSON records (prompts / templates / patterns) as new files.
  Future<int> importRecords({List<Prompt> prompts = const [], List<Template> templates = const [], List<PromptPattern> patterns = const []}) async {
    for (final p in prompts) {
      await savePrompt(p);
    }
    for (final t in templates) {
      await saveTemplate(t);
    }
    for (final p in patterns) {
      await savePattern(p);
    }
    return prompts.length + templates.length + patterns.length;
  }
}

final vaultProvider = NotifierProvider<VaultNotifier, VaultState>(VaultNotifier.new);

/// Cheap, lazily rebuilt phrase-suggestion model over the current vault.
class SuggestionHub {
  final SuggestionEngine engine = SuggestionEngine();
  int _rev = -1;

  SuggestionEngine fresh(VaultState s) {
    if (_rev != s.revision) {
      engine.rebuild(s.data);
      _rev = s.revision;
    }
    return engine;
  }
}

final suggestionHubProvider = Provider<SuggestionHub>((ref) => SuggestionHub());
