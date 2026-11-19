# Domain engine API (contract)

Pure Dart (no Flutter imports except `highlighter.dart`, which may import `package:flutter/painting.dart`).
All files live in `lib/domain/engines/`. They are ports of the original `PromptForge.html` objects
of the same names. **Behaviour must match the original** (read the JS in `/mnt/user-data/uploads/PromptForge.html`);
where Dart differs from JS regex semantics, keep results identical for the test fixtures.

Imports available: `../../core/util.dart` (Utils), `../../core/constants.dart` (all `k*` tables + classes),
`../models.dart`, `../../data/vault/vault_repository.dart` (`VaultData`).
Library-wide rule: NO network, NO AI calls. Everything is local heuristics.

## template_engine.dart
```dart
class VarSpec { final String name; final String type; /* text|number|multiline|select */
  final String defaultValue; final List<String> options; const VarSpec(...); }
class SpanCandidate { final String text; final String kind; /* quoted|number|phrase */ final int index; }
class VarReplacement { final String text; final String varName; const VarReplacement(this.text, this.varName); }
class TemplateEngine {
  static List<VarSpec> extractVariableSpecs(String? body);
  static List<String> extractVariables(String? body);
  static String render(String? body, Map<String, String> values);
  static bool hasUnfilledVariables(String? body);
  static String humanizeVarName(String name);
  static String composeFromBlocks(List<PromptBlock> blocks);       // label = block.label ?? kBlockTypes label ?? type
  static String blockLabel(PromptBlock b);
  static int blockColor(PromptBlock b);                            // ARGB int
  static List<SpanCandidate> detectParameterizableSpans(String? body);
  static String applyExtractedVariables(String body, List<VarReplacement> replacements);
}
```

## analyzer.dart
```dart
class Issue { final String level; /* ok|warn|error */ final String msg; }
class AnalysisResult { final Map<String,int> scores; /* clarity, context, specificity, structure, constraints, output, completeness, ambiguity(=100-ambiguity) */
  final int overall; final List<Issue> issues; final Map<String,bool> has; final int wordCount;
  final List<String> undefinedVars; final String profileId; }
class DnaEntry { final String id; final String label; final int color; final double strength; }
class Improvement { final String title; final String detail; }
class Analyzer {
  static final Map<String, RegExp> cues;  // role, context, task, constraints, output, examples
  static AnalysisResult analyze(String? text, {String? profileId});
  static List<DnaEntry> dnaProfile(String? text, List<PromptBlock>? blocks);
  static List<Improvement> improve(String? text);
}
```

## highlighter.dart  (may import flutter/painting)
```dart
class HighlightColors { final Color header, variable, comment, constraint, key, string, number, keyword, punct, tag, attr, attrValue, mdHeader, mdCode, mdQuote, mdList, mdBold, mdLink;
  const HighlightColors.dark(); const HighlightColors.light(); }
class PromptHighlighter {
  /// Single-pass tokenisers, same token classes as the original (text, json, xml, markdown).
  static TextSpan build(String text, String format, TextStyle base, HighlightColors colors);
}
```
Invariant: concatenated span text MUST equal the input text exactly (the editor depends on this).

## cleaner.dart  (PromptCleaner, SecurityScanner, RiskLinter)
```dart
class CleanFinding { final String type; final String detail; }
class PromptCleaner { static List<CleanFinding> inspect(String? text); static String autoClean(String? text); }
class SecurityFinding { final String id; final String label; final int count; final String sample; }
class SecurityScanner { static List<SecurityFinding> scan(String? text); }
class RiskFinding { final String id; final String label; final String detail; }
class RiskLinter { static List<RiskFinding> scan(String? text); }   // uses kRiskPatterns
```

