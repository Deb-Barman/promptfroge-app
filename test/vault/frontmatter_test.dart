import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_forge/data/vault/frontmatter.dart';

void main() {
  group('Frontmatter', () {
    test('round-trips meta and body exactly', () {
      final meta = {'id': 'pr_1', 'title': 'Hello: "World"', 'tags': ['a', 'b c'], 'favorite': true, 'count': 3, 'nested': {'x': 1}, 'none': null};
      const body = 'Line 1\n\nLine 3 with --- inside\n---\nand more';
      final text = Frontmatter.serialize(meta, body);
      final parsed = Frontmatter.parse(text);
      expect(parsed.meta, meta);
      expect(parsed.body, body);
    });

    test('body trailing newlines and leading blank lines are preserved', () {
      for (final body in ['', '\n', 'x\n', '\n\nx\n\n', '  indented\n  more  ']) {
        final parsed = Frontmatter.parse(Frontmatter.serialize({'id': 'a'}, body));
        expect(parsed.body, body, reason: 'body ${body.codeUnits}');
      }
    });

    test('unicode and emoji survive', () {
      const body = 'नमस्ते 📂 – “quotes” ✓';
      final parsed = Frontmatter.parse(Frontmatter.serialize({'title': 'Café ☕'}, body));
      expect(parsed.meta['title'], 'Café ☕');
      expect(parsed.body, body);
    });

    test('file without frontmatter is all body', () {
      final p = Frontmatter.parse('# Just markdown\n\ntext');
      expect(p.meta, isEmpty);
      expect(p.body, '# Just markdown\n\ntext');
    });

    test('unterminated frontmatter is treated as body', () {
      final p = Frontmatter.parse('---\ntitle: x\nno end');
      expect(p.meta, isEmpty);
    });

    test('CRLF files are read', () {
      final p = Frontmatter.parse('---\r\ntitle: "T"\r\n---\r\nbody\r\nline2\r\n');
      expect(p.meta['title'], 'T');
      expect(p.body, 'body\nline2');
    });

    test('hand-written YAML (Obsidian style) is tolerated', () {
      final p = Frontmatter.parse('---\ntitle: My note\ntags:\n  - one\n  - two\nfavorite: true\nrating: 4\naliases: [a, b]\n---\nHello');
      expect(p.meta['title'], 'My note');
      expect(p.meta['tags'], ['one', 'two']);
      expect(p.meta['favorite'], true);
      expect(p.meta['rating'], 4);
      expect(p.meta['aliases'], ['a', 'b']);
      expect(p.body, 'Hello');
    });
  });
}
