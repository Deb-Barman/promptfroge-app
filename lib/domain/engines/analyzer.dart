import '../../core/constants.dart';
import '../../core/util.dart';
import '../models.dart';
import 'template_engine.dart';

class Issue {
  /// ok | warn | error
  final String level;
  final String msg;
  const Issue(this.level, this.msg);
}

class AnalysisResult {
  /// clarity, context, specificity, structure, constraints, output, completeness, ambiguity (= 100 - ambiguity)
  final Map<String, int> scores;
  final int overall;
  final List<Issue> issues;

  /// role, context, task, constraints, output, examples, mustNotConstraints, mustConstraints
  final Map<String, bool> has;
  final int wordCount;
  final List<String> undefinedVars;
  final String profileId;
  const AnalysisResult({
    required this.scores,
    required this.overall,
    required this.issues,
    required this.has,
    required this.wordCount,
    required this.undefinedVars,
    required this.profileId,
  });
}

class DnaEntry {
  final String id;
  final String label;
  final int color;
  final double strength;
  const DnaEntry({required this.id, required this.label, required this.color, required this.strength});
}

class Improvement {
  final String title;
  final String detail;
  const Improvement(this.title, this.detail);
}

int _ci(num v, int lo, int hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v.toInt();
}

double _cd(double v, double lo, double hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

/// Port of the original rule-based `Analyzer` (no AI, purely local heuristics).
class Analyzer {
  Analyzer._();

  static final Map<String, RegExp> cues = <String, RegExp>{
    'role': RegExp(r'\b(?:you are|act as|as an? (?:expert|professional|senior|certified)|your role is|assume the (?:role|persona) of)\b', caseSensitive: false),
    'context': RegExp(r'\b(?:context:|background:|given that|here is (?:some|the) (?:context|background)|for context)', caseSensitive: false),
    'task': RegExp(
        r'\b(?:task:|your task is|please (?:write|create|generate|build|analyze|summarize|extract|translate|design|review|explain)|i need you to|i want you to)',
        caseSensitive: false),
    'constraints': RegExp(
        r'\b(?:constraints?:|constraint|must not|do not|avoid|limit|no more than|at least|under \d+|only use|restrict|shall not|forbidden|never)',
        caseSensitive: false),
    'output': RegExp(
        r'\b(?:output format:?|output:|respond (?:with|in)|format:|return (?:a|as|the)|answer (?:in|as)|reply (?:in|with)|as (?:json|a table|a list|markdown|bullet points))',
        caseSensitive: false),
    'examples': RegExp(r"\b(?:examples?:|for example|e\.g\.|input:.*output:|here(?:'s| is) an example)", caseSensitive: false),
  };

  static final RegExp _mustNot = RegExp(r"\b(?:must not|do not|don't|avoid|never|forbidden|shall not|no more than|restrict(?:ed)?)\b", caseSensitive: false);
  static final RegExp _must = RegExp(r'\b(?:must(?!\s*not)|should|required?|at least|only use|has to|need to)\b', caseSensitive: false);
  static final RegExp _vague = RegExp(r'\b(something|somehow|stuff|things|handle|improve|better|nice|good|various|etc\.?|maybe|sort of|kind of)\b', caseSensitive: false);
  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _quotedTerms = RegExp('["\'“][^"\'”]{2,40}["\'”]');
  static final RegExp _nonAlnum = RegExp(r'[^a-z0-9\s]');

  static final List<List<RegExp>> _conflictPairs = <List<RegExp>>[
    <RegExp>[
      RegExp(r'\bbe (extremely|very) (detailed|thorough|comprehensive)\b', caseSensitive: false),
      RegExp(r'\b(under|no more than|at most)\s+\d{1,3}\s*words?\b', caseSensitive: false),
    ],
    <RegExp>[RegExp(r'\balways\b', caseSensitive: false), RegExp(r'\bnever\b', caseSensitive: false)],
    <RegExp>[RegExp(r'\bmust\b', caseSensitive: false), RegExp(r'\boptional(ly)?\b', caseSensitive: false)],
  ];

  static ScoringProfile _profile(String? id) {
    for (final p in kScoringProfiles) {
      if (p.id == id) return p;
    }
    return kScoringProfiles.first;
  }

  static AnalysisResult analyze(String? text, {String? profileId}) {
    final raw = text ?? '';
    final words = Utils.tokenize(raw);
    final wordCount = words.length;
    final sentences = Utils.splitSentences(raw);
    final issues = <Issue>[];

    final has = <String, bool>{};
    cues.forEach((key, re) {
      has[key] = re.hasMatch(raw);
    });
    has['mustNotConstraints'] = _mustNot.hasMatch(raw);
    has['mustConstraints'] = _must.hasMatch(raw);

    // --- Clarity ---
    final vagueWords = _vague.allMatches(raw).length;
    final avgSentenceLen = sentences.isNotEmpty ? wordCount / sentences.length : 0.0;
    var clarity = 100;
    if (avgSentenceLen > 28) {
      clarity -= 20;
    } else if (avgSentenceLen > 20) {
      clarity -= 10;
    }
    clarity -= _ci(vagueWords * 8, 0, 40);
    if (wordCount < 6) clarity -= 30;
    clarity = _ci(clarity, 0, 100);
    if (vagueWords > 0) {
      issues.add(Issue('warn',
          '$vagueWords vague word${vagueWords > 1 ? "s" : ""} detected (e.g. "handle", "improve") — replace with specifics.'));
    }

    // --- Context ---
    var context = has['context']! ? 85 : 30;
    if (!has['context']! && wordCount > 40) context = 45;
    if (!has['context']!) issues.add(const Issue('warn', 'No explicit context/background section detected.'));

    // --- Specificity ---
    final hasNumbers = _digit.hasMatch(raw);
    final hasQuotedTerms = _quotedTerms.hasMatch(raw);
    var specificity = 40;
    if (hasNumbers) specificity += 20;
    if (hasQuotedTerms) specificity += 15;
    if (has['output']!) specificity += 15;
    if (wordCount > 15) specificity += 10;
    specificity = _ci(specificity, 0, 100);

    // --- Structure ---
    var structure = 20;
    if (has['role']!) structure += 20;
    if (has['task']!) structure += 25;
    if (has['output']!) structure += 20;
    if (has['constraints']!) structure += 15;
    structure = _ci(structure, 0, 100);
    if (!has['role']!) {
      issues.add(const Issue('warn', "No role/persona assigned — consider 'You are a ...' for domain-sensitive tasks."));
    }
    if (!has['task']!) issues.add(const Issue('error', 'No clear task instruction detected.'));

    // --- Constraints ---
    final constraints = has['constraints']! ? 80 : 20;
    if (!has['constraints']!) {
      issues.add(const Issue('warn', 'No constraints specified — output shape/length/tone may be unpredictable.'));
    }

    // --- Output ---
    final output = has['output']! ? 90 : 15;
    if (!has['output']!) {
      issues.add(const Issue('error', 'No output format specified — the model has to guess the shape of the response.'));
    }

    // --- Completeness (the original counts every key of `has`, including the two sub-signals) ---
    final cueCount = has.values.where((v) => v).length;
    final completeness = _ci(((cueCount / 6) * 100).round(), 0, 100);

    // --- Ambiguity ---
    final undefinedVars = TemplateEngine.extractVariables(raw);
    var ambiguity = _ci(100 - clarity + vagueWords * 5, 0, 100);
    if (undefinedVars.isNotEmpty) {
      ambiguity = _ci(ambiguity + undefinedVars.length * 8, 0, 100);
      final shown = undefinedVars.take(4).map((v) => '{{' + v + '}}').join(', ');
      issues.add(Issue('warn',
          '${undefinedVars.length} undefined template variable${undefinedVars.length > 1 ? "s" : ""}: $shown${undefinedVars.length > 4 ? "…" : ""}'));
    }

    // --- Repeated / conflicting instructions ---
    final seenSentences = <String, int>{};
    for (final s in sentences) {
      final norm = s.toLowerCase().replaceAll(_nonAlnum, '').trim();
      if (norm.length < 8) continue;
      seenSentences[norm] = (seenSentences[norm] ?? 0) + 1;
    }
    final repeats = seenSentences.values.where((c) => c > 1).length;
    if (repeats > 0) {
      issues.add(Issue('warn', '$repeats repeated instruction${repeats > 1 ? "s" : ""} detected — duplicate sentences can dilute emphasis.'));
    }

    var conflicts = 0;
    for (final pair in _conflictPairs) {
      if (pair[0].hasMatch(raw) && pair[1].hasMatch(raw)) conflicts++;
    }
    if (conflicts > 0) {
      issues.add(const Issue('error', 'Potentially conflicting instructions detected (e.g. exhaustive detail + a tight word limit).'));
    }

    if (wordCount > 0 && wordCount < 5) {
      issues.add(const Issue('error', 'Prompt is extremely short — the model has very little to work with.'));
    }

    if (issues.isEmpty) {
      issues.add(const Issue('ok', 'No structural issues detected — this prompt covers the core elements.'));
    }

    final scores = <String, int>{
      'clarity': clarity,
      'context': context,
      'specificity': specificity,
      'structure': structure,
      'constraints': constraints,
      'output': output,
      'completeness': completeness,
      'ambiguity': 100 - ambiguity,
    };
    final w = _profile(profileId).weights;
    final overallRaw = scores['clarity']! * w.clarity +
        scores['context']! * w.context +
        scores['specificity']! * w.specificity +
        scores['structure']! * w.structure +
        scores['constraints']! * w.constraints +
        scores['output']! * w.output +
        scores['ambiguity']! * w.ambiguity;
    final overall = _ci(overallRaw.round(), 0, 100);

    return AnalysisResult(
      scores: scores,
      overall: overall,
      issues: issues,
      has: has,
      wordCount: wordCount,
      undefinedVars: undefinedVars,
      profileId: (profileId == null || profileId.isEmpty) ? 'default' : profileId,
    );
  }

  /// Prompt DNA: one entry per built-in block type (strength 0..1), custom blocks appended.
  static List<DnaEntry> dnaProfile(String? text, List<PromptBlock>? blocks) {
    final raw = text ?? '';
    final entries = <DnaEntry>[];
    if (blocks != null && blocks.isNotEmpty) {
      for (final type in kBlockTypes) {
        PromptBlock? block;
        for (final b in blocks) {
          if (b.type == type.id) {
            block = b;
            break;
          }
        }
        final len = block != null ? block.text.trim().length : 0;
        entries.add(DnaEntry(
          id: type.id,
          label: type.label,
          color: type.color,
          strength: len > 0 ? _cd(0.35 + len / 240, 0.35, 1.0) : 0.0,
        ));
      }
      for (final block in blocks) {
        if (!block.type.startsWith('custom_')) continue;
        final len = block.text.trim().length;
        final label = (block.label == null || block.label!.isEmpty) ? 'Custom Section' : block.label!;
        entries.add(DnaEntry(
          id: block.type,
          label: label,
          color: block.color ?? 0xFF9B7FE0,
          strength: _cd(0.35 + len / 240, 0.15, 1.0),
        ));
      }
      return entries;
    }
    for (final type in kBlockTypes) {
      final re = cues[type.id];
      entries.add(DnaEntry(
        id: type.id,
        label: type.label,
        color: type.color,
        strength: (re != null && re.hasMatch(raw)) ? 0.75 : 0.0,
      ));
    }
    return entries;
  }

  /// Rule-based improvement suggestions (never claims to be AI-generated).
  static List<Improvement> improve(String? text) {
    final result = analyze(text);
    final s = <Improvement>[];
    if (!result.has['role']!) {
      s.add(const Improvement('Add a role', "Open with 'You are a [specific expert]...' to calibrate vocabulary and judgment."));
    }
    if (!result.has['context']!) {
      s.add(const Improvement('Add context', 'State the background the model needs — audience, existing constraints, prior state.'));
    }
    if (!result.has['task']!) {
      s.add(const Improvement('State the task explicitly', "Lead with a direct instruction: 'Write...', 'Analyze...', 'Extract...'."));
    }
    if (!result.has['constraints']!) {
      s.add(const Improvement('Add constraints', 'Specify length, tone, format restrictions, or things to avoid.'));
    }
    if (!result.has['output']!) {
      s.add(const Improvement('Define the output format', 'Say exactly what shape the answer should take — list, JSON, table, word count.'));
    }
    if (result.scores['clarity']! < 60) {
      s.add(const Improvement('Reduce vague language', "Replace words like 'better', 'handle', 'improve' with concrete criteria."));
    }
    if (result.wordCount < 8) {
      s.add(const Improvement('Expand the prompt', 'Very short prompts leave too much to guesswork — add at least a role, task, and format.'));
    }
    if (result.undefinedVars.isNotEmpty) {
      s.add(Improvement('Fill in template variables', '${result.undefinedVars.length} variable(s) are still unfilled placeholders.'));
    }
    return s;
  }
}
