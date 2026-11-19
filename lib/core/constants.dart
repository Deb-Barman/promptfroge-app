/// Type definitions for the static reference data. The data itself lives in
/// `constants_data.dart`, which is generated from the original HTML app.
export 'constants_data.dart';
import 'constants_data.dart';

class CategoryDef {
  final String id;
  final String label;
  final int color;
  const CategoryDef(this.id, this.label, this.color);
}

class StatusDef {
  final String id;
  final String label;
  final int color;
  const StatusDef(this.id, this.label, this.color);
}

class BlockType {
  final String id;
  final String label;
  final int color;
  final String placeholder;
  const BlockType(this.id, this.label, this.color, this.placeholder);
}

/// A block inside a built-in builder preset.
class BlockDef {
  final String type;
  final String? label;
  final int? color;
  const BlockDef(this.type, {this.label, this.color});
}

class BuilderPreset {
  final String id;
  final String name;
  final List<BlockDef> blocks;
  const BuilderPreset(this.id, this.name, this.blocks);
}

class ModelSpec {
  final String id;
  final String label;
  final String vendor;
  final String group;
  final double charsPerToken;
  final int contextWindow;
  final double priceIn;
  final double priceOut;
  final String priceNote;
  final String idiomKey;

  /// "cl100k" or "estimate". The Flutter port always uses the heuristic estimate
  /// (see docs/MIGRATION.md - the 600 KB embedded BPE vocabulary was not ported).
  final String tokenizer;
  const ModelSpec({
    required this.id,
    required this.label,
    required this.vendor,
    required this.group,
    required this.charsPerToken,
    required this.contextWindow,
    required this.priceIn,
    required this.priceOut,
    required this.priceNote,
    required this.idiomKey,
    required this.tokenizer,
  });
}

class ModelIdiom {
  final String label;
  final String comparative;
  final List<String> tips;
  const ModelIdiom(this.label, this.comparative, this.tips);
}

class ScoreWeights {
  final double clarity, context, specificity, structure, constraints, output, ambiguity;
  const ScoreWeights({
    required this.clarity,
    required this.context,
    required this.specificity,
    required this.structure,
    required this.constraints,
    required this.output,
    required this.ambiguity,
  });
}

class ScoringProfile {
  final String id;
  final String label;
  final ScoreWeights weights;
  const ScoringProfile(this.id, this.label, this.weights);
}

class Challenge {
  final String id;
  final String level;
  final String title;
  final String prompt;
  final String task;
  final List<String> checkKeywords;
  const Challenge(this.id, this.level, this.title, this.prompt, this.task, this.checkKeywords);
}

class ConstraintAtom {
  final String id;
  final String category;
  final String label;
  final String text;
  const ConstraintAtom(this.id, this.category, this.label, this.text);
}

class EdgeCaseItem {
  final String id;
  final String label;
  final String question;
  const EdgeCaseItem(this.id, this.label, this.question);
}

class SecurityPattern {
  final String id;
  final String label;
  final RegExp re;
  SecurityPattern(this.id, this.label, this.re);
}

class RiskPattern {
  final String id;
  final String label;
  final RegExp re;
  final String detail;
  RiskPattern(this.id, this.label, this.re, this.detail);
}

class Persona {
  final String id;
  final String label;
  final String text;
  const Persona(this.id, this.label, this.text);
}

class SimpleOption {
  final String id;
  final String label;
  const SimpleOption(this.id, this.label);
}

const List<SimpleOption> kPromptFormats = [
  SimpleOption('text', 'Text'),
  SimpleOption('json', 'JSON'),
  SimpleOption('xml', 'XML'),
  SimpleOption('markdown', 'Markdown'),
];

const List<SimpleOption> kOutputFormatHints = [
  SimpleOption('none', 'No default'),
  SimpleOption('prose', 'Prose / paragraphs'),
  SimpleOption('bullets', 'Bullet list'),
  SimpleOption('json', 'JSON'),
  SimpleOption('markdown', 'Markdown'),
  SimpleOption('table', 'Table'),
  SimpleOption('code', 'Code only'),
];

const List<SimpleOption> kAutosaveIntervals = [
  SimpleOption('500', 'Fast (0.5s)'),
  SimpleOption('900', 'Normal (0.9s)'),
  SimpleOption('2000', 'Relaxed (2s)'),
  SimpleOption('5000', 'Slow (5s)'),
];

const List<SimpleOption> kVersionRetention = [
  SimpleOption('10', 'Last 10 versions'),
  SimpleOption('25', 'Last 25 versions'),
  SimpleOption('50', 'Last 50 versions'),
  SimpleOption('0', 'Unlimited'),
];

const List<SimpleOption> kEditorFonts = [
  SimpleOption('jetbrains', 'JetBrains Mono'),
  SimpleOption('fira', 'Fira Code'),
  SimpleOption('system', 'System Monospace'),
  SimpleOption('ibm', 'IBM Plex Mono'),
];

/// Font-family fallbacks for each editor font (fonts are optional assets; see README).
const Map<String, List<String>> kEditorFontFallbacks = {
  'jetbrains': ['JetBrains Mono', 'Menlo', 'Roboto Mono', 'monospace'],
  'fira': ['Fira Code', 'JetBrains Mono', 'Menlo', 'monospace'],
  'system': ['Menlo', 'Roboto Mono', 'monospace'],
  'ibm': ['IBM Plex Mono', 'JetBrains Mono', 'Menlo', 'monospace'],
};

CategoryDef categoryById(String id) => kCategories.firstWhere((c) => c.id == id, orElse: () => kCategories.last);

StatusDef statusById(String id) => kStatuses.firstWhere((c) => c.id == id, orElse: () => kStatuses.first);

BlockType? blockTypeById(String id) {
  for (final b in kBlockTypes) {
    if (b.id == id) return b;
  }
  return null;
}
