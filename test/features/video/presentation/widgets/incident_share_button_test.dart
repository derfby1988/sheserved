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
    testWidgets('renders default state with LitGlassSurface and share icon',
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
      expect(find.text('แชร์เหตุการณ์'), findsOneWidget);
      expect(find.byIcon(Icons.share_rounded), findsOneWidget);

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

      expect(find.text('แชร์ภาพนี้'), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);

      final surface = tester.widget<LitGlassSurface>(
        find.byType(LitGlassSurface),
      );
      expect(surface.selected, isTrue);
      expect(surface.accentColor, const Color(0xFF38BDF8));
    });

    testWidgets('renders custom label when provided', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          IncidentShareButton(
            onPressed: () {},
            customLabel: 'แชร์คลิปนี้',
          ),
        ),
      );

      expect(find.text('แชร์คลิปนี้'), findsOneWidget);
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
      expect(find.text('แชร์เหตุการณ์'), findsNothing);

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

    testWidgets('handles narrow column width without overflow via FittedBox',
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
      expect(find.byType(FittedBox), findsOneWidget);
    });
  });
}
