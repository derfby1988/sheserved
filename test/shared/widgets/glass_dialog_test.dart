import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/consultation/presentation/widgets/closed_ended/closed_ended_confirmation_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_confirm_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

void main() {
  testWidgets('GlassConfirmDialog returns true after successful confirmation', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await GlassConfirmDialog.show(
                  context,
                  icon: Icons.check_circle_outline,
                  title: 'Confirmation',
                  content: const Text('Content'),
                  accentColor: Colors.teal,
                  cancelLabel: 'Cancel',
                  confirmLabel: 'Confirm',
                  onConfirm: () async => true,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(LitGlassSurface), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('GlassConfirmDialog stays open and shows an error on failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => GlassConfirmDialog.show(
                context,
                title: 'Confirmation',
                content: const Text('Content'),
                accentColor: Colors.teal,
                cancelLabel: 'Cancel',
                confirmLabel: 'Confirm',
                errorMessage: 'Try again',
                onConfirm: () async => false,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
  });

  testWidgets('GlassConfirmDialog returns false when canceled', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await GlassConfirmDialog.show(
                  context,
                  title: 'Confirmation',
                  content: const Text('Content'),
                  accentColor: Colors.teal,
                  cancelLabel: 'Cancel',
                  confirmLabel: 'Confirm',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('GlassDialog returns the route result through the shared shell', (
    tester,
  ) async {
    int? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await GlassDialog.show<int>(
                  context: context,
                  contentPadding: EdgeInsets.zero,
                  builder: (dialogContext) => TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(42),
                    child: const Text('Return'),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(LitGlassSurface), findsOneWidget);
    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();

    expect(result, 42);
  });

  testWidgets('Closed-ended confirmation keeps its answer preview', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await ClosedEndedConfirmationDialog.show(
                  context,
                  questionText: 'อาการวันนี้เป็นอย่างไร',
                  selectedLabel: 'ดีขึ้น',
                  selectedIndex: 1,
                  optionColor: Colors.teal,
                  isQuantitative: false,
                  onConfirm: () async => true,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('ยืนยันคำตอบ'), findsOneWidget);
    expect(find.text('ดีขึ้น'), findsOneWidget);
    expect(find.text('อาการวันนี้เป็นอย่างไร'), findsOneWidget);
    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
