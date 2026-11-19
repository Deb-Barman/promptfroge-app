import '../../core/util.dart';

class ReadabilityResult {
  final int fleschScore;
  final double gradeLevel;
  final double avgSentenceLen;
  final double avgWordLen;
  final double syllablesPerWord;
  final String label;
  const ReadabilityResult(this.fleschScore, this.gradeLevel, this.avgSentenceLen, this.avgWordLen, this.syllablesPerWord, this.label);
}

class ReadabilityEngine {
  ReadabilityEngine._();

  static int countSyllables(String? word) {
    final w = (word ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (w.isEmpty) return 0;
    if (w.length <= 3) return 1;
    final stripped = w.replaceFirst(RegExp(r'e$'), '').replaceFirst(RegExp(r'^y'), '');
    final groups = RegExp(r'[aeiouy]+').allMatches(stripped).length;
    var count = groups == 0 ? 1 : groups;
    if (w.endsWith('le') && w.length > 2 && !'aeiouy'.contains(w[w.length - 3])) count++;
    return count < 1 ? 1 : count;
  }

  static double _r1(double v) => (v * 10).round() / 10;
  static double _r2(double v) => (v * 100).round() / 100;

  static ReadabilityResult analyze(String? text) {
    final raw = text ?? '';
    final words = Utils.tokenize(raw);
    final sentences = Utils.splitSentences(raw);
    final wordCount = words.length;
    final sentenceCount = sentences.isEmpty ? 1 : sentences.length;
    if (wordCount == 0) return const ReadabilityResult(0, 0, 0, 0, 0, '—');

    var totalSyllables = 0;
    var totalChars = 0;
    for (final w in words) {
      totalSyllables += countSyllables(w);
      totalChars += w.length;
    }
    final avgSentenceLen = wordCount / sentenceCount;
    final spw = totalSyllables / wordCount;
    final avgWordLen = totalChars / wordCount;

    final flesch = Utils.clamp(206.835 - 1.015 * avgSentenceLen - 84.6 * spw, 0, 100).toDouble();
    final grade = Utils.clamp(0.39 * avgSentenceLen + 11.8 * spw - 15.59, 0, 18).toDouble();

    var label = 'Very difficult';
    if (flesch >= 90) {
      label = 'Very easy';
    } else if (flesch >= 70) {
      label = 'Easy';
    } else if (flesch >= 50) {
      label = 'Standard';
    } else if (flesch >= 30) {
      label = 'Difficult';
    }
    return ReadabilityResult(flesch.round(), _r1(grade), _r1(avgSentenceLen), _r1(avgWordLen), _r2(spw), label);
  }
}
