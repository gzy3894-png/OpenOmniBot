import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat/widgets/codex_goal_editor_sheet.dart';
import 'package:ui/features/home/pages/chat/widgets/codex_goal_mode_bar.dart';

void main() {
  testWidgets('prefills Goal and saves editor text exactly once', (
    tester,
  ) async {
    var saveCount = 0;
    String? savedGoal;
    await tester.pumpWidget(
      _editorHarness(
        initialGoal: 'existing goal',
        onSave: (goal) async {
          saveCount += 1;
          savedGoal = goal;
          return true;
        },
      ),
    );

    await _openEditor(tester);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('codex-goal-editor-field')),
    );
    expect(field.controller!.text, 'existing goal');

    await tester.enterText(
      find.byKey(const ValueKey('codex-goal-editor-field')),
      '  updated goal  ',
    );
    await tester.tap(
      find.byKey(const ValueKey('codex-goal-editor-save')),
    );
    await tester.pumpAndSettle();

    expect(saveCount, 1);
    expect(savedGoal, 'updated goal');
    expect(
      find.byKey(const ValueKey('codex-goal-editor-field')),
      findsNothing,
    );
  });

  testWidgets('cancel closes editor without saving', (tester) async {
    var saveCount = 0;
    await tester.pumpWidget(
      _editorHarness(
        initialGoal: 'existing goal',
        onSave: (_) async {
          saveCount += 1;
          return true;
        },
      ),
    );

    await _openEditor(tester);
    await tester.tap(
      find.byKey(const ValueKey('codex-goal-editor-cancel')),
    );
    await tester.pumpAndSettle();

    expect(saveCount, 0);
    expect(
      find.byKey(const ValueKey('codex-goal-editor-field')),
      findsNothing,
    );
  });

  testWidgets('failed save keeps the independent editor draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      _editorHarness(
        initialGoal: 'old goal',
        onSave: (_) async => false,
      ),
    );

    await _openEditor(tester);
    await tester.enterText(
      find.byKey(const ValueKey('codex-goal-editor-field')),
      'new draft',
    );
    await tester.tap(
      find.byKey(const ValueKey('codex-goal-editor-save')),
    );
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('codex-goal-editor-field')),
    );
    expect(field.controller!.text, 'new draft');
    expect(find.textContaining('Goal was not saved'), findsOneWidget);
  });

  testWidgets('Goal bar body edits while X only clears', (tester) async {
    var editCount = 0;
    var clearCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodexGoalModeBar(
            goalText: 'active goal',
            onTap: () => editCount += 1,
            onClear: () => clearCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('codex-goal-mode-bar')),
    );
    await tester.pump();
    expect(editCount, 1);
    expect(clearCount, 0);

    await tester.tap(
      find.byKey(const ValueKey('codex-goal-mode-bar-clear')),
    );
    await tester.pump();
    expect(editCount, 1);
    expect(clearCount, 1);
  });
}

Widget _editorHarness({
  required String initialGoal,
  required CodexGoalSaveCallback onSave,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => FilledButton(
          key: const ValueKey('open-goal-editor'),
          onPressed: () {
            showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              builder: (_) => CodexGoalEditorSheet(
                initialGoal: initialGoal,
                onSave: onSave,
              ),
            );
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-goal-editor')));
  await tester.pumpAndSettle();
}
