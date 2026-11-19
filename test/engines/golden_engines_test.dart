// Compares the Dart engines against output of the ORIGINAL JavaScript implementation.
// Expected values come from test/goldens/engines.json (generated, never hand-written).
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_forge/core/constants.dart';
import 'package:prompt_forge/core/util.dart';
import 'package:prompt_forge/domain/engines/analyzer.dart';
import 'package:prompt_forge/domain/engines/cleaner.dart';
import 'package:prompt_forge/domain/engines/format_converter.dart';
import 'package:prompt_forge/domain/engines/readability.dart';
import 'package:prompt_forge/domain/engines/template_engine.dart';
import 'package:prompt_forge/domain/engines/tools.dart';
import 'package:prompt_forge/domain/engines/validator.dart';
import 'package:prompt_forge/domain/models.dart';
import 'package:prompt_forge/domain/engines/analytics.dart';

import '../support/golden.dart';

const _values = {'topic': 'AI', 'document': 'DOC', 'audience': 'engineers', 'count': '5', 'tone': 'warm'};

void main() {
  final g = Goldens.load();
  final prompts = g.prompts;

  group('Analyzer', () {
    for (var i = 0; i < prompts.length; i++) {
      test('analyze fixture $i', () {
        final r = Analyzer.analyze(prompts[i]);
        final e = g.list('analyze')[i] as Map<String, dynamic>;
        expect(r.scores, Map<String, int>.from(e['scores'] as Map), reason: 'scores');
        expect(r.overall, e['overall']);
        expect([for (final x in r.issues) {'level': x.level, 'msg': x.msg}], (e['issues'] as List).map((x) => {'level': x['level'], 'msg': x['msg']}).toList());
        expect(r.has, Map<String, bool>.from(e['has'] as Map));
        expect(r.wordCount, e['wordCount']);
        expect(r.undefinedVars, (e['undefinedVars'] as List).cast<String>());
      });
      test('dnaProfile fixture $i', () {
        final r = Analyzer.dnaProfile(prompts[i], null);
        final e = g.list('dna')[i] as List;
        expect(r.map((x) => x.id).toList(), e.map((x) => x['id']).toList());
        for (var k = 0; k < e.length; k++) {
          expect(r[k].strength, closeTo((e[k]['strength'] as num).toDouble(), 1e-9), reason: e[k]['id'] as String);
        }
      });
      test('improve fixture $i', () {
        final r = Analyzer.improve(prompts[i]);
        final e = g.list('improve')[i] as List;
        expect([for (final x in r) {'title': x.title, 'detail': x.detail}], e.map((x) => {'title': x['title'], 'detail': x['detail']}).toList());
      });
    }
    test('scoring profiles', () {
      final profiles = g['profiles'] as Map<String, dynamic>;
      profiles.forEach((id, expected) {
        final list = (expected as List).cast<int>();
        for (var i = 0; i < list.length; i++) {
          expect(Analyzer.analyze(prompts[i], profileId: id).overall, list[i], reason: 'profile $id fixture $i');
        }
      });
    });
  });

  group('TemplateEngine', () {
    for (var i = 0; i < prompts.length; i++) {
      test('variables fixture $i', () {
        final t = prompts[i];
        final specs = TemplateEngine.extractVariableSpecs(t);
        final e = g.list('varSpecs')[i] as List;
        expect(
          [for (final s in specs) {'name': s.name, 'type': s.type, 'default': s.defaultValue, 'options': s.options}],
          e.map((x) => {'name': x['name'], 'type': x['type'], 'default': x['default'], 'options': (x['options'] as List).cast<String>()}).toList(),
        );
        expect(TemplateEngine.extractVariables(t), (g.list('vars')[i] as List).cast<String>());
        expect(TemplateEngine.render(t, Map<String, String>.of(_values)), g.list('render')[i]);
        expect(TemplateEngine.hasUnfilledVariables(t), g.list('hasUnfilled')[i]);
      });
      test('spans fixture $i', () {
        final r = TemplateEngine.detectParameterizableSpans(prompts[i]);
        final e = g.list('spans')[i] as List;
        expect([for (final s in r) {'text': s.text, 'kind': s.kind, 'index': s.index}], e.map((x) => {'text': x['text'], 'kind': x['kind'], 'index': x['index']}).toList());
      });
    }
    test('humanizeVarName', () {
      for (final row in g.list('humanize')) {
        expect(TemplateEngine.humanizeVarName(row[0] as String), row[1]);
      }
    });
  });

  group('Cleaner / scanners', () {
    for (var i = 0; i < prompts.length; i++) {
      test('fixture $i', () {
        final t = prompts[i];
        expect([for (final f in PromptCleaner.inspect(t)) {'type': f.type, 'detail': f.detail}], (g.list('inspect')[i] as List).map((x) => {'type': x['type'], 'detail': x['detail']}).toList());
        expect(PromptCleaner.autoClean(t), g.list('autoClean')[i]);
        expect([for (final f in SecurityScanner.scan(t)) {'id': f.id, 'label': f.label, 'count': f.count, 'sample': f.sample}],
            (g.list('security')[i] as List).map((x) => {'id': x['id'], 'label': x['label'], 'count': x['count'], 'sample': x['sample']}).toList());
        expect([for (final f in RiskLinter.scan(t)) {'id': f.id, 'label': f.label, 'detail': f.detail}], (g.list('risk')[i] as List).map((x) => {'id': x['id'], 'label': x['label'], 'detail': x['detail']}).toList());
        expect([for (final f in PromptTools.checkInjectionSurface(t)) {'id': f.id, 'label': f.label, 'detail': f.detail}],
            (g.list('injection')[i] as List).map((x) => {'id': x['id'], 'label': x['label'], 'detail': x['detail']}).toList());
      });
    }
  });

  group('PromptTools', () {
    for (var i = 0; i < prompts.length; i++) {
      test('rewrites fixture $i', () {
        final t = prompts[i];
        expect(PromptTools.shorten(t), g.list('shorten')[i]);
        expect(PromptTools.bulletify(t), g.list('bulletify')[i]);
        expect(PromptTools.tableify(t), g.list('tableify')[i]);
        for (final tone in PromptTools.tones) {
          expect(PromptTools.toneShift(t, tone), (g['tone'] as Map)[tone][i], reason: 'tone $tone');
        }
      });
      test('findings fixture $i', () {
        final t = prompts[i];
        expect([for (final f in PromptTools.scanAmbiguity(t)) {'sentence': f.sentence, 'index': f.index}], (g.list('ambiguity')[i] as List).map((x) => {'sentence': x['sentence'], 'index': x['index']}).toList());
        expect([for (final f in PromptTools.scanAdversarial(t)) {'id': f.id, 'label': f.label}], (g.list('adversarial')[i] as List).map((x) => {'id': x['id'], 'label': x['label']}).toList());
        expect([for (final f in PromptTools.findInternalRedundancy(t)) {'a': f.a, 'b': f.b}], (g.list('redundancy')[i] as List).map((x) => {'a': x['a'], 'b': x['b']}).toList());
      });
    }
    test('chainOfThoughtBlock', () => expect(PromptTools.chainOfThoughtBlock(), g['cot']));
  });

  group('Readability', () {
    for (var i = 0; i < prompts.length; i++) {
      test('fixture $i', () {
        final r = ReadabilityEngine.analyze(prompts[i]);
        final e = g.list('readability')[i] as Map<String, dynamic>;
        expect(r.fleschScore, e['fleschScore']);
        expect(r.gradeLevel, closeTo((e['gradeLevel'] as num).toDouble(), 1e-9));
        expect(r.avgSentenceLen, closeTo((e['avgSentenceLen'] as num).toDouble(), 1e-9));
        expect(r.avgWordLen, closeTo((e['avgWordLen'] as num).toDouble(), 1e-9));
        expect(r.syllablesPerWord, closeTo((e['syllablesPerWord'] as num).toDouble(), 1e-9));
        expect(r.label, e['label']);
      });
    }
    test('countSyllables', () {
      for (final row in g.list('syllables')) {
        expect(ReadabilityEngine.countSyllables(row[0] as String), row[1], reason: row[0] as String);
      }
    });
  });

  group('Validator', () {
    test('json validity', () {
      final inputs = (g.fixtures['json'] as List).cast<String>();
      final exp = g.list('validateJson');
      for (var i = 0; i < inputs.length; i++) {
        expect(PromptValidator.validate(inputs[i], 'json').valid, exp[i], reason: inputs[i]);
      }
    });
    test('xml validity', () {
      final inputs = (g.fixtures['xml'] as List).cast<String>();
      final exp = g.list('validateXml');
      for (var i = 0; i < inputs.length; i++) {
        expect(PromptValidator.validate(inputs[i], 'xml').valid, exp[i], reason: inputs[i]);
      }
    });
    for (var i = 0; i < prompts.length; i++) {
      test('embed safety fixture $i', () {
        expect([for (final e in PromptValidator.checkJsonEmbedSafety(prompts[i])) {'id': e.id, 'level': e.level}], (g.list('embed')[i] as List).map((x) => {'id': x['id'], 'level': x['level']}).toList());
      });
    }
  });

  group('FormatConverter', () {
    final sections = (g.fixtures['sections'] as List).cast<String>();
    const formats = ['text', 'markdown', 'xml', 'json'];
    test('extractSections', () {
      for (var i = 0; i < sections.length; i++) {
        for (var f = 0; f < formats.length; f++) {
          final e = (g.list('sections')[i] as List)[f] as Map<String, dynamic>;
          if (e.containsKey('error')) continue;
          final got = FormatConverter.extractSections(sections[i], formats[f]);
          expect([for (final s in got) {'label': s.label, 'content': s.content}], (e['ok'] as List).map((x) => {'label': x['label'], 'content': x['content']}).toList(), reason: '${formats[f]} / $i');
        }
      }
    });
    test('convert', () {
      (g['convert'] as Map<String, dynamic>).forEach((pair, list) {
        final parts = pair.split('>');
        for (var i = 0; i < sections.length; i++) {
          final e = (list as List)[i] as Map<String, dynamic>;
          if (e.containsKey('error')) continue;
          expect(FormatConverter.convert(sections[i], parts[0], parts[1]), e['ok'], reason: '$pair / $i');
        }
      });
    });
  });

  group('Utils', () {
    test('textSimilarity', () {
      final pairs = g.fixtures['similarityPairs'] as List;
      for (var i = 0; i < pairs.length; i++) {
        expect(Utils.textSimilarity(pairs[i][0] as String, pairs[i][1] as String), closeTo((g.list('similarity')[i] as num).toDouble(), 1e-12));
      }
    });
    test('diffWords', () {
      final pairs = g.fixtures['diffPairs'] as List;
      for (var i = 0; i < pairs.length; i++) {
        final got = Utils.diffWords(pairs[i][0] as String, pairs[i][1] as String);
        expect([for (final d in got) {'type': d.type, 'text': d.text}], (g.list('diff')[i] as List).map((x) => {'type': x['type'], 'text': x['text']}).toList(), reason: 'pair $i');
      }
    });
    for (var i = 0; i < prompts.length; i++) {
      test('tokenize/countWords/escapeHtml fixture $i', () {
        expect(Utils.tokenize(prompts[i]), (g.list('tokenize')[i] as List).cast<String>());
        expect(Utils.countWords(prompts[i]), g.list('countWords')[i]);
        expect(Utils.escapeHtml(prompts[i]), g.list('escapeHtml')[i]);
      });
    }
    test('csvEscape', () {
      final inputs = (g.fixtures['csv'] as List).cast<String>();
      for (var i = 0; i < inputs.length; i++) {
        expect(Utils.csvEscape(inputs[i]), g.list('csvEscape')[i], reason: inputs[i]);
      }
    });
    test('truncate', () {
      final inputs = g.fixtures['truncate'] as List;
      for (var i = 0; i < inputs.length; i++) {
        expect(Utils.truncate(inputs[i][0] as String, inputs[i][1] as int), g.list('truncate')[i]);
      }
    });
  });

  group('MessageComposer.splitSystemUser', () {
    for (var i = 0; i < prompts.length; i++) {
      test('fixture $i', () {
        final r = MessageComposer.splitSystemUser(prompts[i]);
        final e = g.list('splitSystemUser')[i] as Map<String, dynamic>;
        expect(r.system, e['system']);
        expect(r.user, e['user']);
      });
    }
  });

  group('DuplicateFinder', () {
    test('clusters match the original', () {
      final d = g['duplicates'] as Map<String, dynamic>;
      final bodies = (d['bodies'] as List).cast<String>();
      final ps = [for (var i = 0; i < bodies.length; i++) Prompt(id: 'p$i', title: 'P$i', body: bodies[i])];
      final got = DuplicateFinder.find(ps).map((c) => c.prompts.map((p) => p.id).toList()).toList();
      expect(got, (d['clusters'] as List).map((c) => (c as List).cast<String>()).toList());
    });
  });

  test('constants generated from the original CONFIG are present', () {
    expect(kCategories, isNotEmpty);
    expect(kBlockTypes, isNotEmpty);
    expect(kPatterns, isNotEmpty);
    expect(kScoringProfiles.map((p) => p.id), (g['profiles'] as Map).keys);
  });
}
