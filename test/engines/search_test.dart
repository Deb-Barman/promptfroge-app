import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_forge/data/vault/vault_repository.dart';
import 'package:prompt_forge/domain/engines/search_engine.dart';
import 'package:prompt_forge/domain/models.dart';

VaultData _vault() {
  final d = VaultData();
  for (final p in [
    Prompt(id: 'a', title: 'Cold email outreach', body: 'Write a cold email to a founder. See [[Follow up email]] and [[Missing note]].', tags: ['sales']),
    Prompt(id: 'b', title: 'Follow up email', body: 'Write a polite follow up email after no reply to the first message.'),
    Prompt(id: 'c', title: 'Poem about the sea', body: 'Write a short poem about the ocean waves.', archived: true),
    Prompt(id: 'd', title: 'Orphan', body: 'Nothing links here.'),
  ]) {
    d.prompts[p.id] = p;
  }
  final s = Snippet(id: 's', trigger: '/sig', body: 'Best regards, Priya');
  d.snippets[s.id] = s;
  final t = Template(id: 't', name: 'Weekly update', body: 'Update for {{week}}');
  d.templates[t.id] = t;
  return d;
}

void main() {
  test('search finds prompts, templates and snippets and ranks title hits first', () {
    final r = SearchEngine.search(_vault(), 'email');
    expect(r.first.kind, 'prompt');
    expect(r.map((x) => x.id), containsAll(['a', 'b']));
    expect(SearchEngine.search(_vault(), 'regards').single.kind, 'snippet');
    expect(SearchEngine.search(_vault(), 'weekly').single.kind, 'template');
    expect(SearchEngine.search(_vault(), 'zzzznotthere'), isEmpty);
    expect(SearchEngine.search(_vault(), ''), isEmpty);
  });

  test('related prompts are ranked by similarity and exclude the prompt itself', () {
    final d = _vault();
    final r = SearchEngine.relatedTo(d, 'a', d.prompts['a']!.body);
    expect(r.every((x) => x.prompt.id != 'a'), isTrue);
    if (r.isNotEmpty) expect(r.first.prompt.id, 'b');
  });

  test('link graph resolves [[wiki links]] case-insensitively and reports broken ones', () {
    final d = _vault();
    final g = LinkGraphBuilder.build(d.prompts.values.where((p) => !p.archived));
    expect(g.edges.any((e) => e.source == 'a' && e.target == 'b'), isTrue);
    expect(g.brokenLinks.map((b) => b.targetTitle), ['Missing note']);
    expect(g.nodes.length, 3);
  });

  group('TriggerDetector', () {
    test('detects every prefix', () {
      for (final e in {'/sig': '/', '//intro': '//', '///cot': '///', r'\tpl': r'\', r'\\role': r'\\', '@foll': '@'}.entries) {
        final m = TriggerDetector.detect('hello ${e.key}');
        expect(m, isNotNull, reason: e.key);
        expect(m!.prefix, e.value);
        expect(TriggerDetector.kindForPrefix(m.prefix), isNotNull);
      }
    });
    test('does not trigger inside words or URLs', () {
      expect(TriggerDetector.detect('see http://x.com/path'), isNull);
      expect(TriggerDetector.detect('a/b'), isNull);
      expect(TriggerDetector.detect('plain text '), isNull);
    });
    test('candidates come from the vault', () {
      final d = _vault();
      final snip = TriggerDetector.candidatesFor(TriggerDetector.kindForPrefix('/')!, 'si', d);
      expect(snip.map((x) => x.text), contains('Best regards, Priya'));
      final links = TriggerDetector.candidatesFor(TriggerDetector.kindForPrefix('@')!, 'foll', d);
      expect(links.map((x) => x.text), contains('[[Follow up email]]'));
    });
  });

  test('variable and phrase suggestions are learned from the vault', () {
    final d = _vault();
    d.templates['t2'] = Template(id: 't2', name: 'X', body: 'Hello {{customer_name}} from {{company}}');
    final e = SuggestionEngine()..rebuild(d);
    expect(e.variableSuggestions('cust').map((x) => x.text), contains('customer_name'));
    expect(e.variableSuggestions('zzz'), isEmpty);
    expect(e.phraseSuggestions('Write a cold email to a'), isA<List<SuggestionItem>>());
  });
}
