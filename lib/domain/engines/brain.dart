import 'dart:math' as math;

import 'brain_seed.dart';

/// Where a piece of learning material came from.
enum BrainSource { prompt, template, pattern, snippet, chain, seed }

/// One document the brain learns from. Plain data so it can be sent to a background isolate.
class BrainDoc {
  final String text;
  final BrainSource source;

  /// Importance of this document (favourites and templates count for more, archived prompts for less).
  final double weight;

  /// Last update time in ms since epoch; recent material counts slightly more.
  final int updatedAt;
  const BrainDoc(this.text, this.source, {this.weight = 1, this.updatedAt = 0});
}

/// A suggestion produced by the brain.
class BrainHit {
  /// Text to put in the editor. It replaces [matchLen] characters before the cursor.
  final String insert;

  /// Text shown in lists.
  final String label;

  /// `word`, `phrase` (typed prefix completion) or `next` (prediction after a space).
  final String kind;
  final double score;
  final int matchLen;
  const BrainHit(this.insert, this.label, this.kind, this.score, this.matchLen);
}

class BrainPhrase {
  final String text;
  final double weight;
  const BrainPhrase(this.text, this.weight);
}

class BlockHint {
  final String id;
  final double score;
  final bool present;

  /// True for the few missing sections this user usually writes in prompts like this one.
  final bool recommended;
  const BlockHint(this.id, this.score, this.present, this.recommended);
}

class BrainLevel {
  final int level;
  final String name;

  /// 0..1 progress towards the next level (1 at the top level).
  final double progress;
  final int points;
  final int nextAt;
  const BrainLevel(this.level, this.name, this.progress, this.points, this.nextAt);
}

class BrainStats {
  final int tokens;
  final int vocabulary;
  final int phrases;
  final int documents;
  final Map<BrainSource, int> bySource;
  const BrainStats(this.tokens, this.vocabulary, this.phrases, this.documents, this.bySource);

  int get points => tokens + documents * 30 + phrases * 4;
}

/// What the user actually accepted. Accepted words are boosted next time.
class BrainUsage {
  final Map<String, int> accepted;
  int shown;
  int acceptedTotal;
  int announcedLevel;
  BrainUsage({Map<String, int>? accepted, this.shown = 0, this.acceptedTotal = 0, this.announcedLevel = 0}) : accepted = accepted ?? <String, int>{};

  double get acceptRate => shown <= 0 ? 0 : math.min(1, acceptedTotal / shown);

  void record(String insert) {
    final key = insert.trim().toLowerCase();
    if (key.isEmpty) return;
    accepted[key] = (accepted[key] ?? 0) + 1;
    acceptedTotal++;
    if (accepted.length > 1200) {
      final sorted = accepted.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      accepted
        ..clear()
        ..addEntries(sorted.take(800));
    }
  }

  void reset() {
    accepted.clear();
    shown = 0;
    acceptedTotal = 0;
  }

  Map<String, dynamic> toJson() => {'a': accepted, 's': shown, 't': acceptedTotal, 'l': announcedLevel};

  factory BrainUsage.fromJson(Map<String, dynamic> m) {
    final a = <String, int>{};
    final raw = m['a'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is num) a[k] = v.toInt();
      });
    }
    int n(Object? v) => v is num ? v.toInt() : 0;
    return BrainUsage(accepted: a, shown: n(m['s']), acceptedTotal: n(m['t']), announcedLevel: n(m['l']));
  }
}

const Set<String> _kStop = {
  'a', 'an', 'the', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'at', 'for', 'with', 'from', 'by', 'as', 'is', 'are', 'was', 'were', 'be', 'been',
  'it', 'its', 'this', 'that', 'these', 'those', 'if', 'then', 'than', 'so', 'do', 'does', 'did', 'not', 'no', 'you', 'your', 'i', 'we', 'they',
  'he', 'she', 'my', 'our', 'their', 'will', 'can', 'should', 'must', 'may', 'into', 'about', 'also', 'any', 'all', 'each', 'such', 'which',
  'who', 'what', 'when', 'where', 'how', 'why', 'have', 'has', 'had', 'up', 'out', 'over', 'under', 'between', 'while', 'only', 'more',
};

