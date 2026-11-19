import '../../core/constants.dart';
import '../../core/util.dart';
import '../../data/vault/vault_repository.dart';
import '../models.dart';

class SearchResult {
  final String kind; // prompt | template | snippet | pattern
  final String id;
  final String title;
  final String snippet;
  final int score;
  const SearchResult(this.kind, this.id, this.title, this.snippet, this.score);
}

class RelatedPrompt {
  final Prompt prompt;
  final double sim;
  const RelatedPrompt(this.prompt, this.sim);
}

class SearchEngine {
  SearchEngine._();

  static int _score(String hay, String rawQuery, List<String> qTokens) {
    var score = 0;
    if (hay.contains(rawQuery)) score += 10;
    var matched = 0;
    for (final t in qTokens) {
      if (hay.contains(t)) {
        score += 2;
        matched++;
      }
    }
    if (qTokens.length > 1 && matched < qTokens.length) return 0;
    return score;
  }

  static List<SearchResult> search(VaultData d, String query, {Set<String> types = const {'prompts', 'templates', 'snippets'}, int limit = 30}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final qTokens = Utils.tokenize(q);
    final results = <SearchResult>[];

    if (types.contains('prompts')) {
      for (final p in d.prompts.values) {
        final hay = '${p.title} ${p.body} ${p.tags.join(' ')} ${p.category}'.toLowerCase();
        final s = _score(hay, q, qTokens);
        if (s > 0) results.add(SearchResult('prompt', p.id, p.displayTitle, Utils.truncate(p.body, 120), s));
      }
    }
    if (types.contains('templates')) {
      for (final t in d.templates.values) {
        final s = _score('${t.name} ${t.body}'.toLowerCase(), q, qTokens);
        if (s > 0) results.add(SearchResult('template', t.id, t.displayName, Utils.truncate(t.body, 120), s));
      }
    }
    if (types.contains('snippets')) {
      for (final sn in d.snippets.values) {
        final s = _score('${sn.trigger} ${sn.body}'.toLowerCase(), q, qTokens);
        if (s > 0) results.add(SearchResult('snippet', sn.id, sn.trigger, Utils.truncate(sn.body, 120), s));
      }
    }
    if (types.contains('patterns')) {
      for (final pat in [...kPatterns, ...d.customPatterns.values]) {
        final s = _score('${pat.name} ${pat.purpose} ${pat.when}'.toLowerCase(), q, qTokens);
        if (s > 0) results.add(SearchResult('pattern', pat.id, pat.name, pat.purpose, s));
      }
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return results.length > limit ? results.sublist(0, limit) : results;
  }

  static List<RelatedPrompt> relatedTo(VaultData d, String promptId, String text, {int limit = 5}) {
    final out = <RelatedPrompt>[];
    for (final p in d.prompts.values) {
      if (p.id == promptId || p.archived || p.body.isEmpty) continue;
      final sim = Utils.textSimilarity(text, p.body);
      if (sim > 0.06) out.add(RelatedPrompt(p, sim));
    }
    out.sort((a, b) => b.sim.compareTo(a.sim));
    return out.length > limit ? out.sublist(0, limit) : out;
  }
}

class GraphNode {
  final String id;
  final String title;
  final int updatedAt;
  const GraphNode(this.id, this.title, this.updatedAt);
}

class GraphEdge {
  final String source;
  final String target;
  const GraphEdge(this.source, this.target);
}

class BrokenLink {
  final String sourceId;
  final String sourceTitle;
  final String targetTitle;
  const BrokenLink(this.sourceId, this.sourceTitle, this.targetTitle);
}

class LinkGraph {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final List<BrokenLink> brokenLinks;
  const LinkGraph(this.nodes, this.edges, this.brokenLinks);
}

/// Resolves `[[Title]]` references (Obsidian-style wiki links) between prompts.
class LinkGraphBuilder {
  LinkGraphBuilder._();

  static LinkGraph build(Iterable<Prompt> activePrompts) {
    final prompts = activePrompts.toList();
    final byTitle = <String, List<Prompt>>{};
    for (final p in prompts) {
      byTitle.putIfAbsent(p.displayTitle.toLowerCase(), () => <Prompt>[]).add(p);
    }
    final nodes = prompts.map((p) => GraphNode(p.id, p.displayTitle, p.updatedAt)).toList();
    final edges = <GraphEdge>[];
    final broken = <BrokenLink>[];
    final re = RegExp(r'\[\[([^\]]+)\]\]');
    for (final p in prompts) {
      for (final m in re.allMatches(p.body)) {
        final target = m.group(1)!.trim();
        final matches = byTitle[target.toLowerCase()];
        if (matches != null && matches.isNotEmpty) {
          final sorted = [...matches]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          if (sorted.first.id != p.id) edges.add(GraphEdge(p.id, sorted.first.id));
        } else {
          broken.add(BrokenLink(p.id, p.displayTitle, target));
        }
      }
    }
    return LinkGraph(nodes, edges, broken);
  }
}

class TriggerMatch {
  final String prefix;
  final String query;
  final String fullMatch;
  const TriggerMatch(this.prefix, this.query, this.fullMatch);
}

class SuggestionItem {
  final String label;
  final String text;

