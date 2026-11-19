// Exact cl100k token counts must equal what the ORIGINAL JavaScript RealTokenizer produced (goldens).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_forge/domain/engines/bpe_tokenizer.dart';
import 'package:prompt_forge/domain/engines/token_estimator.dart';

import '../support/golden.dart';

void main() {
  final g = Goldens.load();
  final tk = Cl100kTokenizer.fromGzip(File('assets/data/cl100k.gz').readAsBytesSync());

  test('vocabulary decodes to the cl100k_base size', () {
    expect(tk.vocabSize, greaterThan(100000));
  });

  group('exact counts match the original RealTokenizer', () {
    final texts = (g['tokens']['texts'] as List).cast<String>();
    final counts = (g['tokens']['counts'] as List).cast<int>();
    for (var i = 0; i < texts.length; i++) {
      test('text #$i', () => expect(tk.countTokens(texts[i]), counts[i], reason: texts[i]));
    }
  });

  group('TokenEstimator uses the real tokenizer only for cl100k models', () {
    final est = g.list('tokenEstimate');
    final prompts = g.prompts;
    test('before attach: heuristic', () {
      TokenEstimator.attachTokenizer(null);
      expect(TokenEstimator.isPendingExact('gpt4o', const []), isTrue);
      expect(TokenEstimator.isExact('gpt4o', const []), isFalse);
    });
    test('after attach: gpt exact, others heuristic - all equal to the original', () {
      TokenEstimator.attachTokenizer(tk);
      expect(TokenEstimator.isExact('gpt4o', const []), isTrue);
      expect(TokenEstimator.isExact('claude', const []), isFalse);
      for (var i = 0; i < prompts.length; i++) {
        final e = est[i] as Map<String, dynamic>;
        expect(TokenEstimator.estimateTokens(prompts[i], 'gpt4o', const []), e['gpt4o'], reason: 'gpt4o #$i');
        expect(TokenEstimator.estimateTokens(prompts[i], 'claude', const []), e['claude'], reason: 'claude #$i');
        expect(TokenEstimator.estimateTokens(prompts[i], 'gemini', const []), e['gemini'], reason: 'gemini #$i');
      }
      TokenEstimator.attachTokenizer(null);
    });
  });
}