/// Points needed for each brain level and the level's name.
const List<(int, String)> kBrainLevels = [
  (0, 'Seed'),
  (150, 'Sprout'),
  (600, 'Apprentice'),
  (2000, 'Adept'),
  (6000, 'Expert'),
  (16000, 'Master'),
  (40000, 'Sage'),
  (100000, 'Oracle'),
];

final RegExp _tokRe = RegExp(r"\{\{\s*[A-Za-z0-9_]+\s*\}\}|[A-Za-z][A-Za-z0-9_'’]*(?:-[A-Za-z0-9_]+)*");
final RegExp _breakRe = RegExp(r'[.!?;]+\s|\n|:\s');
final RegExp _segSplit = RegExp(r'[.!?;]+(?=\s|$)|\n+|:(?=\s|$)');

const String _start = '<s>';

bool _isVar(String t) => t.startsWith('{{');
bool _isWordToken(String t) => !_isVar(t) && t.length >= 3;

String _norm(String raw) => _isVar(raw) ? '{{${raw.substring(2, raw.length - 2).trim().toLowerCase()}}}' : raw.toLowerCase().replaceAll('’', "'");

/// The editor brain: a small statistical language model built only from the user's own prompts, templates,
/// patterns, snippets and chains (plus a tiny low-weight seed). Everything runs on the device.
///
/// The more material the vault holds, the more it knows: completions, next-word predictions, usual sentence
/// starts, favourite variables and the prompt sections the user normally writes.
class BrainModel {
  final Map<String, double> _uni;
  final Map<String, Map<String, double>> _bi;
  final Map<String, Map<String, double>> _tri;
  final Map<String, double> _biTotal;
  final Map<String, double> _triTotal;
  final Map<String, String> _surface;
  final List<String> _sorted;
  final Map<String, double> _sections;
  final Map<String, Map<String, double>> _co;
  final Map<String, String> _aliases;
  final Set<String> _blockIds;

  final BrainStats stats;
  final List<BrainPhrase> topPhrases;
  final List<MapEntry<String, double>> topWords;
  final List<MapEntry<String, double>> topSections;

  BrainModel._(this._uni, this._bi, this._tri, this._biTotal, this._triTotal, this._surface, this._sorted, this._sections, this._co, this._aliases, this._blockIds, this.stats,
      this.topPhrases, this.topWords, this.topSections);

  static BrainModel empty() => BrainModel.build(const [], includeSeed: false);

  bool get isEmpty => _uni.isEmpty;

  BrainLevel get level {
    final pts = stats.points;
    var idx = 0;
    for (var i = 0; i < kBrainLevels.length; i++) {
      if (pts >= kBrainLevels[i].$1) idx = i;
    }
    final cur = kBrainLevels[idx].$1;
    final hasNext = idx + 1 < kBrainLevels.length;
    final next = hasNext ? kBrainLevels[idx + 1].$1 : cur;
    final progress = hasNext ? ((pts - cur) / (next - cur)).clamp(0.0, 1.0) : 1.0;
    return BrainLevel(idx + 1, kBrainLevels[idx].$2, progress.toDouble(), pts, next);
  }

  // ------------------------------------------------------------------ build

  static BrainModel build(List<BrainDoc> docs, {int now = 0, Map<String, String> sectionAliases = const {}, bool includeSeed = true}) {
    final b = _Builder(now, sectionAliases);
    if (includeSeed) {
      for (final s in kBrainSeedSentences) {
        b.addDoc(BrainDoc(s, BrainSource.seed, weight: 0.35));
      }
      for (final w in kBrainSeedWords.split(' ')) {
        if (w.isNotEmpty) b.uni[w] = (b.uni[w] ?? 0) + 0.3;
      }
    }
    for (final d in docs) {
      b.addDoc(d);
    }
    return b.finish();
  }

