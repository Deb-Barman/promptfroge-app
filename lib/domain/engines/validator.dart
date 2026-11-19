import 'dart:convert';

import 'package:xml/xml.dart';

class ValidationResult {
  final bool valid;
  final String? message;
  const ValidationResult(this.valid, [this.message]);
}

class EmbedIssue {
  final String id;
  final String level; // warn | info
  final String label;
  final String detail;
  const EmbedIssue(this.id, this.level, this.label, this.detail);
}

class PromptValidator {
  PromptValidator._();

  static ValidationResult validate(String? text, String format) {
    final raw = (text ?? '').trim();
    if (raw.isEmpty) return const ValidationResult(true);
    if (format == 'json') {
      try {
        jsonDecode(raw);
        return const ValidationResult(true);
      } on FormatException catch (e) {
        return ValidationResult(false, e.message);
      }
    }
    if (format == 'xml') {
      try {
        XmlDocument.parse(raw);
        return const ValidationResult(true);
      } on XmlException catch (e) {
        return ValidationResult(false, e.message);
      } catch (_) {
        return const ValidationResult(false, 'Malformed XML');
      }
    }
    return const ValidationResult(true);
  }

  /// Flags characters that would break the prompt if pasted into a hand-built JSON string.
  static List<EmbedIssue> checkJsonEmbedSafety(String? text) {
    final raw = text ?? '';
    final issues = <EmbedIssue>[];
    if (raw.trim().isEmpty) return issues;

    final quotes = '"'.allMatches(raw).length;
    if (quotes > 0) {
      issues.add(EmbedIssue('unescaped_quotes', 'warn', '$quotes double-quote character${quotes == 1 ? '' : 's'} found',
          'If this text is hand-assembled into a JSON string value rather than passed through a JSON encoder, unescaped " characters will break or truncate the value.'));
    }
    final hasNl = raw.contains('\n');
    final hasTab = raw.contains('\t');
    if (hasNl || hasTab) {
      final what = [if (hasNl) 'newline', if (hasTab) 'tab'].join(' and ');
      issues.add(EmbedIssue('raw_control_chars', 'info', 'Contains raw $what characters',
          'Valid JSON strings require these as \\n / \\t escape sequences, not literal characters. Standard JSON encoders handle this; it only matters when the payload is built with string concatenation.'));
    }
    final open = '{'.allMatches(raw).length;
    final close = '}'.allMatches(raw).length;
    if (open != close) {
      issues.add(EmbedIssue('unbalanced_braces', 'info', 'Unbalanced braces ($open `{` vs $close `}`)',
          'Not necessarily a problem for plain text, but worth a glance if this prompt also contains a JSON example - an unbalanced count usually means the example is incomplete.'));
    }
    return issues;
  }
}
