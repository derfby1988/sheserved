import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/home/presentation/widgets/home_pharmacy_card.dart';
import 'package:sheserved/features/sport_club/presentation/pages/sports_hub_page.dart';

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
  }
}

void main() {
  testWidgets('opens the Sports Hub from the club CTA', (tester) async {
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const Scaffold(body: HomePharmacyCard()),
      ),
    );

    await tester.tap(find.text('เข้าคลับ'));

    expect(observer.pushedRoutes, hasLength(2));
    final route = observer.pushedRoutes.last;
    expect(route, isA<MaterialPageRoute<void>>());
    final page = (route as MaterialPageRoute<void>).builder(
      tester.element(find.byType(HomePharmacyCard)),
    );
    expect(page, isA<SportsHubPage>());
    expect((page as SportsHubPage).initialPage, 1);
  });

  testWidgets(
    'fits a small phone without growing the card or overlapping CTA',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              key: ValueKey('card-size'),
              width: 360,
              child: HomePharmacyCard(),
            ),
          ),
        ),
      );
      await tester.pump();

      final titleRect = tester.getRect(find.textContaining('คลับของคนรัก'));
      final ctaRect = tester.getRect(
        find.ancestor(
          of: find.text('เข้าคลับ'),
          matching: find.byType(InkWell),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('card-size'))).height,
        lessThanOrEqualTo(80),
      );
      expect(ctaRect.top, greaterThanOrEqualTo(titleRect.bottom));
    },
  );
}