  // ------------------------------------------------------------- suggestions

  /// Context for prediction: the last two words of the current sentence/line (or the start marker).
  (String?, String) _context(String before) {
    final tail = before.length > 400 ? before.substring(before.length - 400) : before;
    var start = 0;
    for (final m in _breakRe.allMatches(tail)) {
      start = m.end;
    }
    final seg = tail.substring(start);
    final toks = [for (final m in _tokRe.allMatches(seg)) _norm(m.group(0)!)];
    if (toks.isEmpty) return (null, _start);
    if (toks.length == 1) return (_start, toks[0]);
    return (toks[toks.length - 2], toks[toks.length - 1]);
  }

  /// Probability-like distribution of the next word after (p2, p1).
  Map<String, double> _nextDist(String? p2, String p1) {
    final out = <String, double>{};
    final tri = p2 == null ? null : _tri['$p2 $p1'];
    final bi = _bi[p1];
    final triTotal = tri == null ? 0.0 : (_triTotal['$p2 $p1'] ?? 0.0);
    final biTotal = bi == null ? 0.0 : (_biTotal[p1] ?? 0.0);
    if (tri != null && triTotal > 0) {
      tri.forEach((w, c) => out[w] = (out[w] ?? 0) + 0.65 * c / triTotal);
    }
    if (bi != null && biTotal > 0) {
      final k = (tri != null && triTotal > 0) ? 0.35 : 1.0;
      bi.forEach((w, c) => out[w] = (out[w] ?? 0) + k * c / biTotal);
    }
    return out;
  }

  double _support(String? p2, String p1) {
    final t = p2 == null ? 0.0 : (_triTotal['$p2 $p1'] ?? 0.0);
    return t > 0 ? t : (_biTotal[p1] ?? 0.0);
  }

  /// Follows the most likely continuation to turn a word into a short phrase.
  List<String> _extend(String first, String prev, {int maxExtra = 4}) {
    final words = <String>[];
    var a = prev;
    var b = first;
    for (var i = 0; i < maxExtra; i++) {
      final dist = _nextDist(a, b);
      if (dist.isEmpty) break;
      String? best;
      var bestP = 0.0;
      dist.forEach((w, p) {
        if (p > bestP && w != _start) {
          best = w;
          bestP = p;
        }
      });
      final cand = best;
      if (cand == null || bestP < 0.34 || _support(a, b) < 1.6) break;
      if (words.contains(cand) || cand == first) break;
      words.add(cand);
      a = b;
      b = cand;
    }
    while (words.isNotEmpty && _kStop.contains(words.last)) {
      words.removeLast();
    }
    return words;
  }

  String _cased(String partial, String lowerWord) {
    final s = _surface[lowerWord];
    if (s != null) return s;
    if (partial.isEmpty || _isVar(lowerWord)) return lowerWord;
    if (partial.length > 1 && partial == partial.toUpperCase() && partial != partial.toLowerCase()) return lowerWord.toUpperCase();
    if (partial[0] != partial[0].toLowerCase() && lowerWord.isNotEmpty) return lowerWord[0].toUpperCase() + lowerWord.substring(1);
    return lowerWord;
  }

  String _plain(String lowerWord) => _surface[lowerWord] ?? lowerWord;

  double _boost(BrainUsage? u, String text) {
    if (u == null) return 0;
    final n = u.accepted[text.toLowerCase()] ?? 0;
    return n == 0 ? 0 : 0.9 * math.log(1 + n);
  }

