import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_forge/data/vault/vault_fs.dart';
import 'package:prompt_forge/data/vault/vault_repository.dart';
import 'package:prompt_forge/domain/engines/exporter.dart';
import 'package:prompt_forge/domain/engines/importer.dart';
import 'package:prompt_forge/domain/models.dart';
import 'package:prompt_forge/state/vault_notifier.dart';

void main() {
  late ProviderContainer c;
  late MemoryVaultFs fs;
  late VaultNotifier n;

  setUp(() async {
    c = ProviderContainer();
    addTearDown(c.dispose);
    fs = MemoryVaultFs();
    n = c.read(vaultProvider.notifier);
    await n.openWithFs(fs);
  });

  VaultState s() => c.read(vaultProvider);

  test('opens an empty vault as ready', () {
    expect(s().isReady, isTrue);
    expect(s().data.prompts, isEmpty);
  });

  test('savePrompt writes a file and updates state', () async {
    final p = await n.savePrompt(Prompt(title: 'Hello', body: 'World'));
    expect(s().data.prompts[p.id]!.body, 'World');
    expect(fs.files.keys, contains('$kPromptsDir/Hello.md'));
    expect(s().revision, greaterThan(1));
  });

  test('toggles and counters persist to disk', () async {
    final p = await n.savePrompt(Prompt(title: 'T', body: 'b'));
    await n.toggleFavorite(p.id);
    await n.togglePinned(p.id);
    await n.incrementUse(p.id);
    await n.flagRevisit(p.id, 'check tone');
    final reloaded = (await VaultRepository(fs).loadAll()).prompts[p.id]!;
    expect(reloaded.favorite, isTrue);
    expect(reloaded.pinned, isTrue);
    expect(reloaded.useCount, 1);
    expect(reloaded.needsRevisit?.note, 'check tone');
    await n.clearRevisit(p.id);
    expect(s().data.prompts[p.id]!.needsRevisit, isNull);
  });

  test('duplicate creates an independent copy', () async {
    final p = await n.savePrompt(Prompt(title: 'Original', body: 'text'));
    final copy = await n.duplicatePrompt(p.id);
    expect(copy.id, isNot(p.id));
    expect(copy.body, 'text');
    expect(s().data.prompts.length, 2);
    expect(fs.files.keys.where((k) => k.startsWith('$kPromptsDir/')).length, 2);
  });

  test('delete removes the file and its versions', () async {
    final p = await n.savePrompt(Prompt(title: 'Gone', body: 'x'));
    await n.createVersion(p.id, note: 'v');
    await n.deletePrompt(p.id);
    expect(s().data.prompts, isEmpty);
    expect(fs.files.keys.where((k) => k.startsWith('$kPromptsDir/') || k.startsWith(kVersionsDir)), isEmpty);
  });

  test('versions: create, restore (snapshots current text first), delete', () async {
    final p = await n.savePrompt(Prompt(title: 'V', body: 'first'));
    final v1 = await n.createVersion(p.id, note: 'one');
    expect(v1, isNotNull);
    await n.savePrompt(s().data.prompts[p.id]!.clone()..body = 'second');
    await n.createVersion(p.id, note: 'two');
    // unsaved-as-version edit that a restore must not destroy
    await n.savePrompt(s().data.prompts[p.id]!.clone()..body = 'third');
    await n.restoreVersion(p.id, v1!.versionNum);
    expect(s().data.prompts[p.id]!.body, 'first');
    final versions = await n.versionsOf(p.id);
    expect(versions.any((v) => v.body == 'third'), isTrue, reason: 'pre-restore text must be kept as a version');
    expect(versions.any((v) => v.body == 'second'), isTrue);
    expect(versions.last.note, startsWith('Restored from'));
    final before = versions.length;
    await n.deleteVersion(p.id, versions.first.versionNum);
    expect((await n.versionsOf(p.id)).length, before - 1);
  });

  test('version retention trims the oldest snapshots', () async {
    await n.updateSettings(s().data.settings.clone()..versionRetention = 3);
    final p = await n.savePrompt(Prompt(title: 'R', body: '0'));
    for (var i = 1; i <= 6; i++) {
      await n.savePrompt(s().data.prompts[p.id]!.clone()..body = '$i');
      await n.createVersion(p.id, note: 'n$i');
    }
    final versions = await n.versionsOf(p.id);
    expect(versions.length, 3);
    expect(versions.last.body, '6');
  });

  test('bulk operations', () async {
    final a = await n.savePrompt(Prompt(title: 'A', body: 'a'));
    final b = await n.savePrompt(Prompt(title: 'B', body: 'b'));
    await n.bulkAddTag([a.id, b.id], 'work');
    await n.bulkSetCategory([a.id], 'coding');
    await n.bulkSetStatus([b.id], 'final');
    await n.bulkSetArchived([a.id], true);
    expect(s().data.prompts[a.id]!.tags, contains('work'));
    expect(s().data.prompts[a.id]!.category, 'coding');
    expect(s().data.prompts[b.id]!.status, 'final');
    expect(s().data.prompts[a.id]!.archived, isTrue);
    await n.bulkDelete([a.id, b.id]);
    expect(s().data.prompts, isEmpty);
  });

  test('groups and saved searches', () async {
    final p = await n.savePrompt(Prompt(title: 'G', body: 'g'));
    final g = await n.saveGroup(Group(kind: 'library', name: 'Work'));
    await n.setGroupMembership(g.id, p.id, true);
    expect(s().data.groups[g.id]!.memberIds, [p.id]);
    await n.setGroupMembership(g.id, p.id, false);
    expect(s().data.groups[g.id]!.memberIds, isEmpty);
    final ss = await n.saveSearch(SavedSearch(name: 'S', query: 'q'));
    expect((await VaultRepository(fs).loadAll()).savedSearches.keys, contains(ss.id));
    await n.deleteSearch(ss.id);
    await n.deleteGroup(g.id);
    expect(s().data.groups, isEmpty);
  });

  test('rescan picks up files changed outside the app (Obsidian-style)', () async {
    final p = await n.savePrompt(Prompt(title: 'Shared', body: 'before'));
    final path = '$kPromptsDir/Shared.md';
    fs.files[path] = fs.files[path]!.replaceFirst('before', 'edited elsewhere');
    fs.files['$kPromptsDir/New from desktop.md'] = 'created outside';
    await n.rescan();
    expect(s().data.prompts[p.id]!.body, 'edited elsewhere');
    expect(s().data.prompts.values.any((x) => x.title == 'New from desktop'), isTrue);
    fs.files.remove(path);
    await n.rescan();
    expect(s().data.prompts.containsKey(p.id), isFalse);
  });

  test('full backup round-trips (merge and replace)', () async {
    final p = await n.savePrompt(Prompt(title: 'Backed up', body: 'precious', tags: ['x']));
    await n.createVersion(p.id, note: 'snap');
    await n.saveTemplate(Template(name: 'Tpl', body: 'Hi {{a}}'));
    final json = await n.exportFullBackup();

    final other = ProviderContainer();
    addTearDown(other.dispose);
    final on = other.read(vaultProvider.notifier);
    await on.openWithFs(MemoryVaultFs());
    final contents = BackupParser.parse(json)!;
    expect(contents.counts['prompts'], 1);
    await on.restoreBackup(contents, replace: false);
    final d = other.read(vaultProvider).data;
    expect(d.prompts[p.id]!.body, 'precious');
    expect(d.prompts[p.id]!.tags, ['x']);
    expect(d.templates.length, 1);
    expect((await on.versionsOf(p.id)).length, 1);

    await on.savePrompt(Prompt(title: 'Extra', body: 'e'));
    await on.restoreBackup(contents, replace: true);
    expect(other.read(vaultProvider).data.prompts.length, 1);
  });

  test('exporting produces readable files in every format', () async {
    final p = await n.savePrompt(Prompt(title: 'Exp', body: 'Body text with, comma and "quotes"'));
    final items = Exporter.collect(s().data, {'prompts'});
    expect(items.length, 1);
    expect(Exporter.toMarkdown(items), contains('Body text'));
    expect(Exporter.toTxt(items), contains('Exp'));
    expect(Exporter.toCsv(items), contains('Exp'));
    expect(Exporter.toHtml(items), contains('&quot;quotes&quot;'));
    for (final f in ['txt', 'md', 'json', 'html']) {
      expect(Exporter.promptToFormat(p, f), isNotEmpty);
    }
  });

  test('importRecords creates real files', () async {
    final recs = JsonImporter.parse('[{"title":"From JSON","content":"hello"},{"name":"Second","text":"world"}]', 'prompt');
    final count = await n.importRecords(prompts: recs.map(JsonImporter.toPrompt).toList());
    expect(count, 2);
    expect(fs.files.keys.where((k) => k.startsWith('$kPromptsDir/')).length, 2);
  });

  test('invalid import JSON gives a friendly error', () {
    expect(() => JsonImporter.parse('{oops', 'prompt'), throwsA(isA<ImportException>()));
    expect(() => BackupParser.parse('[1,2]'), throwsA(isA<ImportException>()));
  });

  test('the HTML app backup shape is accepted', () {
    const legacy = '{"prompts":[{"id":"pr_old","title":"Legacy","body":"old body","category":"writing","tags":["a"],"favorite":true,"createdAt":1700000000000,"updatedAt":1700000100000}],'
        '"history":[],"templates":[],"_settings":{"selectedModel":"gpt4o","challengeProgress":{"c1":{"solved":true,"score":80,"answer":"x"},"c2":{"solved":false}}}}';
    final c = BackupParser.parse(legacy)!;
    expect(c.data.prompts['pr_old']!.title, 'Legacy');
    expect(c.data.prompts['pr_old']!.favorite, isTrue);
    expect(c.data.settings.selectedModel, 'gpt4o');
    expect(c.data.settings.challengeProgress, {'c1': true});
  });
}
