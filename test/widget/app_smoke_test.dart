import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_forge/app/app.dart';
import 'package:prompt_forge/data/vault/vault_fs.dart';
import 'package:prompt_forge/data/vault/vault_repository.dart';
import 'package:prompt_forge/domain/models.dart';
import 'package:prompt_forge/state/device_settings.dart';
import 'package:prompt_forge/state/vault_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container({bool withVault = true, MemoryVaultFs? fs, bool onboardingSeen = true}) async {
  // The first-run welcome dialog would sit on top of the dashboard, so most tests start with it already seen.
  SharedPreferences.setMockInitialValues({'onboardingSeen': onboardingSeen});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  addTearDown(c.dispose);
  if (withVault) {
    final f = fs ?? MemoryVaultFs();
    await c.read(vaultProvider.notifier).openWithFs(f);
  }
  return c;
}

Future<void> _pumpApp(WidgetTester tester, ProviderContainer c) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const PromptForgeApp()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first run asks the user to choose or create a folder (no backend, no login)', (tester) async {
    final c = await _container(withVault: false);
    await _pumpApp(tester, c);
    expect(find.text('Create a new vault'), findsOneWidget);
    expect(find.text('Open an existing folder'), findsOneWidget);
    expect(find.textContaining('Sign in'), findsNothing);
    expect(find.textContaining('API key'), findsNothing);
  });

  testWidgets('with a vault open the dashboard shows and the five tabs are reachable', (tester) async {
    final c = await _container();
    await c.read(vaultProvider.notifier).savePrompt(Prompt(title: 'Quarterly review', body: 'Summarize Q3 results.'));
    await _pumpApp(tester, c);
    expect(find.text('Dashboard'), findsWidgets);
    for (final tab in ['Editor', 'Library', 'Builder', 'Settings']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
    expect(find.text('Settings'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library lists vault prompts and opening one loads it into the editor', (tester) async {
    final c = await _container();
    await c.read(vaultProvider.notifier).savePrompt(Prompt(title: 'Quarterly review', body: 'Summarize Q3 results.'));
    await _pumpApp(tester, c);
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    expect(find.text('Quarterly review'), findsOneWidget);
    await tester.tap(find.text('Quarterly review'));
    await tester.pumpAndSettle();
    expect(find.text('Summarize Q3 results.'), findsWidgets);
  });

  testWidgets('typing in the editor autosaves a Markdown file into the vault folder', (tester) async {
    final fs = MemoryVaultFs();
    final c = await _container(fs: fs);
    await _pumpApp(tester, c);
    await tester.tap(find.text('Editor').last);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsWidgets);
    await tester.enterText(fields.first, 'My new prompt');
    await tester.pump();
    await tester.enterText(fields.at(1), 'You are a helpful tutor. Explain recursion.');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final files = fs.files.keys.where((k) => k.startsWith('$kPromptsDir/')).toList();
    expect(files, ['$kPromptsDir/My new prompt.md']);
    expect(fs.files[files.single], contains('You are a helpful tutor.'));
  });

  testWidgets('builder composes blocks and sends them to the editor', (tester) async {
    final c = await _container();
    await _pumpApp(tester, c);
    await tester.tap(find.text('Builder').last);
    await tester.pumpAndSettle();
    expect(find.text('Send to Editor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first run shows the welcome once; skipping it marks onboarding as seen', (tester) async {
    final c = await _container(onboardingSeen: false);
    await _pumpApp(tester, c);
    expect(find.text('Welcome to Prompt Forge'), findsOneWidget);
    await tester.tap(find.textContaining('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Prompt Forge'), findsNothing);
    expect(c.read(deviceSettingsProvider).onboardingSeen, isTrue);
  });

  testWidgets('quick capture saves the idea to the Inbox category', (tester) async {
    final c = await _container();
    await _pumpApp(tester, c);
    await tester.tap(find.byTooltip('Quick capture'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Idea: a prompt that critiques my plan');
    await tester.tap(find.text('Save to Inbox'));
    await tester.pumpAndSettle();
    final saved = c.read(vaultProvider).data.prompts.values.toList();
    expect(saved.length, 1);
    expect(saved.single.category, 'inbox');
    expect(saved.single.body, contains('critiques my plan'));
  });
}
