import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/consultation/presentation/widgets/closed_ended/adaptive_closed_ended_layout.dart';
import 'package:sheserved/features/consultation/presentation/widgets/closed_ended/radial_question_layout.dart';
import 'package:sheserved/features/consultation/presentation/widgets/radial_question_view.dart';

void main() {
  group('RadialQuestionView responsive layout', () {
    test('uses compact mode when the available height is landscape-sized', () {
      expect(
        AdaptiveClosedEndedLayout.canUseRadialLayout(
          size: const Size(390, 844),
          questionText: 'ปวดไหม',
          options: const ['ใช่', 'ไม่ใช่', 'ไม่แน่ใจ'],
          textScale: 1,
        ),
        isTrue,
      );
      expect(
        AdaptiveClosedEndedLayout.canUseRadialLayout(
          size: const Size(390, 390),
          questionText: 'ไม่ระบุปัญหา',
          options: const ['ใช่', 'ไม่ใช่', 'ไม่แน่ใจ'],
          textScale: 1,
          radialTopInset: 64,
          radialBottomInset: 16,
        ),
        isTrue,
      );
      expect(
        AdaptiveClosedEndedLayout.canUseRadialLayout(
          size: const Size(390, 260),
          questionText: 'ปวดไหม',
          options: const ['ใช่', 'ไม่ใช่', 'ไม่แน่ใจ'],
          textScale: 1,
          radialTopInset: 64,
          radialBottomInset: 16,
        ),
        isFalse,
      );
      expect(
        AdaptiveClosedEndedLayout.canUseRadialLayout(
          size: const Size(390, 390),
          questionText: 'Question',
          options: const ['Long choice', 'Yes'],
          textScale: 1,
          radialTopInset: 64,
          radialBottomInset: 16,
        ),
        isFalse,
      );
      expect(
        AdaptiveClosedEndedLayout.canUseRadialLayout(
          size: const Size(390, 400),
          questionText: 'Question',
          options: const ['Long choice', 'Yes'],
          textScale: 1,
          radialTopInset: 64,
          radialBottomInset: 16,
        ),
        isTrue,
      );
      expect(
        AdaptiveClosedEndedLayout.canUseRadialLayout(
          size: const Size(844, 390),
          questionText: 'ปวดไหม',
          options: const ['ใช่', 'ไม่ใช่', 'ไม่แน่ใจ'],
          textScale: 1,
        ),
        isFalse,
      );
    });

    testWidgets('reflows immediately on rotation and preserves the question', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_questionView());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 900));

      expect(
        find.byKey(const ValueKey('closed-ended-radial-layout')),
        findsOneWidget,
      );
      expect(find.text('ปวดไหม'), findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey('closed-ended-compact-layout')),
        findsOneWidget,
      );
      expect(find.text('ปวดไหม'), findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey('closed-ended-radial-layout')),
        findsOneWidget,
      );
      expect(find.text('ปวดไหม'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'keeps the selected answer and confirmation dialog during rotation',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_questionView());
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 900));
        await tester.tap(find.byKey(const ValueKey('closed-ended-option-0')));
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('ยืนยันคำตอบ'), findsOneWidget);

        tester.view.physicalSize = const Size(844, 390);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.byKey(const ValueKey('closed-ended-compact-layout')),
          findsOneWidget,
        );
        expect(find.text('ยืนยันคำตอบ'), findsOneWidget);
        expect(find.text('ใช่'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('uses a radial layout in a compact chat viewport', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 390,
                height: 390,
                child: RadialQuestionView(
                  questionText: 'ไม่ระบุปัญหา',
                  config: ClosedEndedConfig.quantitative(3),
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 900));

      expect(
        find.byKey(const ValueKey('closed-ended-radial-layout')),
        findsOneWidget,
      );
      final center = tester.getCenter(find.byType(RadialQuestionLayout));
      final first = tester.getCenter(
        find.byKey(const ValueKey('closed-ended-option-0')),
      );
      final second = tester.getCenter(
        find.byKey(const ValueKey('closed-ended-option-1')),
      );
      final third = tester.getCenter(
        find.byKey(const ValueKey('closed-ended-option-2')),
      );
      expect(first.dy, lessThan(center.dy));
      expect(second.dx, greaterThan(center.dx));
      expect(second.dy, greaterThan(center.dy));
      expect(third.dx, lessThan(center.dx));
      expect(third.dy, greaterThan(center.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('places qualitative cards around the central question', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 390,
                height: 390,
                child: RadialQuestionView(
                  questionText: 'ระดับอาการ',
                  config: ClosedEndedConfig.qualitative(const [
                    'ใช่',
                    'ปวดน้อย',
                    'ไม่ปวดเลย',
                  ]),
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 900));

      expect(
        find.byKey(const ValueKey('closed-ended-radial-layout')),
        findsOneWidget,
      );
      final center = tester.getCenter(find.byType(RadialQuestionLayout));
      final centerRect = tester.getRect(
        find.byKey(const ValueKey('closed-ended-question-center')),
      );
      final firstFinder = find.byKey(const ValueKey('closed-ended-option-0'));
      final secondFinder = find.byKey(const ValueKey('closed-ended-option-1'));
      final thirdFinder = find.byKey(const ValueKey('closed-ended-option-2'));
      final first = tester.getCenter(firstFinder);
      final second = tester.getCenter(secondFinder);
      final third = tester.getCenter(thirdFinder);
      expect(first.dx, lessThan(center.dx));
      expect(first.dy, lessThan(center.dy));
      expect(second.dx, greaterThan(center.dx));
      expect(second.dy, lessThan(center.dy));
      expect(third.dy, greaterThan(center.dy));
      expect(centerRect.overlaps(tester.getRect(firstFinder)), isFalse);
      expect(centerRect.overlaps(tester.getRect(secondFinder)), isFalse);
      expect(
        centerRect.overlaps(tester.getRect(thirdFinder)),
        isFalse,
        reason: 'center=$centerRect third=${tester.getRect(thirdFinder)}',
      );
      expect(
        tester.getSize(thirdFinder).width,
        greaterThan(tester.getSize(firstFinder).width),
      );
      expect(find.text('ไม่ปวดเลย'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sizes compact qualitative cards to their labels', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 390,
                height: 260,
                child: RadialQuestionView(
                  questionText: 'ระดับอาการ',
                  config: ClosedEndedConfig.qualitative(const [
                    'ใช่',
                    'ปวดบริเวณลำตัวตอนกลางคืน',
                  ]),
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 900));

      expect(
        find.byKey(const ValueKey('closed-ended-compact-layout')),
        findsOneWidget,
      );
      final shortCard = tester.getSize(
        find.byKey(const ValueKey('closed-ended-option-0')),
      );
      final longCard = tester.getSize(
        find.byKey(const ValueKey('closed-ended-option-1')),
      );
      expect(longCard.width, greaterThan(shortCard.width));
      expect(shortCard.height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders quantitative choices in both layout modes', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadialQuestionView(
              questionText: 'ปวดไหม',
              config: ClosedEndedConfig.quantitative(5),
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 900));

      expect(
        find.byKey(const ValueKey('closed-ended-radial-layout')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('closed-ended-option-4')),
        findsOneWidget,
      );

      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey('closed-ended-compact-layout')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('closed-ended-option-4')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('restores the portrait preference when the view closes', (
      tester,
    ) async {
      final orientationPreferences = <List<dynamic>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientationPreferences.add(
            List<dynamic>.from(call.arguments as List),
          );
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(_questionView());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 900));

      expect(orientationPreferences.first, hasLength(4));
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(orientationPreferences.last, hasLength(2));
    });

    testWidgets(
      'uses a scrollable layout for many long labels without overflow',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        final options = List.generate(
          10,
          (index) => 'ตัวเลือกคำตอบที่มีข้อความยาว ${index + 1}',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RadialQuestionView(
                questionText: 'ปวดไหม',
                config: ClosedEndedConfig.qualitative(options),
                onClose: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 900));

        expect(
          find.byKey(const ValueKey('closed-ended-compact-layout')),
          findsOneWidget,
        );
        expect(find.text(options.first), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

Widget _questionView() {
  return MaterialApp(
    home: Scaffold(
      body: RadialQuestionView(
        questionText: 'ปวดไหม',
        config: ClosedEndedConfig.qualitative(const [
          'ใช่',
          'ไม่ใช่',
          'ไม่แน่ใจ',
        ]),
        onClose: () {},
      ),
    ),
  );
}
