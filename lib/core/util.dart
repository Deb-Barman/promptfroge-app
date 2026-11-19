import 'dart:math';

/// Small, dependency-free helpers ported from the original `Utils` object.
class Utils {
  Utils._();

  static final Random _rng = Random();

  static String uid([String? prefix]) {
    final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final r = List.generate(7, (_) => _rng.nextInt(36).toRadixString(36)).join();
    return (prefix != null ? '${prefix}_' : '') + t + r;
  }

  static int nowMs() => DateTime.now().millisecondsSinceEpoch;

  static String escapeHtml(String? s) {
    if (s == null) return '';
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// Strips tags / scripts before persisting (same as the original sanitizeText).
  static String sanitizeText(String? s) {
    if (s == null) return '';
    return s
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]*>'), '');
  }

  static num clamp(num n, num lo, num hi) => max(lo, min(hi, n));

  static int clampInt(num n, int lo, int hi) => max(lo, min(hi, n.round()));

  static int countWords(String? s) {
    if (s == null || s.trim().isEmpty) return 0;
    return RegExp(r'\S+').allMatches(s.trim()).length;
  }

  static String truncate(String? s, int n) {
    if (s == null || s.isEmpty) return '';
    if (s.length <= n) return s;
    return '${s.substring(0, n).trimRight()}…';
  }

  static String timeAgo(int? ts) {
    if (ts == null || ts == 0) return '';
    final diff = nowMs() - ts;
    const min = 60000, hr = 3600000, day = 86400000;
    if (diff < 45000) return 'just now';
    if (diff < hr) return '${(diff / min).round()}m ago';
    if (diff < day) return '${(diff / hr).round()}h ago';
    if (diff < day * 30) return '${(diff / day).round()}d ago';
    return formatDate(ts, withTime: false);
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String formatDate(int ts, {bool withTime = true}) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final base = '${_months[d.month - 1]} ${d.day}, ${d.year}';
    if (!withTime) return base;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$base $hh:$mm';
  }

  /// Lowercase word list; keeps internal apostrophes/hyphens ("don't", "step-by-step").
  static List<String> tokenize(String? s) {
    if (s == null || s.isEmpty) return const [];
    return RegExp(r"[a-z0-9][a-z0-9'-]*").allMatches(s.toLowerCase()).map((m) => m.group(0)!).toList();
  }

  /// Jaccard similarity over token sets.
  static double textSimilarity(String a, String b) {
    final ta = tokenize(a).toSet();
    final tb = tokenize(b).toSet();
    if (ta.isEmpty || tb.isEmpty) return 0;
    var inter = 0;
    for (final t in ta) {
      if (tb.contains(t)) inter++;
    }
    final union = ta.length + tb.length - inter;
    return union == 0 ? 0 : inter / union;
  }

  /// Splits text into sentences (after . ! ?) like the original `split(/(?<=[.!?])\s+/)`.
  static List<String> splitSentences(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.trim().isNotEmpty).toList();
  }

  static String csvEscape(Object? v) {
    final s = v == null ? '' : v.toString();
    if (RegExp(r'[",\n]').hasMatch(s)) return '"${s.replaceAll('"', '""')}"';
    return s;
  }

  /// Word-level LCS diff. Each op is `DiffOp('same'|'add'|'remove', text)`.
  static List<DiffOp> diffWords(String? oldStr, String? newStr) {
    final a = _splitKeepWs(oldStr ?? '');
    final b = _splitKeepWs(newStr ?? '');
    final n = a.length, m = b.length;
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1]);
      }
    }
    final ops = <DiffOp>[];
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (a[i] == b[j]) {
        ops.add(DiffOp('same', a[i]));
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        ops.add(DiffOp('remove', a[i]));
        i++;
      } else {
        ops.add(DiffOp('add', b[j]));
        j++;
      }
    }
    while (i < n) {
      ops.add(DiffOp('remove', a[i++]));
    }
    while (j < m) {
      ops.add(DiffOp('add', b[j++]));
    }
    return ops;
  }

  /// Equivalent of JS `str.split(/(\s+)/)`: tokens and whitespace runs interleaved.
  static List<String> _splitKeepWs(String s) {
    final out = <String>[];
    var last = 0;
    for (final m in RegExp(r'\s+').allMatches(s)) {
      out.add(s.substring(last, m.start));
      out.add(m.group(0)!);
      last = m.end;
    }
    out.add(s.substring(last));
    return out;
  }

  /// Turns a title into a safe, human-readable file name (no extension).
  static String fileSafe(String title, {String fallback = 'Untitled'}) {
    var s = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'^\.+'), '').trim();
    if (s.length > 80) s = s.substring(0, 80).trim();
    return s.isEmpty ? fallback : s;
  }

  static String slug(String s) {
    final v = s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return v;
  }
}

class DiffOp {
  /// 'same' | 'add' | 'remove'
  final String type;
  final String text;
  const DiffOp(this.type, this.text);
}
