import 'dart:convert';

/// Small helpers shared by the engines. They exist to reproduce JavaScript
/// behaviours that Dart does not have out of the box (stable sort, JSON.stringify
/// number formatting, integer-like object key ordering).

class _Indexed<T> {
  final T value;
  final int index;
  _Indexed(this.value, this.index);
}

/// Returns a new list sorted with [compare]; equal elements keep their original
/// order (JS `Array.prototype.sort` is stable, Dart's `List.sort` is not).
List<T> stableSorted<T>(Iterable<T> items, int Function(T a, T b) compare) {
  final indexed = <_Indexed<T>>[];
  var i = 0;
  for (final v in items) {
    indexed.add(_Indexed<T>(v, i));
    i++;
  }
  indexed.sort((a, b) {
    final c = compare(a.value, b.value);
    if (c != 0) return c;
    return a.index.compareTo(b.index);
  });
  return indexed.map((e) => e.value).toList();
}

/// JS `str.slice(from, to)` for non-negative / negative indexes.
String jsSlice(String s, int from, [int? to]) {
  final len = s.length;
  var f = from < 0 ? len + from : from;
  var t = to == null ? len : (to < 0 ? len + to : to);
  if (f < 0) f = 0;
  if (t > len) t = len;
  if (f > len) f = len;
  if (t < f) return '';
  return s.substring(f, t);
}

String _jsNumber(num v) {
  if (v is int) return v.toString();
  final d = v.toDouble();
  if (d.isNaN || d.isInfinite) return 'null';
  if (d == d.truncateToDouble() && d.abs() < 1e21) {
    return d.toInt().toString();
  }
  return d.toString();
}

/// Equivalent of `JSON.stringify(value, null, indent)` (indent 0 = compact).
/// Doubles with an integral value print without a fraction like JS does.
String jsonStringify(Object? value, {int indent = 0}) {
  final sb = StringBuffer();
  _writeJson(sb, value, indent, 0);
  return sb.toString();
}

void _newline(StringBuffer sb, int indent, int depth) {
  if (indent <= 0) return;
  sb.write('\n');
  sb.write(' ' * (indent * depth));
}

void _writeJson(StringBuffer sb, Object? v, int indent, int depth) {
  if (v == null) {
    sb.write('null');
  } else if (v is bool) {
    sb.write(v ? 'true' : 'false');
  } else if (v is num) {
    sb.write(_jsNumber(v));
  } else if (v is String) {
    sb.write(jsonEncode(v));
  } else if (v is Map) {
    if (v.isEmpty) {
      sb.write('{}');
      return;
    }
    sb.write('{');
    var first = true;
    for (final e in v.entries) {
      if (!first) sb.write(',');
      first = false;
      _newline(sb, indent, depth + 1);
      sb.write(jsonEncode(e.key.toString()));
      sb.write(indent > 0 ? ': ' : ':');
      _writeJson(sb, e.value, indent, depth + 1);
    }
    _newline(sb, indent, depth);
    sb.write('}');
  } else if (v is Iterable) {
    final list = v.toList();
    if (list.isEmpty) {
      sb.write('[]');
      return;
    }
    sb.write('[');
    for (var i = 0; i < list.length; i++) {
      if (i > 0) sb.write(',');
      _newline(sb, indent, depth + 1);
      _writeJson(sb, list[i], indent, depth + 1);
    }
    _newline(sb, indent, depth);
    sb.write(']');
  } else {
    sb.write(jsonEncode(v.toString()));
  }
}

bool _isArrayIndexKey(String k) {
  if (k.isEmpty) return false;
  if (k == '0') return true;
  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(k)) return false;
  final n = int.tryParse(k);
  return n != null && n < 4294967295;
}

/// Orders map entries the way a JS object enumerates its keys: integer-like keys
/// first (ascending), then the remaining keys in insertion order.
List<MapEntry<String, dynamic>> jsObjectEntries(Map<String, dynamic> m) {
  final ints = <MapEntry<String, dynamic>>[];
  final rest = <MapEntry<String, dynamic>>[];
  for (final e in m.entries) {
    if (_isArrayIndexKey(e.key)) {
      ints.add(e);
    } else {
      rest.add(e);
    }
  }
  ints.sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));
  return [...ints, ...rest];
}

/// A map whose iteration order equals [jsObjectEntries] (for JSON output).
Map<String, dynamic> jsOrderedMap(Map<String, dynamic> m) {
  final out = <String, dynamic>{};
  for (final e in jsObjectEntries(m)) {
    out[e.key] = e.value;
  }
  return out;
}

/// JS `Math.round` for finite doubles (round half up).
int jsRound(num v) => (v + 0.5).floor();
