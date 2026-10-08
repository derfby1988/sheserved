import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/application/court_card_style_service.dart';
import 'package:sheserved/features/sport_club/book_court/domain/court_card_style.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_card_style_panel.dart';

void main() {
  setUp(() {
    CourtCardStyleService.instance.style.value = CourtCardStyle.classic;
  });

  testWidgets('previews every style and marks the active one', (tester) async {
    tester.view.physicalSize = const Size(1200, 5200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CourtCardStylePanel())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    for (final style in CourtCardStyle.values) {
      expect(
        find.byKey(ValueKey('court-card-style-${style.wireValue}')),
        findsOneWidget,
      );
      expect(find.text(style.label), findsWidgets);
    }
    expect(find.text('4.3'), findsNothing);
    expect(find.text('คะแนนสนาม'), findsNothing);
    expect(find.text('ใช้อยู่'), findsOneWidget);
    expect(
      find.text('ใช้อยู่ตอนนี้: ${CourtCardStyle.classic.label}'),
      findsOneWidget,
    );
  });

  testWidgets('selecting a style applies it to the card service', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 5200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CourtCardStylePanel())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final selectButton = find.byKey(
      const ValueKey('court-card-style-select-painter_3d'),
    );
    await tester.ensureVisible(selectButton);
    await tester.pump();
    await tester.tap(selectButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      CourtCardStyleService.instance.style.value,
      CourtCardStyle.painter3d,
    );
    // Supabase is unavailable in tests, so the panel reports the local-only
    // outcome instead of claiming the shared setting was saved.
    expect(find.textContaining('เปลี่ยนบนเครื่องนี้แล้ว'), findsOneWidget);
    expect(
      find.text('ใช้อยู่ตอนนี้: ${CourtCardStyle.painter3d.label}'),
      findsOneWidget,
    );
  });

  testWidgets('3D icon toggle switches between 3D voxels and custom image presets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 5200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // Start with 3D style
    CourtCardStyleService.instance.style.value = CourtCardStyle.painter3d;

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CourtCardStylePanel())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Toggle should be present and ON by default
    final toggleFinder = find.byKey(const ValueKey('court-card-3d-icon-toggle'));
    expect(toggleFinder, findsOneWidget);

    // Switch OFF the 3D icon
    await tester.ensureVisible(toggleFinder);
    await tester.pump();
    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    // Now replacement image section should appear with presets
    expect(find.text('เลือกรูปภาพแทนไอคอน 3 มิติ'), findsOneWidget);
    expect(find.byKey(const ValueKey('preset-chip-preset:tennis')), findsOneWidget);
    expect(find.byKey(const ValueKey('preset-chip-preset:badminton')), findsOneWidget);

    // Tap badminton preset chip
    final badmintonChip = find.byKey(const ValueKey('preset-chip-preset:badminton'));
    await tester.tap(badmintonChip);
    await tester.pumpAndSettle();

    // Save button should be visible when params are dirty
    final saveButton = find.byKey(const ValueKey('court-card-save-3d-params-button'));
    expect(saveButton, findsOneWidget);

    // Tap save
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(CourtCardStyleService.instance.params3d.value.show3dIcon, isFalse);
    expect(CourtCardStyleService.instance.params3d.value.customImageUrl, 'preset:badminton');
  });

  testWidgets('shadow management sliders are visible in 3D params section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 5200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    CourtCardStyleService.instance.style.value = CourtCardStyle.painter3d;

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CourtCardStylePanel())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Shadow controls section and sliders should be rendered
    expect(find.text('การจัดการเงาและแสงสะท้อน'), findsOneWidget);
    expect(find.text('ความกว้างเงา'), findsOneWidget);
    expect(find.text('ความยาวเงา'), findsOneWidget);
    expect(find.text('ความเข้มเงา'), findsOneWidget);
  });
}
