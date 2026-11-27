import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_forge/domain/engines/model_import.dart';
import 'package:prompt_forge/domain/models.dart';

void main() {
  group('ModelImport', () {
    test('reads the documented example', () {
      final r = ModelImport.parse(ModelImport.example);
      expect(r.problems.isEmpty, isTrue);
      expect(r.models.length, equals(1));
      final m = r.models.first;
      expect(m.label, equals('Gemini 3'));
      expect(m.vendor, equals('Google'));
      expect(m.groupLabel, equals('Gemini'));
      expect(m.contextWindow, equals(2000000));
      expect(m.priceIn, equals(2.0));
      expect(m.priceOut, equals(8.0));
    });

    test('accepts a single object and a models wrapper', () {
      expect(ModelImport.parse('{"label":"A"}').models.length, equals(1));
      expect(ModelImport.parse('{"models":[{"label":"A"},{"label":"B"}]}').models.length, equals(2));
    });

    test('fills sensible defaults and falls back to the vendor as group', () {
      final m = ModelImport.parse('[{"label":"X","vendor":"Acme"}]').models.first;
      expect(m.groupLabel, equals('Acme'));
      expect(m.contextWindow, equals(128000));
      expect(m.priceIn, equals(0.0));
      expect(m.priceNote, equals('per 1M tokens'));
    });

    test('is forgiving about numbers written as text and ignores negatives', () {
      final m = ModelImport.parse('[{"label":"X","contextWindow":"1,000,000","priceIn":"2.5","priceOut":-3}]').models.first;
      expect(m.contextWindow, equals(1000000));
      expect(m.priceIn, equals(2.5));
      expect(m.priceOut, equals(0.0));
    });

    test('reports entries it had to skip but keeps the good ones', () {
      final r = ModelImport.parse('[{"label":"Good"},{"vendor":"NoLabel"},"oops"]');
      expect(r.models.length, equals(1));
      expect(r.problems.length, equals(2));
    });

    test('explains invalid and empty input', () {
      expect(ModelImport.parse('{nope').problems.isNotEmpty, isTrue);
      expect(ModelImport.parse('   ').problems.isNotEmpty, isTrue);
      expect(ModelImport.parse('[]').models.isEmpty, isTrue);
    });

    test('custom models round-trip through the settings map, including the new fields', () {
      final s = VaultSettings(customModels: [CustomModel(label: 'M', vendor: 'V', group: 'G', priceNote: 'n')], hideBuiltinModels: true);
      final back = VaultSettings.fromMap(s.toMap());
      expect(back.customModels.first.group, equals('G'));
      expect(back.customModels.first.priceNote, equals('n'));
      expect(back.hideBuiltinModels, isTrue);
      expect(VaultSettings.fromMap({'customModels': [{'label': 'Old'}]}).customModels.first.groupLabel, equals('Custom'));
    });
  });
}
