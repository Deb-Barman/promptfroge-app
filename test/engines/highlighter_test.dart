import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_forge/domain/engines/highlighter.dart';

import '../support/golden.dart';

String _plain(InlineSpan span) {
  final sb = StringBuffer();
  span.visitChildren((s) {
    if (s is TextSpan && s.text != null) sb.write(s.text);
    return true;
  });
  return sb.toString();
}

void main() {
  final g = Goldens.load();
  const base = TextStyle(fontSize: 14);
  const extra = [
    '',
    '{{unclosed',
    '```\ncode\n```\n> quote\n- item\n**bold** [link](http://x)',
    '{"a": [1, 2.5e3, true, null, "str\\"esc"], "b": {}}',
    '<a href="x">text &amp; more</a><!-- c --><br/>',
    '# Heading\n\n// comment\nMUST NOT do that. Always answer.',
    'emoji 📂 and नमस्ते and \t tabs\r\nCRLF',
  ];

  test('highlighted spans concatenate back to the exact input for every format', () {
    final inputs = [...g.prompts, ...extra, ...(g.fixtures['json'] as List).cast<String>(), ...(g.fixtures['xml'] as List).cast<String>()];
    for (final format in ['text', 'json', 'xml', 'markdown']) {
      for (final text in inputs) {
        for (final colors in [const HighlightColors.dark(), const HighlightColors.light()]) {
          final span = PromptHighlighter.build(text, format, base, colors);
          expect(_plain(span), text, reason: 'format=$format text=${text.replaceAll('\n', '\\n')}');
        }
      }
    }
  });

  test('variables are coloured differently from plain text', () {
    final span = PromptHighlighter.build('Hello {{name}} there', 'text', base, const HighlightColors.dark());
    final styles = <Color?>{};
    span.visitChildren((s) {
      if (s is TextSpan && s.text != null) styles.add(s.style?.color);
      return true;
    });
    expect(styles.length, greaterThan(1));
  });
}