  int _lowerBound(String prefix) {
    var lo = 0, hi = _sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sorted[mid].compareTo(prefix) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Completions for the word being typed (needs at least two letters). Words and short phrases, best first.
  List<BrainHit> complete(String before, {int limit = 8, BrainUsage? usage}) {
    if (_uni.isEmpty) return const [];
    final m = RegExp(r"([A-Za-z][A-Za-z0-9_'’-]*)$").firstMatch(before);
    if (m == null) return const [];
    final partial = m.group(1)!;
    if (partial.length < 2) return const [];
    final lp = partial.toLowerCase();
    final head = before.substring(0, m.start);
    if (head.isNotEmpty && RegExp(r'[{@/\\]$').hasMatch(head)) return const [];
    final (p2, p1) = _context(head);

    final scored = <MapEntry<String, double>>[];
    for (var i = _lowerBound(lp); i < _sorted.length; i++) {
      final w = _sorted[i];
      if (!w.startsWith(lp)) break;
      if (w == lp) continue;
      final gain = w.length - lp.length;
      if (gain < 2) continue;
      if (lp.length < 3 && _kStop.contains(w)) continue;
      final base = math.log(1 + (_uni[w] ?? 0));
      final pBi = _bi[p1] == null ? 0.0 : ((_bi[p1]![w] ?? 0) / (_biTotal[p1] ?? 1));
      final pTri = p2 == null || _tri['$p2 $p1'] == null ? 0.0 : ((_tri['$p2 $p1']![w] ?? 0) / (_triTotal['$p2 $p1'] ?? 1));
      final s = base + 4 * pBi + 6 * pTri + _boost(usage, w) - 0.02 * gain;
      scored.add(MapEntry(w, s));
    }
    if (scored.isEmpty) return const [];
    scored.sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });

    final hits = <String, BrainHit>{};
    void add(BrainHit h) {
      final k = h.insert.toLowerCase();
      final ex = hits[k];
      if (ex == null || h.score > ex.score) hits[k] = h;
    }

    final top = scored.take(math.max(limit + 4, 10)).toList();
    for (final e in top) {
      add(BrainHit(_cased(partial, e.key), _cased(partial, e.key), 'word', e.value, partial.length));
    }
    for (final e in top.take(4)) {
      final ext = _extend(e.key, p1, maxExtra: 3);
      if (ext.isEmpty) continue;
      final phrase = ([_cased(partial, e.key), ...ext.map(_plain)]).join(' ');
      add(BrainHit(phrase, phrase, 'phrase', e.value - 0.02 + _boost(usage, phrase) * 0.5, partial.length));
    }
    final list = hits.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    return list.take(limit).toList();
  }

  /// Predictions for the word after a space / at the start of a line (shown as chips above the keyboard).
  List<BrainHit> predictNext(String before, {int limit = 4, BrainUsage? usage}) {
    if (_uni.isEmpty) return const [];
    if (before.isNotEmpty && !RegExp(r'\s$').hasMatch(before)) return const [];
    if (before.trim().isEmpty) {
      // an empty document: offer the usual openings
      return _predictFrom(null, _start, limit, usage);
    }
    final (p2, p1) = _context(before);
    return _predictFrom(p2, p1, limit, usage);
  }

  List<BrainHit> _predictFrom(String? p2, String p1, int limit, BrainUsage? usage) {
    final dist = _nextDist(p2, p1);
    if (dist.isEmpty || _support(p2, p1) < 1.8) return const [];
    final ranked = dist.entries.where((e) => e.key != _start && e.value >= 0.14).toList()..sort((a, b) => b.value.compareTo(a.value));
    final out = <String, BrainHit>{};
    for (final e in ranked.take(limit + 2)) {
      final w = e.key;
      final shown = _isVar(w) ? w : _plain(w);
      final ext = _extend(w, p1);
      final text = ext.isEmpty ? shown : [shown, ...ext.map(_plain)].join(' ');
      final score = e.value * 10 + (ext.isEmpty ? 0 : 0.5) + _boost(usage, text);
      out[text.toLowerCase()] = BrainHit('$text ', text, 'next', score, 0);
      if (ext.isNotEmpty) {
        // also offer the single word, so the user can stop early
        out.putIfAbsent(shown.toLowerCase(), () => BrainHit('$shown ', shown, 'next', e.value * 10 - 0.2, 0));
      }
    }
    final list = out.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    return list.take(limit).toList();
  }

  // --------------------------------------------------------------- sections

  String? _sectionOf(String line) {
    final t = line.trim();
    if (t.isEmpty) return null;
    final s = t.length > 64 ? t.substring(0, 64) : t;
    var m = RegExp(r'^#{1,4}\s*(.+?)\s*:?$').firstMatch(s);
    m ??= RegExp(r'^[*_]{0,2}([A-Za-z][A-Za-z /&-]{1,30}?)[*_]{0,2}\s*:(?:\s|$)').firstMatch(s);
    m ??= RegExp(r'^<([A-Za-z_]{2,24})>').firstMatch(s);
    if (m == null) return null;
    return _aliases[m.group(1)!.trim().toLowerCase()];
  }

  /// Ids of the sections already written in [text].
  Set<String> sectionsIn(String text) {
    final out = <String>{};
    for (final line in text.split('\n')) {
      final s = _sectionOf(line);
      if (s != null) out.add(s);
    }
    return out;
  }

  /// Block types ordered by how likely this user is to want them next. Sections the prompt already has are
  /// marked present; up to three missing ones the user habitually writes alongside the present ones are
  /// marked recommended.
  List<BlockHint> rankBlocks(String text) {
    final present = sectionsIn(text);
    final ids = _blockIds.toList();
    final out = <BlockHint>[];
    final scores = <String, double>{};
    for (final id in ids) {
      final freq = _sections[id] ?? 0;
      var s = math.log(1 + freq);
      for (final p in present) {
        final tot = _sections[p] ?? 0;
        if (tot > 0) s += 2.5 * ((_co[p]?[id] ?? 0) / tot);
      }
      scores[id] = s;
    }
    final missing = ids.where((i) => !present.contains(i)).toList()..sort((a, b) => scores[b]!.compareTo(scores[a]!));
    final rec = <String>{};
    for (final id in missing) {
      if (rec.length >= 3) break;
      final seen = _sections[id] ?? 0;
      if (seen < 1.5) continue;
      var ok = present.isEmpty;
      for (final p in present) {
        final tot = _sections[p] ?? 0;
        if (tot > 0 && (_co[p]?[id] ?? 0) / tot >= 0.4) ok = true;
      }
      if (ok) rec.add(id);
    }
    for (final id in ids) {
      out.add(BlockHint(id, scores[id]!, present.contains(id), rec.contains(id)));
    }
    return out;
  }
}

