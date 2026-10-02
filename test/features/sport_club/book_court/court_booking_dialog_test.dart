import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';
import 'package:sheserved/shared/widgets/thai_buddhist_date_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/domain/venue_local_time.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_booking_dialog.dart';

CourtAvailability _availability(DateTime from) => CourtAvailability(
  courtId: 'court-1',
  hours: [
    VenueOperatingHours(
      dayOfWeek: from.weekday % 7,
      openTime: '06:00',
      closeTime: '23:00',
    ),
  ],
);

Future<void> _openDialog(
  WidgetTester tester, {
  bool allowDisjoint = true,
  DateTime? initialSlotStart,
  Future<CourtAvailability> Function(String, DateTime, DateTime)?
  loadAvailability,
  void Function(List<({DateTime start, DateTime end})>? result)? onResult,
}) async {
  final date = VenueLocalTime.addCalendarDays(
    VenueLocalTime.today('Asia/Bangkok'),
    1,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await CourtBookingDialog.show(
                context,
                court: const VenueCourt(
                  id: 'court-1',
                  venueId: 'venue-1',
                  sportId: 'sport-1',
                  name: 'คอร์ท A',
                ),
                venueName: 'สนามทดสอบ',
                timezone: 'Asia/Bangkok',
                initialDate: date,
                initialSlotStart: initialSlotStart,
                allowDisjoint: allowDisjoint,
                loadAvailability:
                    loadAvailability ??
                    (_, from, to) async => _availability(from),
              );
              onResult?.call(result);
            },
            child: const Text('เปิด'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('เปิด'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('booking selection resolves wall time in venue timezone', (
    tester,
  ) async {
    const timezone = 'Asia/Bangkok';
    final date = VenueLocalTime.addCalendarDays(
      VenueLocalTime.today(timezone),
      1,
    );
    List<({DateTime start, DateTime end})>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await CourtBookingDialog.show(
                  context,
                  court: const VenueCourt(
                    id: 'court-1',
                    venueId: 'venue-1',
                    sportId: 'sport-1',
                    name: 'คอร์ท A',
                  ),
                  venueName: 'สนามทดสอบ',
                  timezone: timezone,
                  initialDate: date,
                  loadAvailability: (_, from, to) async => CourtAvailability(
                    courtId: 'court-1',
                    hours: [
                      VenueOperatingHours(
                        dayOfWeek: from.weekday % 7,
                        openTime: '06:00',
                        closeTime: '23:00',
                      ),
                    ],
                  ),
                );
              },
              child: const Text('เปิดฟอร์มจอง'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เปิดฟอร์มจอง'));
    await tester.pumpAndSettle();
    expect(
      find.text(ThaiDateUtils.formatShortDateBE2Digit(date)),
      findsOneWidget,
    );
    for (final hour in ['18:00', '19:00', '21:00']) {
      await tester.tap(find.text(hour));
      await tester.pumpAndSettle();
    }
    expect(find.text('รวม 3 ชั่วโมง • 2 ช่วงเวลา'), findsOneWidget);
    expect(find.text('18:00–20:00'), findsOneWidget);
    expect(find.text('21:00–22:00'), findsOneWidget);
    await tester.ensureVisible(find.text('ถัดไป — อ่านเงื่อนไข'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ถัดไป — อ่านเงื่อนไข'));
    await tester.pumpAndSettle();

    expect(
      result!.first.start.toUtc(),
      VenueLocalTime.atWallTime(date, timezone, 18).toUtc(),
    );
    expect(result, hasLength(2));
    expect(
      result!.first.end.difference(result!.first.start),
      const Duration(hours: 2),
    );
    expect(
      result!.last.start.toUtc(),
      VenueLocalTime.atWallTime(date, timezone, 21).toUtc(),
    );
    expect(
      result!.last.end.difference(result!.last.start),
      const Duration(hours: 1),
    );
  });

  testWidgets('initial slot is summarized and remains editable', (
    tester,
  ) async {
    const timezone = 'Asia/Bangkok';
    final date = VenueLocalTime.addCalendarDays(
      VenueLocalTime.today(timezone),
      1,
    );
    await _openDialog(
      tester,
      initialSlotStart: VenueLocalTime.atWallTime(date, timezone, 18),
    );
    await tester.pumpAndSettle();

    expect(find.text('รวม 1 ชั่วโมง • 1 ช่วงเวลา'), findsOneWidget);
    expect(find.text('18:00–19:00'), findsOneWidget);
    await tester.tap(find.text('18:00'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่ได้เลือกเวลา'), findsOneWidget);
    await tester.tap(find.text('19:00'));
    await tester.pumpAndSettle();
    expect(find.text('รวม 1 ชั่วโมง • 1 ช่วงเวลา'), findsOneWidget);
    expect(find.text('19:00–20:00'), findsOneWidget);
  });

  testWidgets('deselect updates summary and disables empty confirmation', (
    tester,
  ) async {
    await _openDialog(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('18:00'));
    await tester.pumpAndSettle();
    expect(find.text('รวม 1 ชั่วโมง • 1 ช่วงเวลา'), findsOneWidget);
    await tester.tap(find.text('18:00'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่ได้เลือกเวลา'), findsOneWidget);
    expect(
      tester.widget<GlassActionButton>(find.byType(GlassActionButton)).onTap,
      isNull,
    );
  });

  testWidgets(
    'rescheduling rejects disjoint selections but accepts adjacent ones',
    (tester) async {
      await _openDialog(tester, allowDisjoint: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('18:00'));
      await tester.tap(find.text('20:00'));
      await tester.pumpAndSettle();
      expect(find.text('กรุณาเลือกเวลาต่อเนื่องกัน'), findsOneWidget);
      expect(
        tester.widget<GlassActionButton>(find.byType(GlassActionButton)).onTap,
        isNull,
      );
      await tester.tap(find.text('19:00'));
      await tester.pumpAndSettle();
      expect(find.text('18:00–21:00'), findsOneWidget);
      expect(
        tester.widget<GlassActionButton>(find.byType(GlassActionButton)).onTap,
        isNotNull,
      );
    },
  );

  testWidgets('availability errors can be retried and loading blocks submit', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<CourtAvailability>();
    await _openDialog(
      tester,
      loadAvailability: (_, from, to) {
        calls++;
        if (calls == 1) return pending.future;
        return Future.value(_availability(from));
      },
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester.widget<GlassActionButton>(find.byType(GlassActionButton)).onTap,
      isNull,
    );
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('โหลดตารางว่างไม่สำเร็จ'), findsOneWidget);
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('18:00'), findsOneWidget);
  });

  testWidgets('changing date reloads venue-local day and clears selection', (
    tester,
  ) async {
    final requests = <({DateTime from, DateTime to})>[];
    await _openDialog(
      tester,
      loadAvailability: (_, from, to) async {
        requests.add((from: from, to: to));
        return _availability(from);
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('18:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('เดือนถัดไป'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(requests.last.from.day, 1);
    expect(requests.last.from.hour, 0);
    expect(
      requests.last.to.difference(requests.last.from),
      const Duration(hours: 24),
    );
    expect(find.text('ยังไม่ได้เลือกเวลา'), findsOneWidget);
  });

  testWidgets('dismissal returns null without a selection', (tester) async {
    var returned = false;
    await _openDialog(
      tester,
      onResult: (result) {
        returned = true;
        expect(result, isNull);
      },
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
  });

  testWidgets('small phone scrolls without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openDialog(tester);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('18:00'));
    await tester.tap(find.text('18:00'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ถัดไป — อ่านเงื่อนไข'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('dateOfInstant uses the venue-local calendar date', () {
    expect(
      VenueLocalTime.dateOfInstant(
        DateTime.utc(2026, 9, 30, 18),
        'Asia/Bangkok',
      ),
      DateTime(2026, 10, 1),
    );
  });
}