## tools.dart  (PromptTools + editor transforms)
```dart
class PromptTools {
  static String shorten(String? t); static String bulletify(String? t); static String chainOfThoughtBlock();
  static String? tableify(String? t);              // null when nothing list-like
  static const List<String> tones;                 // formal, casual, persuasive, neutral
  static String toneShift(String? t, String tone);
  static List<AmbiguityFinding> scanAmbiguity(String? t);   // {sentence,index}
  static List<AdversarialFinding> scanAdversarial(String? t); // {id,label}
  static List<RedundancyFinding> findInternalRedundancy(String? t); // {a,b}
}
class ModelAdapter {                                // original "Adapt for..." modal + "Wrap in XML tags" + "Copy as"
  static String adapt(String body, String fromFormat, String idiomKey);   // idiomKey: claude | openai | gemini | generic
  static String wrapInXml(String body, [String fromFormat = 'text']);
  static String copyAs(String text, String style);     // read original openCopyAsModal for the styles; expose `static const List<SimpleOption> copyStyles`
}
```

## bpe_tokenizer.dart / graph_layout.dart / core/date_parse.dart  (pure Dart, golden-tested)

`Cl100kTokenizer.fromGzip(bytes).countTokens(text)` is the exact GPT tokenizer; attach it with `TokenEstimator.attachTokenizer`.
`GraphLayout.layout(ids, edges, width, height)` is the deterministic force layout. `parseFlexibleDate(text)` reads
"12 sep 2026", "2026-09-12", "12/9/2026", today and yesterday.

## token_estimator.dart  (+ readability)
```dart
class TokenEstimate { final int promptTokens; final int completionTokens; final double cost; final ModelSpec model; }
class ContextStatus { final int tokens; final int limit; final double pct; final String level; /* ok|warn|over */ }
class TokenEstimator {
  static List<ModelSpec> allModels(List<CustomModel> custom);          // kModels + custom mapped to ModelSpec (tokenizer 'estimate')
  static ModelSpec getModel(String id, List<CustomModel> custom);      // falls back to the 'generic' model
  static int estimateTokens(String? text, String modelId, List<CustomModel> custom);   // ALWAYS heuristic chars/charsPerToken
  static TokenEstimate estimateCost(String? text, String modelId, List<CustomModel> custom, {int? completionTokens});
  static ContextStatus contextStatus(String? text, String modelId, List<CustomModel> custom);
}
class ReadabilityResult { final int fleschScore; final double gradeLevel, avgSentenceLen, avgWordLen, syllablesPerWord; final String label; }
class ReadabilityEngine { static int countSyllables(String w); static ReadabilityResult analyze(String? text); }   // file: readability.dart
```
(The original embeds a 600 KB cl100k BPE vocabulary; it is intentionally NOT ported. UI must label counts "estimate".)

## format_converter.dart / validator.dart
```dart
class Section { final String label; final String content; }
class FormatConverter { static List<Section> extractSections(String? t, String from); static String convert(String? t, String from, String to); }
class ValidationResult { final bool valid; final String message; final int? line; final int? column; }
class PromptValidator { static ValidationResult validate(String? text, String format); }   // json via dart:convert, xml via a small well-formedness checker; text/markdown always valid
```

