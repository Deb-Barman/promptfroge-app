import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/engines/bpe_tokenizer.dart';
import '../domain/engines/token_estimator.dart';

/// Loads the cl100k vocabulary asset once and hands it to [TokenEstimator]. Watch this provider in any widget
/// that shows token counts so it rebuilds (heuristic -> exact) the moment the vocabulary is ready.
final tokenizerProvider = FutureProvider<bool>((ref) async {
  try {
    final data = await rootBundle.load('assets/data/cl100k.gz');
    // Let the first frame paint before spending ~150 ms building the rank table.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    TokenEstimator.attachTokenizer(Cl100kTokenizer.fromGzip(data.buffer.asUint8List()));
    return true;
  } catch (_) {
    // Counts simply stay heuristic, exactly like the original app when its vocabulary fails to load.
    return false;
  }
});
