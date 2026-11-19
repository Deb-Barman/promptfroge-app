import '../core/util.dart';

/// All entities are plain mutable classes with `clone()`, `toMap()` and `fromMap()`.
/// Timestamps are epoch milliseconds (same as the original HTML app, so a JSON
/// backup exported from the HTML version can be imported directly).

int _i(dynamic v, [int d = 0]) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? d : d);
bool _b(dynamic v, [bool d = false]) => v is bool ? v : d;
String _s(dynamic v, [String d = '']) => v == null ? d : v.toString();
List<String> _sl(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];

class PromptBlock {
  /// Built-in block id ("role", "task"...) or "custom_xxx".
  String type;
  String text;
  String? label; // custom blocks / renamed blocks
  int? color; // ARGB int for custom blocks
  String id;

  PromptBlock({required this.type, this.text = '', this.label, this.color, String? id}) : id = id ?? Utils.uid('blk');

  PromptBlock clone() => PromptBlock(type: type, text: text, label: label, color: color, id: id);

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'text': text,
        if (label != null) 'label': label,
        if (color != null) 'color': color,
      };

  factory PromptBlock.fromMap(Map<String, dynamic> m) => PromptBlock(
        id: m['id'] is String ? m['id'] as String : null,
        type: _s(m['type'], 'custom_section'),
        text: _s(m['text']),
        label: m['label'] is String ? m['label'] as String : null,
        color: m['color'] is num ? (m['color'] as num).toInt() : null,
      );
}

class NeedsRevisit {
  String note;
  int flaggedAt;
  NeedsRevisit({required this.note, required this.flaggedAt});
  Map<String, dynamic> toMap() => {'note': note, 'flaggedAt': flaggedAt};
  factory NeedsRevisit.fromMap(Map<String, dynamic> m) => NeedsRevisit(note: _s(m['note']), flaggedAt: _i(m['flaggedAt']));
}

class Prompt {
  String id;
  String title;
  String body;
  String category;
  List<String> tags;
  bool favorite;
  bool pinned;
  bool archived;
  bool bestOf;
  List<PromptBlock>? blocks;
  String format; // text | json | xml | markdown
  String status; // draft | review | production
  int currentVersion;
  int useCount;
  NeedsRevisit? needsRevisit;
  Map<String, bool> edgeCaseChecks;
  int createdAt;
  int updatedAt;

  /// Path of the file inside the vault, relative to the vault root (set by the repository).
  String? path;

  Prompt({
    String? id,
    this.title = '',
    this.body = '',
    this.category = 'custom',
    List<String>? tags,
    this.favorite = false,
    this.pinned = false,
    this.archived = false,
    this.bestOf = false,
    this.blocks,
    this.format = 'text',
    this.status = 'draft',
    this.currentVersion = 1,
    this.useCount = 0,
    this.needsRevisit,
    Map<String, bool>? edgeCaseChecks,
    int? createdAt,
    int? updatedAt,
    this.path,
  })  : id = id ?? Utils.uid('pr'),
        tags = tags ?? <String>[],
        edgeCaseChecks = edgeCaseChecks ?? <String, bool>{},
        createdAt = createdAt ?? Utils.nowMs(),
        updatedAt = updatedAt ?? Utils.nowMs();

  String get displayTitle => title.trim().isEmpty ? 'Untitled prompt' : title;

  Prompt clone() => Prompt(
        id: id,
        title: title,
        body: body,
        category: category,
        tags: List<String>.from(tags),
        favorite: favorite,
        pinned: pinned,
        archived: archived,
        bestOf: bestOf,
        blocks: blocks?.map((b) => b.clone()).toList(),
        format: format,
        status: status,
        currentVersion: currentVersion,
        useCount: useCount,
        needsRevisit: needsRevisit == null ? null : NeedsRevisit(note: needsRevisit!.note, flaggedAt: needsRevisit!.flaggedAt),
        edgeCaseChecks: Map<String, bool>.from(edgeCaseChecks),
        createdAt: createdAt,
        updatedAt: updatedAt,
        path: path,
      );