class _Builder {
  final int now;
  final Map<String, String> aliases;
  final Map<String, double> uni = {};
  final Map<String, Map<String, double>> bi = {};
  final Map<String, Map<String, double>> tri = {};
  final Map<String, Map<String, double>> votes = {};
  final Map<String, double> sections = {};
  final Map<String, Map<String, double>> co = {};
  final Set<String> userWords = {};
  final Map<BrainSource, int> bySource = {};
  var tokens = 0;
  var docs = 0;

  _Builder(this.now, this.aliases);

  double _recency(BrainDoc d) {
    if (d.source == BrainSource.seed || d.updatedAt <= 0 || now <= 0) return 1;
    final days = math.max(0, (now - d.updatedAt) / 86400000);
    return 0.75 + 0.25 / (1 + days / 60);
  }

  void _addTo(Map<String, Map<String, double>> m, String k, String w, double c) {
    final inner = m.putIfAbsent(k, () => <String, double>{});
    inner[w] = (inner[w] ?? 0) + c;
  }

  String? _sectionOf(String line) {
    final t = line.trim();
    if (t.isEmpty) return null;
    final s = t.length > 64 ? t.substring(0, 64) : t;
    var m = RegExp(r'^#{1,4}\s*(.+?)\s*:?$').firstMatch(s);
    m ??= RegExp(r'^[*_]{0,2}([A-Za-z][A-Za-z /&-]{1,30}?)[*_]{0,2}\s*:(?:\s|$)').firstMatch(s);
    m ??= RegExp(r'^<([A-Za-z_]{2,24})>').firstMatch(s);
    if (m == null) return null;
    return aliases[m.group(1)!.trim().toLowerCase()];
  }

