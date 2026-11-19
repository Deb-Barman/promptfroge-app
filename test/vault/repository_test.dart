import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_forge/data/vault/vault_fs.dart';
import 'package:prompt_forge/data/vault/vault_repository.dart';
import 'package:prompt_forge/domain/models.dart';

void main() {
  late MemoryVaultFs fs;
  late VaultRepository repo;

  setUp(() async {
    fs = MemoryVaultFs();
    repo = VaultRepository(fs);
    await repo.init();
  });

  test('init creates the vault skeleton', () async {
    expect(fs.files.containsKey('$kMetaDir/vault.json'), isTrue);
  });

  test('a prompt is a real Markdown file named after its title', () async {
    await repo.writePrompt(Prompt(id: 'p1', title: 'Weekly report', body: 'Summarize the week.'));
    expect(fs.files.keys, contains('$kPromptsDir/Weekly report.md'));
    final raw = fs.files['$kPromptsDir/Weekly report.md']!;
    expect(raw.startsWith('---\n'), isTrue);
    expect(raw.contains('Summarize the week.'), isTrue);
    final data = await VaultRepository(fs).loadAll();
    expect(data.prompts['p1']!.title, 'Weekly report');
    expect(data.prompts['p1']!.body, 'Summarize the week.');
  });

  test('renaming moves the file and never leaves two copies', () async {
    final p = Prompt(id: 'p1', title: 'Old name', body: 'x');
    await repo.writePrompt(p);
    p.title = 'New name';
    await repo.writePrompt(p);
    final names = fs.files.keys.where((k) => k.startsWith('$kPromptsDir/')).toList();
    expect(names, ['$kPromptsDir/New name.md']);
  });

  test('two prompts with the same title get distinct files', () async {
    await repo.writePrompt(Prompt(id: 'a', title: 'Same', body: '1'));
    await repo.writePrompt(Prompt(id: 'b', title: 'Same', body: '2'));
    expect(fs.files.keys, containsAll(['$kPromptsDir/Same.md', '$kPromptsDir/Same (2).md']));
    final data = await VaultRepository(fs).loadAll();
    expect(data.prompts.length, 2);
    expect(data.prompts['a']!.body, '1');
    expect(data.prompts['b']!.body, '2');
  });

  test('unsafe characters in titles do not break file names', () async {
    await repo.writePrompt(Prompt(id: 'a', title: 'a/b:c*?"<>|d', body: '1'));
    final name = fs.files.keys.firstWhere((k) => k.startsWith('$kPromptsDir/'));
    expect(name.substring(kPromptsDir.length + 1).contains(RegExp(r'[/\\:*?"<>|]')), isFalse);
  });

  test('a plain .md file dropped into the folder becomes a prompt and gets an id', () async {
    fs.files['$kPromptsDir/Dropped note.md'] = 'Just some text I wrote in Obsidian.';
    final data = await VaultRepository(fs).loadAll();
    expect(data.prompts.length, 1);
    final p = data.prompts.values.single;
    expect(p.title, 'Dropped note');
    expect(p.body, 'Just some text I wrote in Obsidian.');
    // the id was written back so it is stable next time
    final again = await VaultRepository(fs).loadAll();
    expect(again.prompts.keys.single, p.id);
  });

  test('duplicate ids (copied file) are repaired, nothing is lost', () async {
    await repo.writePrompt(Prompt(id: 'same', title: 'A', body: 'one'));
    fs.files['$kPromptsDir/A copy.md'] = fs.files['$kPromptsDir/A.md']!;
    final data = await VaultRepository(fs).loadAll();
    expect(data.prompts.length, 2);
    expect(data.prompts.values.map((p) => p.body), everyElement('one'));
  });

  test('removing a prompt deletes its file and versions', () async {
    final p = Prompt(id: 'p1', title: 'T', body: 'b');
    await repo.writePrompt(p);
    await repo.writeVersion(PromptVersion(promptId: 'p1', versionNum: 1, title: 'T', body: 'b'));
    await repo.removePrompt('p1');
    expect(fs.files.keys.where((k) => k.contains('p1') || k.startsWith('$kPromptsDir/')), isEmpty);
  });

  test('versions round-trip in order', () async {
    for (final n in [1, 2, 3]) {
      await repo.writeVersion(PromptVersion(promptId: 'p1', versionNum: n, title: 'T', body: 'body $n', note: 'note $n'));
    }
    final list = await repo.listVersions('p1');
    expect(list.map((v) => v.versionNum), [1, 2, 3]);
    expect(list.last.body, 'body 3');
    expect(list.first.note, 'note 1');
    await repo.removeVersion('p1', 2);
    expect((await repo.listVersions('p1')).map((v) => v.versionNum), [1, 3]);
  });

  test('templates, snippets, patterns, chains and settings persist', () async {
    await repo.writeTemplate(Template(id: 't1', name: 'Email', body: 'Hi {{name}}', category: 'writing'));
    await repo.writeSnippet(Snippet(id: 's1', trigger: '/sig', body: 'Best, Me'));
    await repo.writePattern(PromptPattern(id: 'c1', name: 'My pattern', template: 'T {{x}}'));
    await repo.writeChain(Chain(id: 'ch1', name: 'Flow', description: 'desc', steps: [ChainStep(promptId: 'p1', note: 'first')]));
    await repo.writeSettings(VaultSettings(selectedModel: 'gpt4o', versionRetention: 10));
    final d = await VaultRepository(fs).loadAll();
    expect(d.templates['t1']!.body, 'Hi {{name}}');
    expect(d.snippets['s1']!.trigger, '/sig');
    expect(d.customPatterns['c1']!.template, 'T {{x}}');
    expect(d.chains['ch1']!.steps.single.note, 'first');
    expect(d.chains['ch1']!.description, 'desc');
    expect(d.settings.selectedModel, 'gpt4o');
    expect(d.settings.versionRetention, 10);
  });

  test('groups, saved searches and structures persist in .promptforge', () async {
    await repo.writeGroups([Group(id: 'g1', kind: 'library', name: 'Work', color: 0xFF5B8DEF, memberIds: ['p1'])]);
    await repo.writeSavedSearches([SavedSearch(id: 'ss1', name: 'Fav', query: 'x')]);
    await repo.writeBuilderStructures([BuilderStructure(id: 'b1', name: 'S', blocks: [PromptBlock(type: 'role')])]);
    final d = await VaultRepository(fs).loadAll();
    expect(d.groups['g1']!.memberIds, ['p1']);
    expect(d.savedSearches['ss1']!.query, 'x');
    expect(d.builderStructures['b1']!.blocks.single.type, 'role');
  });

  test('corrupt settings.json falls back to defaults instead of failing', () async {
    fs.files['$kMetaDir/settings.json'] = '{not json';
    final d = await VaultRepository(fs).loadAll();
    expect(d.settings.selectedModel, isNotEmpty);
  });
}