  /// snippet | prompt | pattern | template | block | link | variable | phrase | word
  final String src;
  final String? meta;

  /// For word/phrase completions: number of already-typed characters to replace.
  final int matchLen;
  const SuggestionItem(this.label, this.text, this.src, {this.meta, this.matchLen = 0});
}

/// "/", "//", "///", "\", "\\" and "@" insertion triggers in the editor.
class TriggerDetector {
  TriggerDetector._();

  static final RegExp _re = RegExp(r'(^|\s)(/{1,3}|\\{1,2}|@)([^\s]*)$');

  static TriggerMatch? detect(String textBeforeCursor) {
    final m = _re.firstMatch(textBeforeCursor);
    if (m == null) return null;
    final q = m.group(3) ?? '';
    return TriggerMatch(m.group(2)!, q, '${m.group(2)}$q');
  }

  static String? kindForPrefix(String prefix) {
    const map = {'/': 'snippet', '//': 'prompt', '///': 'pattern', '\\': 'template', '\\\\': 'block', '@': 'link'};
    return map[prefix];
  }

  static List<SuggestionItem> candidatesFor(String kind, String query, VaultData d) {
    final q = query.trim();
    final ql = q.toLowerCase();
    final activePrompts = d.prompts.values.where((p) => !p.archived).toList();
    List<Prompt> promptPool() {
      if (q.isNotEmpty) {
        final res = SearchEngine.search(d, q, types: const {'prompts'}, limit: 8);
        return res.map((r) => d.prompts[r.id]).whereType<Prompt>().toList();
      }
      final sorted = [...activePrompts]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sorted.take(8).toList();
    }

    switch (kind) {
      case 'snippet':
        return d.snippets.values
            .where((s) => s.trigger.toLowerCase().startsWith('/${ql}'))
            .take(8)
            .map((s) => SuggestionItem(s.trigger, s.body, 'snippet', meta: s.id))
            .toList();
      case 'prompt':
        return promptPool().map((p) => SuggestionItem(p.displayTitle, p.body, 'prompt', meta: p.id)).toList();
      case 'pattern':
        final all = [...kPatterns, ...d.customPatterns.values];
        final pool = q.isNotEmpty ? all.where((p) => p.name.toLowerCase().contains(ql) || p.purpose.toLowerCase().contains(ql)).take(8) : all.take(8);
        return pool.map((p) => SuggestionItem(p.name, p.template, 'pattern', meta: p.id)).toList();
      case 'template':
        final all = d.templates.values.toList();
        final pool = q.isNotEmpty
            ? all.where((t) => t.name.toLowerCase().contains(ql)).take(8).toList()
            : ([...all]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt))).take(8).toList();
        return pool.map((t) => SuggestionItem(t.displayName, t.body, 'template', meta: t.id)).toList();
      case 'block':
        final pool = ql.isNotEmpty ? kBlockTypes.where((b) => b.id.startsWith(ql) || b.label.toLowerCase().startsWith(ql)) : kBlockTypes;
        return pool.take(11).map((b) => SuggestionItem(b.label, '${b.label}:\n', 'block', meta: b.id)).toList();
      case 'link':
        return promptPool().map((p) => SuggestionItem(p.displayTitle, '[[${p.displayTitle}]]', 'link', meta: p.id)).toList();
    }
    return const [];
  }
}

const Set<String> kStopWords = {
  'the', 'and', 'for', 'that', 'with', 'this', 'from', 'have', 'will', 'your', 'you', 'are', 'should', 'must', 'into', 'when', 'then', 'than', 'also',
  'each', 'been', 'being', 'they', 'them', 'their', 'what', 'which', 'while', 'about', 'these', 'those', 'such', 'only', 'some', 'more', 'most', 'less',
  'just', 'like', 'make', 'made', 'used', 'using', 'need', 'needs', 'provide', 'given', 'over', 'under', 'not', 'use', 'can', "it's", 'its',
};

class _Rec {
  int count = 0;
  int lastUsed = 0;
  List<String> words = const [];
}

/// Learned phrase completion (local n-grams over the vault) + variable-name suggestions.
class SuggestionEngine {
  static const int minPhraseLen = 2;
  static const int maxPhraseLen = 5;

  final Map<String, _Rec> _words = {};
  final Map<String, _Rec> _phrases = {};
  final Map<String, Set<String>> _byFirst = {};
  final Map<String, int> _varNames = {};