  void addDoc(BrainDoc d) {
    if (d.text.trim().isEmpty) return;
    final seed = d.source == BrainSource.seed;
    final w = d.weight * _recency(d);
    if (!seed) {
      docs++;
      bySource[d.source] = (bySource[d.source] ?? 0) + 1;
      final present = <String>{};
      for (final line in d.text.split('\n')) {
        final s = _sectionOf(line);
        if (s != null) present.add(s);
      }
      for (final a in present) {
        sections[a] = (sections[a] ?? 0) + w;
        for (final b in present) {
          if (a != b) {
            final inner = co.putIfAbsent(a, () => <String, double>{});
            inner[b] = (inner[b] ?? 0) + w;
          }
        }
      }
    }
    for (final seg in d.text.split(_segSplit)) {
      if (seg.trim().isEmpty) continue;
      final raws = [for (final m in _tokRe.allMatches(seg)) m.group(0)!];
      if (raws.isEmpty) continue;
      final t = [for (final r in raws) _norm(r)];
      for (var i = 0; i < t.length; i++) {
        final cur = t[i];
        final v = _isVar(cur);
        if (!v) {
          uni[cur] = (uni[cur] ?? 0) + w;
          if (raws[i] != cur && !seed) {
            final inner = votes.putIfAbsent(cur, () => <String, double>{});
            inner[raws[i]] = (inner[raws[i]] ?? 0) + w;
          }
        }
        if (!seed) {
          tokens++;
          if (!v) userWords.add(cur);
        }
        final p1 = i > 0 ? t[i - 1] : _start;
        _addTo(bi, p1, cur, w);
        if (i >= 1) {
          final p2 = i > 1 ? t[i - 2] : _start;
          _addTo(tri, '$p2 $p1', cur, w);
        }
      }
    }
  }

  BrainModel finish() {
    if (tokens > 120000) {
      final dead = <String>[];
      tri.forEach((k, inner) {
        inner.removeWhere((_, c) => c < 1.2);
        if (inner.isEmpty) dead.add(k);
      });
      for (final k in dead) {
        tri.remove(k);
      }
    }
    final biTotal = <String, double>{};
    bi.forEach((k, inner) {
      var s = 0.0;
      for (final c in inner.values) {
        s += c;
      }
      biTotal[k] = s;
    });
    final triTotal = <String, double>{};
    var recurring = 0;
    tri.forEach((k, inner) {
      var s = 0.0;
      for (final c in inner.values) {
        s += c;
        if (c >= 2.0) recurring++;
      }
      triTotal[k] = s;
    });

    final surface = <String, String>{};
    votes.forEach((lower, raws) {
      String? best;
      var bestW = 0.0;
      raws.forEach((raw, c) {
        if (raw.length > 1 && raw.substring(1) != raw.substring(1).toLowerCase() && c > bestW) {
          best = raw;
          bestW = c;
        }
      });
      if (best != null && bestW >= 0.5 * (uni[lower] ?? 0)) surface[lower] = best!;
    });

    final sorted = [for (final w in uni.keys) if (_isWordToken(w) && !_isVar(w)) w]..sort();

    final tw = [for (final e in uni.entries) if (userWords.contains(e.key) && e.key.length > 2 && !_kStop.contains(e.key)) e]
      ..sort((a, b) => b.value.compareTo(a.value));

    final phrases = <BrainPhrase>[];
    tri.forEach((k, inner) {
      if (k.contains(_start)) return;
      final ctx = k.split(' ');
      inner.forEach((next, c) {
        if (c < 2.0) return;
        final ws = [...ctx, next];
        if (ws.every(_kStop.contains) || ws.any(_isVar)) return;
        phrases.add(BrainPhrase(ws.join(' '), c));
      });
    });
    if (phrases.length < 24) {
      bi.forEach((k, inner) {
        if (k == _start || _isVar(k)) return;
        inner.forEach((next, c) {
          if (c < 2.0 || _isVar(next)) return;
          if (_kStop.contains(k) && _kStop.contains(next)) return;
          phrases.add(BrainPhrase('$k $next', c));
        });
      });
    }
    phrases.sort((a, b) => b.weight.compareTo(a.weight));
    final seen = <String>{};
    final topPhrases = <BrainPhrase>[];
    for (final p in phrases) {
      if (topPhrases.length >= 30) break;
      // skip a phrase that is only a part of one already listed
      if (topPhrases.any((x) => x.text.contains(p.text))) continue;
      if (seen.add(p.text)) topPhrases.add(p);
    }

    final ts = sections.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final blockIds = aliases.values.toSet();
    return BrainModel._(
      uni,
      bi,
      tri,
      biTotal,
      triTotal,
      surface,
      sorted,
      sections,
      co,
      aliases,
      blockIds,
      BrainStats(tokens, userWords.length, recurring, docs, bySource),
      topPhrases,
      tw.take(30).map((e) => MapEntry(e.key, e.value)).toList(),
      ts.take(12).toList(),
    );
  }
}