## search_engine.dart  (SearchEngine, TriggerDetector, link graph, SuggestionEngine)
```dart
class SearchResult { final String kind; /* prompt|template|snippet|pattern */ final String id; final String title; final String snippet; final int score; }
class SearchEngine {
  static List<SearchResult> search(VaultData d, String query, {Set<String> types = const {'prompts','templates','snippets'}, int limit = 30});
  static List<RelatedPrompt> relatedTo(VaultData d, String promptId, String text, {int limit = 5});   // {Prompt prompt; double sim}
}
class LinkGraph { final List<GraphNode> nodes; final List<GraphEdge> edges; final List<BrokenLink> brokenLinks; }
//   GraphNode{id,title,updatedAt} GraphEdge{source,target} BrokenLink{sourceId,sourceTitle,targetTitle}
class LinkGraphBuilder { static LinkGraph build(Iterable<Prompt> activePrompts); }   // [[Title]] wiki links, case-insensitive
class TriggerMatch { final String prefix; final String query; final String fullMatch; }
class SuggestionItem { final String label; final String text; final String src; /* snippet|prompt|pattern|template|block|link|variable|phrase */ final String? meta; final int matchLen; }
class TriggerDetector {
  static TriggerMatch? detect(String textBeforeCursor);              // / // /// \ \\ @
  static String? kindForPrefix(String prefix);
  static List<SuggestionItem> candidatesFor(String kind, String query, VaultData d);
}
class SuggestionEngine {                                              // learned n-gram phrase completion + variable-name suggestions
  SuggestionEngine(); void rebuild(VaultData d);
  List<SuggestionItem> phraseSuggestions(String textBeforeCursor, {int limit = 4});
  List<SuggestionItem> variableSuggestions(String partial, {int limit = 6});   // names seen in {{vars}} across the vault
  List<MapEntry<String,int>> topWords(int n);
}
```

## analytics.dart / duplicate_finder.dart
```dart
class DayCount { final String label; final int count; final int date; }
class AnalyticsSummary { final int totalPrompts, totalTemplates, totalSnippets, totalWords, avgLen, favoriteCount;
  final Map<String,int> byCategory; final Map<String,int> byStatus; final List<DayCount> activity; /* last 14 days */
  final List<MapEntry<String,int>> topWords; final double avgScore; /* mean Analyzer overall of active prompts */
  final List<MapEntry<String,int>> mostUsed; /* prompt title -> useCount, top 5 */ }
class AnalyticsEngine { static AnalyticsSummary summary(VaultData d, SuggestionEngine se, {String? profileId}); }
class DuplicateGroup { final List<Prompt> prompts; final double similarity; }
class DuplicateFinder { static List<DuplicateGroup> find(Iterable<Prompt> prompts, {double threshold}); }  // read original DuplicateFinder for the threshold/metric
```

## exporter.dart / importer.dart
```dart
class ExportItem { final String id; final String kind; /* prompt|template|pattern|chain|snippet|history */
  final String title; final String body; final int updatedAt; final Map<String,dynamic> meta; }
class Exporter {
  static const List<String> allKinds = ['prompts','templates','patterns','chains','shortcuts','history'];
  static List<ExportItem> collect(VaultData d, Set<String> kinds, {Map<String, List<PromptVersion>> versions = const {}});
  static String toMarkdown(List<ExportItem> items, {String coverNote = ''});
  static String toTxt(List<ExportItem> items, {String coverNote = ''});
  static String toCsv(List<ExportItem> items);
  static String toHtml(List<ExportItem> items, {String coverNote = ''});
  // The JSON export is the full backup only (as in the original); there is no per-item toJson.
}
class JsonImporter {
  static List<Map<String, dynamic>> parse(String text, String kind);   // tolerant keys; single object or array
  static Prompt toPrompt(Map<String, dynamic> m);
  static Template toTemplate(Map<String, dynamic> m);
  static PromptPattern toPattern(Map<String, dynamic> m);
}
class BackupContents { final VaultData data; final List<PromptVersion> versions; final Map counts; final int? exportedAt; }
class BackupParser { static BackupContents? parse(String raw); }   // original HTML-app backups AND this app's backups
```

## Tests
`test/engines/*_test.dart`. Expected values for analyzer/template/cleaner/tools/search/format/diff tests MUST come from
running the ORIGINAL JavaScript (see `tool/golden/` — write a node script that loads the JS objects out of the HTML and
dumps JSON goldens; commit the goldens under `test/goldens/` and have the Dart tests read them with `dart:io`).
Do not write expected values by hand.

## Additional real shapes (tools.dart)
`PromptTools.checkInjectionSurface(String?) -> List<InjectionFinding(id,label,detail)>`;
`MessageComposer.render(body, format, modelId, vendor)` renders the "Copy as" formats (e.g. `openai_json`).
