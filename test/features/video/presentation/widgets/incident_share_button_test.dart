import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/incident_share_button.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

void main() {
  Widget buildTestableWidget(Widget child, {double width = 120}) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(
            width: width,
            child: child,
          ),
        ),
      ),
    );
  }

  group('IncidentShareButton Tests', () {
    Semantics buttonSemantics(WidgetTester tester) {
      return tester.widget<Semantics>(
        find.descendant(
          of: find.byType(IncidentShareButton),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label != null,
          ),
        ),
      );
    }

    testWidgets('renders default state as round icon-only button (orange icon)',
        (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        buildTestableWidget(
          IncidentShareButton(
            onPressed: () => pressed = true,
          ),
        ),
      );

      expect(find.byType(LitGlassSurface), findsOneWidget);
      // Icon-only design — no text is rendered; the label lives in Semantics
      expect(find.byType(Text), findsNothing);
      expect(buttonSemantics(tester).properties.label, 'แชร์เหตุการณ์');
      final icon = tester.widget<Icon>(find.byIcon(Icons.share_rounded));
      expect(icon.color, const Color(0xFFFF6B35));

      await tester.tap(find.byType(IncidentShareButton));
      await tester.pump();
      expect(pressed, isTrue);
    });

    testWidgets('renders photo focused state with image icon and cyan accent',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          IncidentShareButton(
            onPressed: () {},
            isPhotoFocused: true,
          ),
        ),
      );

      expect(find.byType(Text), findsNothing);
      expect(buttonSemantics(tester).properties.label, 'แชร์ภาพนี้');
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);

      final surface = tester.widget<LitGlassSurface>(
        find.byType(LitGlassSurface),
      );
      expect(surface.selected, isTrue);
      expect(surface.accentColor, const Color(0xFF38BDF8));
    });

    testWidgets('uses custom label for semantics when provided',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          IncidentShareButton(
            onPressed: () {},
            customLabel: 'แชร์คลิปนี้',
          ),
        ),
      );

      expect(buttonSemantics(tester).properties.label, 'แชร์คลิปนี้');
    });

    testWidgets('shows loading spinner when isLoading is true and ignores tap',
        (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        buildTestableWidget(
          IncidentShareButton(
            onPressed: () => pressed = true,
            isLoading: true,
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(Icon), findsNothing);

      await tester.tap(find.byType(IncidentShareButton));
      await tester.pump();
      expect(pressed, isFalse);
    });

    testWidgets('disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const IncidentShareButton(
            onPressed: null,
          ),
        ),
      );

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(animatedOpacity.opacity, 0.6);
    });

    testWidgets('press down triggers AnimatedScale 0.96 (Neumorphic bounce)',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          IncidentShareButton(
            onPressed: () {},
          ),
        ),
      );

      final gesture = await tester.createGesture();
      await gesture.down(tester.getCenter(find.byType(IncidentShareButton)));
      await tester.pump(const Duration(milliseconds: 100));

      final animatedScale = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(animatedScale.scale, 0.96);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));

      final releasedScale = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(releasedScale.scale, 1.0);
    });

    testWidgets('renders as a 34dp-high round button without overflow',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          IncidentShareButton(
            onPressed: () {},
          ),
          width: 60, // Very narrow column
        ),
      );

      expect(tester.takeException(), isNull);
      // กล่องกระจกคงขนาด 34x34 ภายใต้ Align (Column ผู้ใช้ stretch ความกว้าง)
      final boxFinder = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 34 && w.height == 34,
      );
      expect(boxFinder, findsOneWidget);
      final surface = tester.widget<LitGlassSurface>(
        find.byType(LitGlassSurface),
      );
      expect(surface.borderRadius, 17); // 34dp box + radius 17 = circle
    });
  });
}