// ---------------------------------------------------------------- similarity

class SimDoc {
  final String id;
  final String text;
  const SimDoc(this.id, this.text);
}

class SimEdge {
  final String a;
  final String b;
  final double sim;
  const SimEdge(this.a, this.b, this.sim);
}

/// "Related by the brain": TF-IDF cosine similarity between documents, used for the graph's soft links.
class BrainSimilarity {
  BrainSimilarity._();

  static List<SimEdge> related(List<SimDoc> docs, {double minSim = 0.16, int perNode = 2}) {
    final n = docs.length;
    if (n < 2) return const [];
    final tfs = <Map<String, double>>[];
    final df = <String, int>{};
    for (final d in docs) {
      final counts = <String, int>{};
      for (final m in _tokRe.allMatches(d.text)) {
        final t = _norm(m.group(0)!);
        if (_isVar(t) || t.length < 3 || _kStop.contains(t)) continue;
        counts[t] = (counts[t] ?? 0) + 1;
      }
      final tf = <String, double>{};
      counts.forEach((t, c) {
        tf[t] = 1 + math.log(c);
        df[t] = (df[t] ?? 0) + 1;
      });
      tfs.add(tf);
    }
    final maxDf = n >= 20 ? (n * 0.5).floor() : n;
    final vecs = <Map<String, double>>[];
    final postings = <String, List<int>>{};
    for (var i = 0; i < n; i++) {
      final v = <String, double>{};
      var norm = 0.0;
      tfs[i].forEach((t, tf) {
        final d = df[t]!;
        if (d > maxDf) return;
        final idf = math.log((n + 1) / (d + 1)) + 1;
        final x = tf * idf;
        v[t] = x;
        norm += x * x;
      });
      norm = math.sqrt(norm);
      if (norm > 0) {
        v.updateAll((_, x) => x / norm);
        v.keys.forEach((t) => postings.putIfAbsent(t, () => <int>[]).add(i));
      }
      vecs.add(v);
    }
    final best = <int, List<MapEntry<int, double>>>{};
    for (var i = 0; i < n; i++) {
      final acc = <int, double>{};
      vecs[i].forEach((t, x) {
        for (final j in postings[t]!) {
          if (j == i) continue;
          acc[j] = (acc[j] ?? 0) + x * vecs[j][t]!;
        }
      });
      final list = acc.entries.where((e) => e.value >= minSim).toList()..sort((a, b) => b.value.compareTo(a.value));
      best[i] = list.take(perNode).toList();
    }
    final seen = <String>{};
    final out = <SimEdge>[];
    best.forEach((i, list) {
      for (final e in list) {
        final a = math.min(i, e.key), b = math.max(i, e.key);
        if (seen.add('$a|$b')) out.add(SimEdge(docs[a].id, docs[b].id, e.value));
      }
    });
    return out;
  }
}
