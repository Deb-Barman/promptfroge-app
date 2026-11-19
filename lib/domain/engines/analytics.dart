import '../../core/util.dart';
import '../../data/vault/vault_repository.dart';
import '../models.dart';
import 'analyzer.dart';
import 'search_engine.dart';

class DayCount {
  final String label;
  final int count;
  final int date;
  const DayCount(this.label, this.count, this.date);
}

class AnalyticsSummary {
  final int totalPrompts;
  final int totalTemplates;
  final int totalSnippets;
  final int totalWords;
  final int avgLen;
  final int favoriteCount;
  final Map<String, int> byCategory;
  final Map<String, int> byStatus;
  final List<DayCount> activity;
  final List<MapEntry<String, int>> topWords;
  final double avgScore;
  final List<MapEntry<String, int>> mostUsed;
  const AnalyticsSummary({
    required this.totalPrompts,
    required this.totalTemplates,
    required this.totalSnippets,
    required this.totalWords,
    required this.avgLen,
    required this.favoriteCount,
    required this.byCategory,
    required this.byStatus,
    required this.activity,
    required this.topWords,
    required this.avgScore,
    required this.mostUsed,
  });
}

class AnalyticsEngine {
  AnalyticsEngine._();

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static AnalyticsSummary summary(VaultData d, SuggestionEngine se, {String? profileId}) {
    final active = d.prompts.values.where((p) => !p.archived).toList();
    var totalWords = 0;
    var scoreSum = 0;
    var scored = 0;
    final byCat = <String, int>{};
    final byStatus = <String, int>{};
    for (final p in active) {
      totalWords += Utils.countWords(p.body);
      byCat[p.category] = (byCat[p.category] ?? 0) + 1;
      byStatus[p.status] = (byStatus[p.status] ?? 0) + 1;
      if (p.body.trim().isNotEmpty) {
        scoreSum += Analyzer.analyze(p.body, profileId: profileId).overall;
        scored++;
      }
    }
    final avgLen = active.isEmpty ? 0 : (totalWords / active.length).round();

    final days = <DayCount>[];
    final now = DateTime.now();
    for (var i = 13; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final start = day.millisecondsSinceEpoch;
      final end = DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch;
      final count = active.where((p) => p.updatedAt >= start && p.updatedAt < end).length;
      days.add(DayCount(_weekdays[day.weekday - 1], count, start));
    }

    final used = active.where((p) => p.useCount > 0).toList()..sort((a, b) => b.useCount.compareTo(a.useCount));

    return AnalyticsSummary(
      totalPrompts: active.length,
      totalTemplates: d.templates.length,
      totalSnippets: d.snippets.length,
      totalWords: totalWords,
      avgLen: avgLen,
      favoriteCount: active.where((p) => p.favorite).length,
      byCategory: byCat,
      byStatus: byStatus,
      activity: days,
      topWords: se.topWords(20),
      avgScore: scored == 0 ? 0 : scoreSum / scored,
      mostUsed: used.take(5).map((p) => MapEntry(p.displayTitle, p.useCount)).toList(),
    );
  }
}

class DuplicateGroup {
  final List<Prompt> prompts;
  const DuplicateGroup(this.prompts);
}

class DuplicateFinder {
  DuplicateFinder._();

  static List<DuplicateGroup> find(Iterable<Prompt> prompts, {double threshold = 0.55}) {
    final active = prompts.where((p) => p.body.trim().length > 20).toList();
    final visited = <String>{};
    final clusters = <DuplicateGroup>[];
    for (var i = 0; i < active.length; i++) {
      if (visited.contains(active[i].id)) continue;
      final group = <Prompt>[active[i]];
      for (var j = i + 1; j < active.length; j++) {
        if (visited.contains(active[j].id)) continue;
        if (Utils.textSimilarity(active[i].body, active[j].body) >= threshold) {
          group.add(active[j]);
          visited.add(active[j].id);
        }
      }
      if (group.length > 1) {
        visited.add(active[i].id);
        clusters.add(DuplicateGroup(group));
      }
    }
    return clusters;
  }
}
