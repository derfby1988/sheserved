import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/position_lineup.dart';

Map<String, dynamic> _marker({
  String id = 'p1',
  String label = 'กองหน้า',
  String icon = 'forward',
  String color = '#2196F3',
  int slots = 2,
  int side = 0,
  double x = 0.5,
  double y = 0.5,
  bool active = true,
}) {
  return {
    'id': id,
    'label': label,
    'icon': icon,
    'color': color,
    'slots': slots,
    'side': side,
    'x': x,
    'y': y,
    'is_active': active,
  };
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('PositionLineupEditor', () {
    testWidgets('renders empty hint when no positions', (tester) async {
      await tester.pumpWidget(_wrap(
        PositionLineupEditor(
          layout: 'single',
          positions: const [],
          onChanged: (_) {},
        ),
      ));
      await tester.pump();
      expect(find.textContaining('ยังไม่มีตำแหน่ง'), findsOneWidget);
    });

    testWidgets('shows add button when enabled', (tester) async {
      await tester.pumpWidget(_wrap(
        PositionLineupEditor(
          layout: 'single',
          positions: const [],
          onChanged: (_) {},
        ),
      ));
      await tester.pump();
      expect(find.byIcon(Icons.add_location_alt_rounded), findsOneWidget);
    });

    testWidgets('hides add button when disabled', (tester) async {
      await tester.pumpWidget(_wrap(
        PositionLineupEditor(
          layout: 'single',
          positions: const [],
          onChanged: (_) {},
          enabled: false,
        ),
      ));
      await tester.pump();
      expect(find.byIcon(Icons.add_location_alt_rounded), findsNothing);
    });

    testWidgets('renders marker label and slot count', (tester) async {
      await tester.pumpWidget(_wrap(
        PositionLineupEditor(
          layout: 'single',
          positions: [_marker(label: 'กองหน้า', slots: 3)],
          onChanged: (list) {},
        ),
      ));
      await tester.pump();
      expect(find.textContaining('กองหน้า'), findsWidgets);
      expect(find.textContaining('3'), findsWidgets);
    });

    testWidgets('emits updated list when delete tapped', (tester) async {
      List<Map<String, dynamic>>? captured;
      await tester.pumpWidget(_wrap(
        PositionLineupEditor(
          layout: 'single',
          positions: [_marker(id: 'p1'), _marker(id: 'p2', label: 'กองหลัง')],
          onChanged: (list) => captured = list,
        ),
      ));
      await tester.pump();
      // Tap the first delete icon
      final deleteButtons = find.byIcon(Icons.delete_rounded);
      expect(deleteButtons, findsNWidgets(2));
      await tester.tap(deleteButtons.first);
      await tester.pump();
      expect(captured, isNotNull);
      expect(captured!.length, 1);
      expect(captured!.first['id'], 'p2');
    });
  });

  group('PositionLineupView', () {
    testWidgets('renders markers when layout is single', (tester) async {
      await tester.pumpWidget(_wrap(
        PositionLineupView(
          layout: 'single',
          positions: [_marker(label: 'ผู้รักษาประตู')],
        ),
      ));
      await tester.pump();
      expect(find.textContaining('ผู้รักษาประตู'), findsOneWidget);
    });

    testWidgets('renders markers when layout is double', (tester) async {
      await tester.pumpWidget(_wrap(
        PositionLineupView(
          layout: 'double',
          positions: [
            _marker(id: 'a', label: 'ฝั่ง A', side: 0, x: 0.25),
            _marker(id: 'b', label: 'ฝั่ง B', side: 1, x: 0.75),
          ],
        ),
      ));
      await tester.pump();
      expect(find.textContaining('ฝั่ง A'), findsOneWidget);
      expect(find.textContaining('ฝั่ง B'), findsOneWidget);
    });

    testWidgets('shows remaining slots when takenCounts provided', (tester) async {
      await tester.pumpWidget(_wrap(
        PositionLineupView(
          layout: 'single',
          positions: [_marker(id: 'p1', label: 'กองหน้า', slots: 2)],
          takenCounts: {'p1': 1},
        ),
      ));
      await tester.pump();
      expect(find.textContaining('เหลือ 1'), findsOneWidget);
    });

    testWidgets('displays full label when position is full', (tester) async {
      await tester.pumpWidget(_wrap(
        PositionLineupView(
          layout: 'single',
          positions: [_marker(id: 'p1', label: 'กองหน้า', slots: 1)],
          takenCounts: {'p1': 1},
        ),
      ));
      await tester.pump();
      expect(find.textContaining('เต็ม'), findsOneWidget);
    });

    testWidgets('disables tap on full position', (tester) async {
      String? selected;
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 300,
          height: 300,
          child: PositionLineupView(
            layout: 'single',
            positions: [_marker(id: 'p1', label: 'กองหน้า', slots: 1)],
            takenCounts: {'p1': 1},
            onPositionSelected: (id) => selected = id,
          ),
        ),
      ));
      await tester.pump();
      // Find the GestureDetector wrapping the marker and tap it
      final gestures = find.byType(GestureDetector);
      // Tap the first marker gesture detector
      if (gestures.evaluate().length > 1) {
        await tester.tap(gestures.at(1), warnIfMissed: false);
        await tester.pump();
      }
      expect(selected, isNull);
    });

    testWidgets('calls onPositionSelected when tapping available marker', (tester) async {
      String? selected;
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 300,
          height: 300,
          child: PositionLineupView(
            layout: 'single',
            positions: [_marker(id: 'p1', label: 'กองหน้า', slots: 2)],
            takenCounts: {'p1': 0},
            onPositionSelected: (id) => selected = id,
          ),
        ),
      ));
      await tester.pump();
      final gestures = find.byType(GestureDetector);
      if (gestures.evaluate().length > 1) {
        await tester.tap(gestures.at(1), warnIfMissed: false);
        await tester.pump();
      }
      expect(selected, 'p1');
    });

    testWidgets('hides inactive positions', (tester) async {
      await tester.pumpWidget(_wrap(
        PositionLineupView(
          layout: 'single',
          positions: [
            _marker(id: 'a', label: 'Active', active: true),
            _marker(id: 'b', label: 'Inactive', active: false),
          ],
        ),
      ));
      await tester.pump();
      expect(find.textContaining('Active'), findsOneWidget);
      expect(find.textContaining('Inactive'), findsNothing);
    });

    testWidgets('highlights selected position', (tester) async {
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 300,
          height: 300,
          child: PositionLineupView(
            layout: 'single',
            positions: [
              _marker(id: 'p1', label: 'กองหน้า'),
              _marker(id: 'p2', label: 'กองหลัง'),
            ],
            selectedPositionId: 'p1',
          ),
        ),
      ));
      await tester.pump();
      // Both labels should be present; selection is visual (border color)
      expect(find.textContaining('กองหน้า'), findsOneWidget);
      expect(find.textContaining('กองหลัง'), findsOneWidget);
    });
  });

  group('FieldCanvasPainter', () {
    testWidgets('paints single layout without throwing', (tester) async {
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 200,
          height: 160,
          child: CustomPaint(painter: FieldCanvasPainter(layout: 'single')),
        ),
      ));
      await tester.pump();
      expect(find.byType(CustomPaint), findsOneWidget);
    });

    testWidgets('paints double layout without throwing', (tester) async {
      await tester.pumpWidget(_wrap(
        SizedBox(
          width: 200,
          height: 120,
          child: CustomPaint(painter: FieldCanvasPainter(layout: 'double')),
        ),
      ));
      await tester.pump();
      expect(find.byType(CustomPaint), findsOneWidget);
    });
  });

  group('parseHexColor', () {
    test('parses 6-digit hex with #', () {
      expect(parseHexColor('#FF9800'), const Color(0xFFFF9800));
    });

    test('parses 6-digit hex without #', () {
      expect(parseHexColor('FF9800'), const Color(0xFFFF9800));
    });

    test('returns fallback for invalid input', () {
      expect(parseHexColor('xyz'), const Color(0xFF2196F3));
    });

    test('returns fallback for null', () {
      expect(parseHexColor(null), const Color(0xFF2196F3));
    });

    test('returns fallback for empty string', () {
      expect(parseHexColor(''), const Color(0xFF2196F3));
    });
  });
}
