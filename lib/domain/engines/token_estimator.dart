import '../../core/constants.dart';
import '../../core/util.dart';
import '../models.dart';
import 'bpe_tokenizer.dart';

class TokenEstimate {
  final int promptTokens;
  final int completionTokens;
  final double cost;
  final ModelSpec model;
  const TokenEstimate(this.promptTokens, this.completionTokens, this.cost, this.model);
}

class ContextStatus {
  final int tokens;
  final int limit;
  final double pct;

  /// ok | warn | over
  final String level;
  const ContextStatus(this.tokens, this.limit, this.pct, this.level);
}

/// Token counts. Models flagged `tokenizer: 'cl100k'` (GPT family) are counted exactly with the real BPE
/// once [attachTokenizer] has been given the loaded vocabulary; everything else (and GPT counts before the
/// vocab finishes loading) uses the chars-per-token heuristic, exactly like the original HTML app.
class TokenEstimator {
  TokenEstimator._();

  static Cl100kTokenizer? _real;

  /// Called once the vocabulary asset has been decoded.
  static void attachTokenizer(Cl100kTokenizer? t) => _real = t;

  static bool get hasRealTokenizer => _real != null;

  /// True when this model's count comes from the exact BPE rather than the heuristic.
  static bool isExact(String modelId, List<CustomModel> custom) => getModel(modelId, custom).tokenizer == 'cl100k' && _real != null;

  /// True when the model *would* be exact once the vocabulary finishes loading.
  static bool isPendingExact(String modelId, List<CustomModel> custom) => getModel(modelId, custom).tokenizer == 'cl100k' && _real == null;

  static List<ModelSpec> allModels(List<CustomModel> custom) {
    return [
      ...kModels,
      ...custom.map((m) => ModelSpec(
            id: m.id,
            label: m.label,
            vendor: m.vendor,
            group: m.vendor,
            charsPerToken: m.charsPerToken <= 0 ? 4.0 : m.charsPerToken,
            contextWindow: m.contextWindow <= 0 ? 32000 : m.contextWindow,
            priceIn: m.priceIn,
            priceOut: m.priceOut,
            priceNote: 'custom',
            idiomKey: 'generic',
            tokenizer: 'estimate',
          )),
    ];
  }

  static ModelSpec getModel(String id, List<CustomModel> custom) {
    final all = allModels(custom);
    for (final m in all) {
      if (m.id == id) return m;
    }
    for (final m in kModels) {
      if (m.id == 'generic') return m;
    }
    return kModels.last;
  }

  static int estimateTokens(String? text, String modelId, List<CustomModel> custom) {
    final model = getModel(modelId, custom);
    if (model.tokenizer == 'cl100k' && _real != null) return _real!.countTokens(text ?? '');
    final len = (text ?? '').length;
    if (len == 0) return 0;
    final v = (len / model.charsPerToken).round();
    return v < 1 ? 1 : v;
  }

  static TokenEstimate estimateCost(String? text, String modelId, List<CustomModel> custom, {int? completionTokens}) {
    final model = getModel(modelId, custom);
    final prompt = estimateTokens(text, modelId, custom);
    final comp = completionTokens ?? (prompt * 0.25).round();
    final cost = (prompt / 1e6) * model.priceIn + (comp / 1e6) * model.priceOut;
    return TokenEstimate(prompt, comp, cost, model);
  }

  static ContextStatus contextStatus(String? text, String modelId, List<CustomModel> custom) {
    final model = getModel(modelId, custom);
    final tokens = estimateTokens(text, modelId, custom);
    final pct = Utils.clamp((tokens / model.contextWindow) * 100, 0, 999).toDouble();
    var level = 'ok';
    if (pct >= 95) {
      level = 'over';
    } else if (pct >= 70) {
      level = 'warn';
    }
    return ContextStatus(tokens, model.contextWindow, pct, level);
  }
}
