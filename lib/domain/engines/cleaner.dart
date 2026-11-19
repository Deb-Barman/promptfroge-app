import '../../core/constants.dart';
import '../../core/util.dart';

class CleanFinding {
  final String type;
  final String detail;
  const CleanFinding(this.type, this.detail);
}

/// Mechanical checks and safe auto-fixes (whitespace only).
class PromptCleaner {
  PromptCleaner._();

  static final RegExp _nonAlnum = RegExp(r'[^a-z0-9\s]');

  static List<CleanFinding> inspect(String? text) {
    final raw = text ?? '';
    final findings = <CleanFinding>[];

    final sentences = Utils.splitSentences(raw).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final seen = <String, List<int>>{};
    for (var i = 0; i < sentences.length; i++) {
      final norm = sentences[i].toLowerCase().replaceAll(_nonAlnum, '');
      if (norm.length < 8) continue;
      seen.putIfAbsent(norm, () => <int>[]).add(i);
    }
    for (final idxs in seen.values) {
      if (idxs.length > 1) {
        findings.add(CleanFinding('duplicate_sentence', 'Sentence repeated ${idxs.length}x: "${Utils.truncate(sentences[idxs.first], 60)}"'));
      }
    }

    if (RegExp(r'\s{3,}').hasMatch(raw)) {
      findings.add(const CleanFinding('whitespace', 'Excessive whitespace (3+ consecutive spaces) found.'));
    }
    if (RegExp(r'\n{4,}').hasMatch(raw)) {
      findings.add(const CleanFinding('whitespace', 'Excessive blank lines (3+ in a row) found.'));
    }

    final openBraces = RegExp(r'\{\{').allMatches(raw).length;
    final closeBraces = RegExp(r'\}\}').allMatches(raw).length;
    if (openBraces != closeBraces) {
      findings.add(CleanFinding('broken_template', 'Unbalanced template braces: $openBraces "{{" vs $closeBraces "}}".'));
    }
    if (RegExp(r'\{\{\s*\}\}').hasMatch(raw)) {
      findings.add(const CleanFinding('broken_template', 'Empty {{}} placeholder found.'));
    }

    final pairs = <List<RegExp>>[
      [RegExp(r'\balways\b', caseSensitive: false), RegExp(r'\bnever\b', caseSensitive: false)],
      [RegExp(r'\bmust\b', caseSensitive: false), RegExp(r'\boptional(ly)?\b', caseSensitive: false)],
    ];
    for (final p in pairs) {
      if (p[0].hasMatch(raw) && p[1].hasMatch(raw)) {
        findings.add(const CleanFinding('conflict', "Conflicting absolute instructions detected (e.g. 'always' and 'never')."));
      }
    }
    return findings;
  }

  static String autoClean(String? text) {
    return (text ?? '')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .trim();
  }
}

class SecurityFinding {
  final String id;
  final String label;
  final int count;
  final String sample;
  const SecurityFinding(this.id, this.label, this.count, this.sample);
}

/// Detects leaked secrets (API keys, tokens, passwords...).
class SecurityScanner {
  SecurityScanner._();

  static List<SecurityFinding> scan(String? text) {
    if (text == null || text.isEmpty) return const [];
    final findings = <SecurityFinding>[];
    for (final pat in kSecurityPatterns) {
      final matches = pat.re.allMatches(text).toList();
      if (matches.isNotEmpty) {
        findings.add(SecurityFinding(pat.id, pat.label, matches.length, _mask(matches.first.group(0)!)));
      }
    }
    return findings;
  }

  static String _mask(String s) {
    if (s.length <= 8) return '${s.substring(0, s.length < 2 ? s.length : 2)}***';
    return '${s.substring(0, 5)}…${s.substring(s.length - 3)}';
  }
}

class RiskFinding {
  final String id;
  final String label;
  final String detail;
  const RiskFinding(this.id, this.label, this.detail);
}

/// Flags phrasing that is risky to ship to a model (e.g. absolute guarantees).
class RiskLinter {
  RiskLinter._();

  static List<RiskFinding> scan(String? text) {
    final raw = text ?? '';
    final out = <RiskFinding>[];
    for (final p in kRiskPatterns) {
      if (p.re.hasMatch(raw)) out.add(RiskFinding(p.id, p.label, p.detail));
    }
    return out;
  }
}
