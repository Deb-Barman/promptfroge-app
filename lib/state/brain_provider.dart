import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../data/vault/vault_repository.dart';
import '../domain/engines/brain.dart';
import 'device_settings.dart';
import 'vault_notifier.dart';

const String _kUsageKey = 'brain_usage_v1';

/// Names a prompt section can go by, mapped to the builder block ids.
Map<String, String> brainSectionAliases() {
  final m = <String, String>{};
  for (final b in kBlockTypes) {
    m[b.label.toLowerCase()] = b.id;
    m[b.id] = b.id;
  }
  const extra = {
    'format': 'output',
    'output format': 'output',
    'rules': 'constraints',
    'constraint': 'constraints',
    'goal': 'objective',
    'persona': 'role',
    'criteria': 'evaluation',
    'evaluation criteria': 'evaluation',
    'edge cases': 'edgecases',
    'edge_cases': 'edgecases',
    'steps': 'instructions',
    'instruction': 'instructions',
    'example': 'examples',
    'inputs': 'input',
    'background': 'context',
  };
  m.addAll(extra);
  return m;
}

/// Turns the vault into learning material. Built-in patterns are low-weight seed material, never "learned".
List<BrainDoc> brainDocsFrom(VaultData d) {
  final docs = <BrainDoc>[];
  for (final p in d.prompts.values) {
    var w = p.archived ? 0.4 : 1.0;
    if (p.favorite || p.bestOf) w += 0.35;
    if (p.status == 'production') w += 0.25;
    docs.add(BrainDoc('${p.title}\n${p.body}', BrainSource.prompt, weight: w, updatedAt: p.updatedAt));
  }
  for (final t in d.templates.values) {
    docs.add(BrainDoc('${t.name}\n${t.body}', BrainSource.template, weight: 1.25, updatedAt: t.updatedAt));
  }
  for (final p in d.customPatterns.values) {
    docs.add(BrainDoc('${p.name}\n${p.purpose}\n${p.template}', BrainSource.pattern, weight: 1.2, updatedAt: p.updatedAt));
  }
  for (final p in kPatterns) {
    docs.add(BrainDoc('${p.purpose}\n${p.template}', BrainSource.seed, weight: 0.5));
  }
  for (final s in d.snippets.values) {
    docs.add(BrainDoc(s.body, BrainSource.snippet, weight: 1.1, updatedAt: s.updatedAt));
  }
  for (final c in d.chains.values) {
    final steps = c.steps.map((s) => s.note).where((n) => n.trim().isNotEmpty).join('\n');
    docs.add(BrainDoc('${c.name}\n${c.description}\n$steps', BrainSource.chain, weight: 0.8, updatedAt: c.updatedAt));
  }
  return docs;
}

int _fingerprint(VaultData d) {
  var h = 17;
  for (final p in d.prompts.values) {
    h = Object.hash(h, p.id, p.updatedAt, p.archived);
  }
  for (final t in d.templates.values) {
    h = Object.hash(h, t.id, t.updatedAt);
  }
  for (final p in d.customPatterns.values) {
    h = Object.hash(h, p.id, p.updatedAt);
  }
  for (final s in d.snippets.values) {
    h = Object.hash(h, s.id, s.updatedAt);
  }
  for (final c in d.chains.values) {
    h = Object.hash(h, c.id, c.updatedAt);
  }
  return h;
}

class _BuildArgs {
  final List<BrainDoc> docs;
  final int now;
  final Map<String, String> aliases;
  const _BuildArgs(this.docs, this.now, this.aliases);
}

BrainModel _buildNow(_BuildArgs a) => BrainModel.build(a.docs, now: a.now, sectionAliases: a.aliases);

class BrainState {
  final BrainModel? model;
  final bool building;
  final BrainUsage usage;

  /// Bumped whenever a new model replaces the old one (so listeners can refresh suggestions).
  final int version;

  /// Set when the brain just reached a new level (cleared by [BrainController.clearLevelUp]).
  final int? levelUp;
  const BrainState({this.model, this.building = false, required this.usage, this.version = 0, this.levelUp});

  BrainState copyWith({BrainModel? model, bool? building, BrainUsage? usage, int? version, int? levelUp, bool clearLevelUp = false}) => BrainState(
        model: model ?? this.model,
        building: building ?? this.building,
        usage: usage ?? this.usage,
        version: version ?? this.version,
        levelUp: clearLevelUp ? null : (levelUp ?? this.levelUp),
      );
}

/// Builds the editor brain from everything in the vault and keeps it up to date: after any change to the
/// prompts, templates, patterns, snippets or chains it relearns in the background (a few seconds after the
/// user stops typing). It also remembers which suggestions were accepted so those rank higher next time.
class BrainController extends Notifier<BrainState> {
  Timer? _timer;
  int _fp = -1;
  int _gen = 0;
  SharedPreferences? _prefs;

  @override
  BrainState build() {
    _prefs = ref.read(sharedPrefsProvider);
    var usage = BrainUsage();
    try {
      final raw = _prefs!.getString(_kUsageKey);
      if (raw != null) usage = BrainUsage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
    ref.listen<VaultState>(vaultProvider, (prev, next) {
      if (!next.isReady) return;
      final fp = _fingerprint(next.data);
      if (fp == _fp) return;
      final first = _fp == -1;
      _fp = fp;
      _schedule(next.data, first ? Duration.zero : const Duration(milliseconds: 3500));
    }, fireImmediately: true);
    ref.onDispose(() {
      _timer?.cancel();
    });
    return BrainState(usage: usage);
  }

  void _schedule(VaultData data, Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(_run(data)));
  }

  /// Relearn right now from the current vault.
  Future<void> relearn() => _run(ref.read(vaultProvider).data);

  Future<void> _run(VaultData data) async {
    final gen = ++_gen;
    state = state.copyWith(building: true);
    final docs = brainDocsFrom(data);
    final now = DateTime.now().millisecondsSinceEpoch;
    var chars = 0;
    for (final d in docs) {
      chars += d.text.length;
    }
    final args = _BuildArgs(docs, now, brainSectionAliases());
    BrainModel model;
    try {
      model = chars > 120000 ? await Isolate.run(() => _buildNow(args)) : _buildNow(args);
    } catch (_) {
      if (gen == _gen) state = state.copyWith(building: false);
      return;
    }
    if (gen != _gen) return;
    final lvl = model.level.level;
    int? up;
    final u = state.usage;
    if (lvl > u.announcedLevel) {
      if (u.announcedLevel != 0) up = lvl;
      u.announcedLevel = lvl;
      _save();
    }
    state = BrainState(model: model, building: false, usage: u, version: state.version + 1, levelUp: up ?? state.levelUp);
  }

  void clearLevelUp() {
    if (state.levelUp != null) state = state.copyWith(clearLevelUp: true);
  }

  /// Counts a suggestion list that was shown. Kept in memory and saved with the next accepted suggestion.
  void noteShown() {
    state.usage.shown++;
  }

  void recordAccept(String insert) {
    state.usage.record(insert);
    _save();
  }

  /// Forget which suggestions were accepted (the learned vocabulary itself comes from the vault).
  void resetPersonalLearning() {
    state.usage.reset();
    state = state.copyWith(usage: state.usage, version: state.version + 1);
    _save();
  }

  void _save() {
    try {
      _prefs?.setString(_kUsageKey, jsonEncode(state.usage.toJson()));
    } catch (_) {}
  }
}

final brainProvider = NotifierProvider<BrainController, BrainState>(BrainController.new);