  void rebuild(VaultData d) {
    _words.clear();
    _phrases.clear();
    _byFirst.clear();
    _varNames.clear();
    final varRe = RegExp(r'\{\{\s*([a-zA-Z0-9_]+)');
    void learnVars(String body) {
      for (final m in varRe.allMatches(body)) {
        _varNames[m.group(1)!] = (_varNames[m.group(1)!] ?? 0) + 1;
      }
    }

    for (final p in d.prompts.values) {
      _learn(p.body, p.updatedAt);
      learnVars(p.body);
    }
    for (final t in d.templates.values) {
      _learn(t.body, t.updatedAt);
      learnVars(t.body);
    }
    for (final s in d.snippets.values) {
      _learn(s.body, s.updatedAt);
    }
  }

  void _learn(String text, int ts) {
    if (text.length < 2) return;
    for (final sentence in text.split(RegExp(r'(?<=[.!?\n])\s+'))) {
      final words = Utils.tokenize(sentence);
      if (words.isEmpty) continue;
      for (final w in words) {
        if (w.length < 2) continue;
        final rec = _words.putIfAbsent(w, () => _Rec());
        rec.count++;
        if (ts > rec.lastUsed) rec.lastUsed = ts;
      }
      for (var len = minPhraseLen; len <= maxPhraseLen; len++) {
        for (var i = 0; i + len <= words.length; i++) {
          final slice = words.sublist(i, i + len);
          final key = slice.join(' ');
          final rec = _phrases.putIfAbsent(key, () => _Rec()..words = slice);
          rec.count++;
          if (ts > rec.lastUsed) rec.lastUsed = ts;
          _byFirst.putIfAbsent(slice.first, () => <String>{}).add(key);
        }
      }
    }
  }

  double _score(int count, int lastUsed, int now) {
    final ageDays = ((now - lastUsed) / 86400000).clamp(0, double.infinity).toDouble();
    final recency = 1 / (1 + ageDays / 14);
    return count * (0.55 + 0.45 * recency);
  }

  /// Word completion (mid-word) and next-phrase prediction (after a space).
  List<SuggestionItem> phraseSuggestions(String textBeforeCursor, {int limit = 4}) {
    if (textBeforeCursor.isEmpty || _words.isEmpty) return const [];
    final trailingSpace = RegExp(r'\s$').hasMatch(textBeforeCursor);
    final trimmed = textBeforeCursor.replaceAll(RegExp(r'\s+$'), '');
    final ctx = Utils.tokenize(trimmed);
    if (ctx.isEmpty) return const [];
    final now = Utils.nowMs();
    final best = <String, MapEntry<double, SuggestionItem>>{};
    void add(String text, double score, String src, int matchLen) {
      final ex = best[text];
      if (ex == null || score > ex.key) best[text] = MapEntry(score, SuggestionItem(text, text, src, matchLen: matchLen));
    }

    if (!trailingSpace) {
      final partial = ctx.last;
      for (final e in _words.entries) {
        if (e.key != partial && e.key.startsWith(partial)) add(e.key, _score(e.value.count, e.value.lastUsed, now), 'word', partial.length);
      }
      for (final e in _byFirst.entries) {
        if (e.key == partial || !e.key.startsWith(partial)) continue;
        for (final key in e.value) {
          final rec = _phrases[key];
          if (rec == null) continue;
          add(rec.words.join(' '), _score(rec.count, rec.lastUsed, now) * 1.15, 'phrase', partial.length);
        }
      }
    } else {
      final maxLook = (maxPhraseLen - 1) < ctx.length ? (maxPhraseLen - 1) : ctx.length;
      for (var look = maxLook; look >= 1; look--) {
        final tail = ctx.sublist(ctx.length - look);
        final keys = _byFirst[tail.first];
        if (keys == null) continue;
        for (final key in keys) {
          final rec = _phrases[key];
          if (rec == null || rec.words.length <= look) continue;
          if (rec.words.sublist(0, look).join(' ') != tail.join(' ')) continue;
          final cont = rec.words.sublist(look).join(' ');
          if (cont.isEmpty) continue;
          add(cont, _score(rec.count, rec.lastUsed, now) * (1 + look * 0.6), 'phrase', 0);
        }
        if (best.length >= limit * 2) break;
      }
    }
    final list = best.values.toList()..sort((a, b) => b.key.compareTo(a.key));
    return list.take(limit).map((e) => e.value).toList();
  }

  /// Variable names already used in `{{...}}` across the vault.
  List<SuggestionItem> variableSuggestions(String partial, {int limit = 6}) {
    final p = partial.toLowerCase();
    final entries = _varNames.entries.where((e) => e.key.toLowerCase().startsWith(p) && e.key.toLowerCase() != p).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => SuggestionItem(e.key, e.key, 'variable', matchLen: partial.length)).toList();
  }

  List<MapEntry<String, int>> topWords(int n) {
    final list = _words.entries.where((e) => e.key.length > 2 && !kStopWords.contains(e.key)).toList()..sort((a, b) => b.value.count.compareTo(a.value.count));
    return list.take(n).map((e) => MapEntry(e.key, e.value.count)).toList();
  }
}