  /// Metadata (everything except the body) - written to the file's frontmatter.
  Map<String, dynamic> metaMap() => {
        'id': id,
        'title': title,
        'category': category,
        'tags': tags,
        'favorite': favorite,
        'pinned': pinned,
        'archived': archived,
        'bestOf': bestOf,
        'format': format,
        'status': status,
        'currentVersion': currentVersion,
        'useCount': useCount,
        if (needsRevisit != null) 'needsRevisit': needsRevisit!.toMap(),
        if (edgeCaseChecks.isNotEmpty) 'edgeCaseChecks': edgeCaseChecks,
        if (blocks != null) 'blocks': blocks!.map((b) => b.toMap()).toList(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// Full map including the body (used for JSON backups; compatible with the HTML app's records).
  Map<String, dynamic> toMap() => {...metaMap(), 'body': body};

  factory Prompt.fromMap(Map<String, dynamic> m, {String? bodyOverride, String? path}) {
    final checks = <String, bool>{};
    if (m['edgeCaseChecks'] is Map) {
      (m['edgeCaseChecks'] as Map).forEach((k, v) {
        if (v == true) checks[k.toString()] = true;
      });
    }
    return Prompt(
      id: m['id'] is String && (m['id'] as String).isNotEmpty ? m['id'] as String : null,
      title: _s(m['title']),
      body: bodyOverride ?? _s(m['body']),
      category: _s(m['category'], 'custom'),
      tags: _sl(m['tags']),
      favorite: _b(m['favorite']),
      pinned: _b(m['pinned']),
      archived: _b(m['archived']),
      bestOf: _b(m['bestOf']),
      blocks: m['blocks'] is List
          ? (m['blocks'] as List).whereType<Map>().map((e) => PromptBlock.fromMap(Map<String, dynamic>.from(e))).toList()
          : null,
      format: _s(m['format'], 'text'),
      status: _s(m['status'], 'draft'),
      currentVersion: _i(m['currentVersion'], 1),
      useCount: _i(m['useCount']),
      needsRevisit: m['needsRevisit'] is Map ? NeedsRevisit.fromMap(Map<String, dynamic>.from(m['needsRevisit'] as Map)) : null,
      edgeCaseChecks: checks,
      createdAt: _i(m['createdAt'], Utils.nowMs()),
      updatedAt: _i(m['updatedAt'], Utils.nowMs()),
      path: path,
    );
  }
}

class Template {
  String id;
  String name;
  String body;
  String category;
  int useCount;
  int createdAt;
  int updatedAt;
  String? path;

  Template({
    String? id,
    this.name = '',
    this.body = '',
    this.category = 'custom',
    this.useCount = 0,
    int? createdAt,
    int? updatedAt,
    this.path,
  })  : id = id ?? Utils.uid('tpl'),
        createdAt = createdAt ?? Utils.nowMs(),
        updatedAt = updatedAt ?? Utils.nowMs();

  String get displayName => name.trim().isEmpty ? 'Untitled template' : name;

  Template clone() => Template(
      id: id, name: name, body: body, category: category, useCount: useCount, createdAt: createdAt, updatedAt: updatedAt, path: path);

  Map<String, dynamic> metaMap() => {
        'id': id,
        'name': name,
        'category': category,
        'useCount': useCount,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
  Map<String, dynamic> toMap() => {...metaMap(), 'body': body};

  factory Template.fromMap(Map<String, dynamic> m, {String? bodyOverride, String? path}) => Template(
        id: m['id'] is String && (m['id'] as String).isNotEmpty ? m['id'] as String : null,
        name: _s(m['name']),
        body: bodyOverride ?? _s(m['body']),
        category: _s(m['category'], 'custom'),
        useCount: _i(m['useCount']),
        createdAt: _i(m['createdAt'], Utils.nowMs()),
        updatedAt: _i(m['updatedAt'], Utils.nowMs()),
        path: path,
      );
}

class Snippet {
  String id;
  String trigger; // always starts with "/"
  String body;
  int useCount;
  int createdAt;
  int updatedAt;
  String? path;

  Snippet({String? id, this.trigger = '/', this.body = '', this.useCount = 0, int? createdAt, int? updatedAt, this.path})
      : id = id ?? Utils.uid('snip'),
        createdAt = createdAt ?? Utils.nowMs(),
        updatedAt = updatedAt ?? Utils.nowMs();

  Snippet clone() =>
      Snippet(id: id, trigger: trigger, body: body, useCount: useCount, createdAt: createdAt, updatedAt: updatedAt, path: path);

  Map<String, dynamic> metaMap() =>
      {'id': id, 'trigger': trigger, 'useCount': useCount, 'createdAt': createdAt, 'updatedAt': updatedAt};
  Map<String, dynamic> toMap() => {...metaMap(), 'body': body};

  factory Snippet.fromMap(Map<String, dynamic> m, {String? bodyOverride, String? path}) => Snippet(
        id: m['id'] is String && (m['id'] as String).isNotEmpty ? m['id'] as String : null,
        trigger: _s(m['trigger'], '/'),
        body: bodyOverride ?? _s(m['body']),
        useCount: _i(m['useCount']),
        createdAt: _i(m['createdAt'], Utils.nowMs()),
        updatedAt: _i(m['updatedAt'], Utils.nowMs()),
        path: path,
      );
}

/// A pattern - either built-in (see `kPatterns`) or a user's custom one stored in the vault.
class PromptPattern {
  String id;
  String name;
  String category;
  String purpose;
  String when;
  String template;
  String example;
  List<String> variables;
  bool builtin;
  int useCount;
  int createdAt;
  int updatedAt;
  String? path;

  PromptPattern({
    String? id,
    this.name = '',
    this.category = 'Custom',
    this.purpose = '',
    this.when = '',
    this.template = '',
    this.example = '',
    List<String>? variables,
    this.builtin = false,
    this.useCount = 0,
    int? createdAt,
    int? updatedAt,
    this.path,
  })  : id = id ?? Utils.uid('cpat'),
        variables = variables ?? <String>[],
        createdAt = createdAt ?? Utils.nowMs(),
        updatedAt = updatedAt ?? Utils.nowMs();

  PromptPattern clone() => PromptPattern(
      id: id,
      name: name,
      category: category,
      purpose: purpose,
      when: when,
      template: template,
      example: example,
      variables: List<String>.from(variables),
      builtin: builtin,
      useCount: useCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      path: path);

  Map<String, dynamic> metaMap() => {
        'id': id,
        'name': name,
        'category': category,
        'purpose': purpose,
        'when': when,
        'example': example,
        'variables': variables,
        'useCount': useCount,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
  Map<String, dynamic> toMap() => {...metaMap(), 'template': template};

  factory PromptPattern.fromMap(Map<String, dynamic> m, {String? bodyOverride, String? path}) => PromptPattern(
        id: m['id'] is String && (m['id'] as String).isNotEmpty ? m['id'] as String : null,
        name: _s(m['name']),
        category: _s(m['category'], 'Custom'),
        purpose: _s(m['purpose']),
        when: _s(m['when']),
        template: bodyOverride ?? _s(m['template']),
        example: _s(m['example']),
        variables: _sl(m['variables']),
        useCount: _i(m['useCount']),
        createdAt: _i(m['createdAt'], Utils.nowMs()),
        updatedAt: _i(m['updatedAt'], Utils.nowMs()),
        path: path,
      );
}

class ChainStep {
  String id;
  String? promptId;
  String note;
  ChainStep({String? id, this.promptId, this.note = ''}) : id = id ?? Utils.uid('step');
  ChainStep clone() => ChainStep(id: id, promptId: promptId, note: note);
  Map<String, dynamic> toMap() => {'id': id, 'promptId': promptId, 'note': note};
  factory ChainStep.fromMap(Map<String, dynamic> m) =>
      ChainStep(id: m['id'] is String ? m['id'] as String : null, promptId: m['promptId'] is String ? m['promptId'] as String : null, note: _s(m['note']));
}

class Chain {
  String id;
  String name;
  String description;
  List<ChainStep> steps;
  int createdAt;
  int updatedAt;
  String? path;

  Chain({String? id, this.name = '', this.description = '', List<ChainStep>? steps, int? createdAt, int? updatedAt, this.path})
      : id = id ?? Utils.uid('chain'),
        steps = steps ?? <ChainStep>[],
        createdAt = createdAt ?? Utils.nowMs(),
        updatedAt = updatedAt ?? Utils.nowMs();

  Chain clone() => Chain(
      id: id,
      name: name,
      description: description,
      steps: steps.map((s) => s.clone()).toList(),
      createdAt: createdAt,
      updatedAt: updatedAt,
      path: path);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'steps': steps.map((s) => s.toMap()).toList(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory Chain.fromMap(Map<String, dynamic> m, {String? path}) => Chain(
        id: m['id'] is String && (m['id'] as String).isNotEmpty ? m['id'] as String : null,
        name: _s(m['name']),
        description: _s(m['description']),
        steps: m['steps'] is List
            ? (m['steps'] as List).whereType<Map>().map((e) => ChainStep.fromMap(Map<String, dynamic>.from(e))).toList()
            : <ChainStep>[],
        createdAt: _i(m['createdAt'], Utils.nowMs()),
        updatedAt: _i(m['updatedAt'], Utils.nowMs()),
        path: path,
      );
}

/// kind: "library" | "templates" | "patterns"
class Group {
  String id;
  String kind;
  String name;
  int color; // ARGB
  List<String> memberIds;
  int createdAt;
  int updatedAt;

  Group({String? id, required this.kind, this.name = '', this.color = 0xFF6366F1, List<String>? memberIds, int? createdAt, int? updatedAt})
      : id = id ?? Utils.uid('grp'),
        memberIds = memberIds ?? <String>[],
        createdAt = createdAt ?? Utils.nowMs(),
        updatedAt = updatedAt ?? Utils.nowMs();

  Group clone() =>
      Group(id: id, kind: kind, name: name, color: color, memberIds: List<String>.from(memberIds), createdAt: createdAt, updatedAt: updatedAt);

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind,
        'name': name,
        'color': color,
        'memberIds': memberIds,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// Accepts both int colors and the HTML app's "#rrggbb" strings.
  factory Group.fromMap(Map<String, dynamic> m) {
    var color = 0xFF6366F1;
    final c = m['color'];
    if (c is num) {
      color = c.toInt();
    } else if (c is String && c.startsWith('#') && c.length == 7) {
      color = 0xFF000000 | (int.tryParse(c.substring(1), radix: 16) ?? 0x6366F1);
    }
    return Group(
      id: m['id'] is String ? m['id'] as String : null,
      kind: _s(m['kind'], 'library'),
      name: _s(m['name']),
      color: color,
      memberIds: _sl(m['memberIds']),
      createdAt: _i(m['createdAt'], Utils.nowMs()),
      updatedAt: _i(m['updatedAt'], Utils.nowMs()),
    );
  }
}

class SavedSearch {
  String id;
  String name;
  String query;
  String category; // "all" or a category id
  String tag; // "" = any
  bool favoritesOnly;
  String sort;
  int createdAt;

  SavedSearch({String? id, this.name = '', this.query = '', this.category = 'all', this.tag = '', this.favoritesOnly = false, this.sort = 'updated', int? createdAt})
      : id = id ?? Utils.uid('search'),
        createdAt = createdAt ?? Utils.nowMs();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'query': query,
        'category': category,
        'tag': tag,
        'favoritesOnly': favoritesOnly,
        'sort': sort,
        'createdAt': createdAt,
      };

  factory SavedSearch.fromMap(Map<String, dynamic> m) => SavedSearch(
        id: m['id'] is String ? m['id'] as String : null,
        name: _s(m['name']),
        query: _s(m['query']),
        category: _s(m['category'], 'all'),
        tag: _s(m['tag']),
        favoritesOnly: _b(m['favoritesOnly']),
        sort: _s(m['sort'], 'updated'),
        createdAt: _i(m['createdAt'], Utils.nowMs()),
      );
}

class BuilderStructure {
  String id;
  String name;
  List<PromptBlock> blocks; // text is ignored for presets
  bool builtin;
  int createdAt;
  int updatedAt;

  BuilderStructure({String? id, this.name = '', List<PromptBlock>? blocks, this.builtin = false, int? createdAt, int? updatedAt})
      : id = id ?? Utils.uid('struct'),
        blocks = blocks ?? <PromptBlock>[],
        createdAt = createdAt ?? Utils.nowMs(),
        updatedAt = updatedAt ?? Utils.nowMs();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'blocks': blocks.map((b) => b.toMap()).toList(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory BuilderStructure.fromMap(Map<String, dynamic> m) => BuilderStructure(
        id: m['id'] is String ? m['id'] as String : null,
        name: _s(m['name']),
        blocks: m['blocks'] is List
            ? (m['blocks'] as List).whereType<Map>().map((e) => PromptBlock.fromMap(Map<String, dynamic>.from(e))).toList()
            : <PromptBlock>[],
        createdAt: _i(m['createdAt'], Utils.nowMs()),
        updatedAt: _i(m['updatedAt'], Utils.nowMs()),
      );
}

class PromptVersion {
  String id;
  String promptId;
  int versionNum;
  String title;
  String body;
  String note;
  int createdAt;

  PromptVersion({String? id, required this.promptId, required this.versionNum, this.title = '', this.body = '', this.note = '', int? createdAt})
      : id = id ?? Utils.uid('ver'),
        createdAt = createdAt ?? Utils.nowMs();

  Map<String, dynamic> metaMap() => {
        'id': id,
        'promptId': promptId,
        'versionNum': versionNum,
        'title': title,
        'note': note,
        'createdAt': createdAt,
      };
  Map<String, dynamic> toMap() => {...metaMap(), 'body': body};

  factory PromptVersion.fromMap(Map<String, dynamic> m, {String? bodyOverride}) => PromptVersion(
        id: m['id'] is String ? m['id'] as String : null,
        promptId: _s(m['promptId']),
        versionNum: _i(m['versionNum'], 1),
        title: _s(m['title']),
        body: bodyOverride ?? _s(m['body']),
        note: _s(m['note']),
        createdAt: _i(m['createdAt'], Utils.nowMs()),
      );
}

class CustomModel {
  String id;
  String label;
  String vendor;
  double charsPerToken;
  int contextWindow;
  double priceIn;
  double priceOut;

  CustomModel({String? id, this.label = '', this.vendor = 'Custom', this.charsPerToken = 4.0, this.contextWindow = 32000, this.priceIn = 0, this.priceOut = 0})
      : id = id ?? Utils.uid('model');

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'vendor': vendor,
        'charsPerToken': charsPerToken,
        'contextWindow': contextWindow,
        'priceIn': priceIn,
        'priceOut': priceOut,
      };

  factory CustomModel.fromMap(Map<String, dynamic> m) => CustomModel(
        id: m['id'] is String ? m['id'] as String : null,
        label: _s(m['label']),
        vendor: _s(m['vendor'], 'Custom'),
        charsPerToken: m['charsPerToken'] is num ? (m['charsPerToken'] as num).toDouble() : 4.0,
        contextWindow: _i(m['contextWindow'], 32000),
        priceIn: m['priceIn'] is num ? (m['priceIn'] as num).toDouble() : 0,
        priceOut: m['priceOut'] is num ? (m['priceOut'] as num).toDouble() : 0,
      );
}

/// Portable settings stored in `<vault>/.promptforge/settings.json`.
/// One attempt at a Learn challenge. Same shape the HTML app stored: { solved, score, answer, attemptedAt }.
class ChallengeAttempt {
  final bool solved;
  final int score;
  final String answer;
  final int attemptedAt;
  const ChallengeAttempt({required this.solved, required this.score, required this.answer, required this.attemptedAt});

  Map<String, dynamic> toMap() => {'solved': solved, 'score': score, 'answer': answer, 'attemptedAt': attemptedAt};

  factory ChallengeAttempt.fromMap(Map<String, dynamic> m) => ChallengeAttempt(
        solved: m['solved'] == true,
        score: _i(m['score'], 0),
        answer: _s(m['answer'], ''),
        attemptedAt: _i(m['attemptedAt'], 0),
      );
}

class VaultSettings {
  String selectedModel;
  String scoringProfile;
  int versionRetention; // 0 = unlimited
  String outputFormatHint;
  List<CustomModel> customModels;
  Map<String, bool> challengeProgress;

  /// Latest attempt per challenge (answer + score), so a reopened challenge shows your previous rewrite.
  Map<String, ChallengeAttempt> challengeAttempts;

  /// Calls per month used for the projected monthly cost in the editor's token panel.
  int volumeCallsPerMonth;

  /// Category given to new prompts.
  String defaultCategory;

  VaultSettings({
    this.selectedModel = 'claude',
    this.scoringProfile = 'default',
    this.versionRetention = 25,
    this.outputFormatHint = 'none',
    List<CustomModel>? customModels,
    Map<String, bool>? challengeProgress,
    Map<String, ChallengeAttempt>? challengeAttempts,
    this.volumeCallsPerMonth = 1000,
    this.defaultCategory = 'custom',
  })  : customModels = customModels ?? <CustomModel>[],
        challengeProgress = challengeProgress ?? <String, bool>{},
        challengeAttempts = challengeAttempts ?? <String, ChallengeAttempt>{};

  VaultSettings clone() => VaultSettings(
        selectedModel: selectedModel,
        scoringProfile: scoringProfile,
        versionRetention: versionRetention,
        outputFormatHint: outputFormatHint,
        customModels: customModels.map((m) => CustomModel.fromMap(m.toMap())).toList(),
        challengeProgress: Map<String, bool>.from(challengeProgress),
        challengeAttempts: Map<String, ChallengeAttempt>.from(challengeAttempts),
        volumeCallsPerMonth: volumeCallsPerMonth,
        defaultCategory: defaultCategory,
      );

  Map<String, dynamic> toMap() => {
        'selectedModel': selectedModel,
        'scoringProfile': scoringProfile,
        'versionRetention': versionRetention,
        'outputFormatHint': outputFormatHint,
        'customModels': customModels.map((m) => m.toMap()).toList(),
        'challengeProgress': challengeProgress,
        'challengeAttempts': {for (final e in challengeAttempts.entries) e.key: e.value.toMap()},
        'volumeCallsPerMonth': volumeCallsPerMonth,
        'defaultCategory': defaultCategory,
      };

  factory VaultSettings.fromMap(Map<String, dynamic> m) {
    final prog = <String, bool>{};
    final attempts = <String, ChallengeAttempt>{};
    if (m['challengeProgress'] is Map) {
      (m['challengeProgress'] as Map).forEach((k, v) {
        // This app stores `true`; the HTML app stored {solved, score, answer, attemptedAt}.
        if (v == true || (v is Map && v['solved'] == true)) prog[k.toString()] = true;
        if (v is Map) attempts[k.toString()] = ChallengeAttempt.fromMap(Map<String, dynamic>.from(v));
      });
    }
    if (m['challengeAttempts'] is Map) {
      (m['challengeAttempts'] as Map).forEach((k, v) {
        if (v is Map) attempts[k.toString()] = ChallengeAttempt.fromMap(Map<String, dynamic>.from(v));
      });
    }
    return VaultSettings(
      selectedModel: _s(m['selectedModel'], 'claude'),
      scoringProfile: _s(m['scoringProfile'], 'default'),
      versionRetention: _i(m['versionRetention'], 25),
      outputFormatHint: _s(m['outputFormatHint'], 'none'),
      customModels: m['customModels'] is List
          ? (m['customModels'] as List).whereType<Map>().map((e) => CustomModel.fromMap(Map<String, dynamic>.from(e))).toList()
          : <CustomModel>[],
      challengeProgress: prog,
      challengeAttempts: attempts,
      volumeCallsPerMonth: _i(m['volumeCallsPerMonth'], 1000).clamp(1, 1000000000),
      defaultCategory: _s(m['defaultCategory'], 'custom'),
    );
  }
}
