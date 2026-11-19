import 'dart:convert';
import 'dart:io' show GZipCodec;
import 'dart:typed_data';

/// Exact cl100k_base tokenizer (the encoding GPT-4 / GPT-4o-class models use), ported from the original
/// `RealTokenizer` in PromptForge.html: same pre-tokenizer pattern, same byte-level BPE merge rule.
///
/// The vocabulary ships as `assets/data/cl100k.gz`: gzip of `[len byte][token bytes]` records in rank order.
class Cl100kTokenizer {
  Cl100kTokenizer._(this._ranks);

  /// Byte sequence (as a latin-1 string, one char per byte) -> rank.
  final Map<String, int> _ranks;

  int get vocabSize => _ranks.length;

  /// Same pattern as the original (JS-regex form of tiktoken's pattern); needs unicode mode for \p{L}/\p{N}.
  static final RegExp _pretoken = RegExp(
    r"'(?:[sSdDmMtT]|[lL][lL]|[vV][eE]|[rR][eE])|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s+$|\s*[\r\n]|\s+(?!\S)|\s",
    unicode: true,
  );

  /// Builds a tokenizer from the gzipped vocab bytes.
  factory Cl100kTokenizer.fromGzip(List<int> gz) => Cl100kTokenizer.fromRaw(GZipCodec().decode(gz));

  factory Cl100kTokenizer.fromRaw(List<int> raw) {
    final ranks = <String, int>{};
    var offset = 0;
    var rank = 0;
    while (offset < raw.length) {
      final len = raw[offset++];
      ranks[String.fromCharCodes(raw.sublist(offset, offset + len))] = rank++;
      offset += len;
    }
    return Cl100kTokenizer._(ranks);
  }

  List<int> _encodeWord(Uint8List bytes) {
    if (bytes.length == 1) {
      final r = _ranks[String.fromCharCode(bytes[0])];
      return r == null ? const [] : [r];
    }
    final parts = <String>[for (final b in bytes) String.fromCharCode(b)];
    while (parts.length > 1) {
      var minRank = 1 << 62;
      var minIdx = -1;
      for (var i = 0; i < parts.length - 1; i++) {
        final r = _ranks[parts[i] + parts[i + 1]];
        if (r != null && r < minRank) {
          minRank = r;
          minIdx = i;
        }
      }
      if (minIdx == -1) break;
      parts.replaceRange(minIdx, minIdx + 2, [parts[minIdx] + parts[minIdx + 1]]);
    }
    return [for (final p in parts) _ranks[p]!];
  }

  /// Token ids for [text].
  List<int> encode(String text) {
    if (text.isEmpty) return const [];
    final out = <int>[];
    for (final m in _pretoken.allMatches(text)) {
      out.addAll(_encodeWord(Uint8List.fromList(utf8.encode(m.group(0)!))));
    }
    return out;
  }

  int countTokens(String text) => encode(text).length;
}
