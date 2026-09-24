import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/consultation/presentation/widgets/closed_ended/adaptive_closed_ended_layout.dart';
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
