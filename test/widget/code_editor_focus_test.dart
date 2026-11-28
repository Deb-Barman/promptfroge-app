import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_forge/ui/screens/editor/code_editor.dart';
import 'package:prompt_forge/ui/theme/app_theme.dart';

/// Regression test for "the mobile keyboard closes after every word I type".
///
/// The autocomplete popup opens a moment after two letters are typed. CodeEditor used to return a bare editor when
/// there was no popup and a Stack when there was one; that changes the root widget type, so Flutter disposed the
/// TextField and built a brand-new one each time the suggestion list opened or closed. The new field had no focus and
/// no input connection, which closes the soft keyboard in the middle of a word.
void main() {
  testWidgets('opening and closing the suggestion popup keeps the same text field and its focus', (tester) async {
    final controller = HighlightingController(text: 'You are an exp');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    Widget host({Widget? popup}) => MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 500,
              child: CodeEditor(
                controller: controller,
                focusNode: focus,
                fontFamily: 'JetBrains Mono',
                fontFallback: const ['monospace'],
                fontSize: 14,
                lineNumbers: true,
                wordWrap: true,
                popup: popup,
                popupHeight: 34,
                popupWidth: 200,
              ),
            ),
          ),
        );

    // The user taps into the editor: it has focus (this is the moment the keyboard opens).
    await tester.pumpWidget(host());
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    final before = tester.state<EditableTextState>(find.byType(EditableText));

    // They type a word: the suggestion list opens. The same field must stay mounted and focused.
    await tester.pumpWidget(host(popup: const SizedBox(height: 34, child: Text('explain'))));
    await tester.pump();
    expect(find.text('explain'), findsOneWidget);
    expect(focus.hasFocus, isTrue, reason: 'opening the popup must not take focus away, or the keyboard closes');
    expect(tester.state<EditableTextState>(find.byType(EditableText)), same(before), reason: 'the TextField must not be rebuilt from scratch');

    // They type a space (or pick a suggestion): the list closes. Still the same field, still focused.
    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.text('explain'), findsNothing);
    expect(focus.hasFocus, isTrue);
    expect(tester.state<EditableTextState>(find.byType(EditableText)), same(before));
  });
}
