import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';
import 'package:sheserved/shared/widgets/thai_buddhist_date_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/domain/venue_local_time.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_booking_dialog.dart';

CourtAvailability _availability(
  DateTime from, {
  List<({DateTime startsAt, DateTime endsAt})> blocked = const [],
}) => CourtAvailability(
  courtId: 'court-1',
  blocked: blocked,
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
  Future<VenueCourtPriceQuote> Function(
    VenueCourt court,
    DateTime startsAt,
    DateTime endsAt,
  )?
  quotePrice,
  bool canManageAvailability = false,
  CourtAvailabilityMutation? manageAvailability,
  void Function(List<CourtBookingSelection>? result)? onResult,
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
                canManageAvailability: canManageAvailability,
                manageAvailability: manageAvailability,
                loadAvailability:
                    loadAvailability ??
                    (_, from, to) async => _availability(from),
                quotePrice:
                    quotePrice ??
                    (_, _, _) async =>
                        const VenueCourtPriceQuote(priceScheduleVersion: 1),
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
    List<CourtBookingSelection>? result;

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
                  quotePrice: (_, _, _) async =>
                      const VenueCourtPriceQuote(priceScheduleVersion: 1),
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
      find.text(ThaiDateUtils.formatWeekdayShortDateBE2Digit(date)),
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

  testWidgets('shows and returns the server price quote version', (
    tester,
  ) async {
    List<CourtBookingSelection>? result;
    await _openDialog(
      tester,
      quotePrice: (_, _, _) async => const VenueCourtPriceQuote(
        totalAmount: 90,
        priceAmount: 90,
        pricingUnit: 'hour',
        priceScheduleVersion: 3,
        hasTimePricing: true,
      ),
      onResult: (selection) => result = selection,
    );

    await tester.tap(find.text('18:00'));
    await tester.pumpAndSettle();
    expect(find.text('ราคารวมประมาณ 90 บาท'), findsOneWidget);
    await tester.ensureVisible(find.text('ถัดไป — อ่านเงื่อนไข'));
    await tester.tap(find.text('ถัดไป — อ่านเงื่อนไข'));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    expect(result!.single.priceQuote.priceScheduleVersion, 3);
    expect(result!.single.priceQuote.totalAmount, 90);
  });

  testWidgets('verified venue managers can suspend multiple slot ranges', (
    tester,
  ) async {
    var quoteCalls = 0;
    var loadCalls = 0;
    final changes =
        <
          ({
            String courtId,
            bool suspend,
            List<({DateTime start, DateTime end})> ranges,
          })
        >[];
    await _openDialog(
      tester,
      canManageAvailability: true,
      manageAvailability: (courtId, suspend, ranges) async {
        changes.add((courtId: courtId, suspend: suspend, ranges: ranges));
      },
      loadAvailability: (_, from, to) async {
        loadCalls++;
        return _availability(from);
      },
      quotePrice: (_, _, _) async {
        quoteCalls++;
        throw StateError('availability management must not quote');
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('จัดการเวลาจอง — สนาม คอร์ท A'), findsOneWidget);
    expect(find.text('ระงับ / ยกเลิกระงับ'), findsOneWidget);
    expect(find.text('ถัดไป — อ่านเงื่อนไข'), findsNothing);
    expect(quoteCalls, 0);

    for (final time in ['18:00', '19:00', '21:00']) {
      await tester.ensureVisible(find.text(time));
      await tester.tap(find.text(time));
      await tester.pumpAndSettle();
    }
    expect(find.text('ระงับ 2 ช่วง'), findsOneWidget);
    await tester.ensureVisible(find.text('ระงับ 2 ช่วง'));
    await tester.tap(find.text('ระงับ 2 ช่วง'));
    await tester.pumpAndSettle();

    expect(changes, hasLength(1));
    expect(changes.single.courtId, 'court-1');
    expect(changes.single.suspend, isTrue);
    expect(
      changes.single.ranges.map((range) => (range.start.hour, range.end.hour)),
      [(18, 20), (21, 22)],
    );
    expect(loadCalls, 2);
    expect(find.text('ระงับเวลาแล้ว 2 ช่วง'), findsOneWidget);
  });

  testWidgets('opening a suspended slot preselects it for unsuspension', (
    tester,
  ) async {
    const timezone = 'Asia/Bangkok';
    final date = VenueLocalTime.addCalendarDays(
      VenueLocalTime.today(timezone),
      1,
    );
    final start = VenueLocalTime.atWallTime(date, timezone, 18);
    var changedAction = true;
    List<({DateTime start, DateTime end})>? changedRanges;

    await _openDialog(
      tester,
      initialSlotStart: start,
      canManageAvailability: true,
      manageAvailability: (courtId, suspend, ranges) async {
        changedAction = suspend;
        changedRanges = ranges;
      },
      loadAvailability: (_, from, to) async => _availability(
        from,
        blocked: [
          (startsAt: start, endsAt: start.add(const Duration(hours: 1))),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ยกเลิกระงับ 1 ช่วง'), findsOneWidget);
    await tester.ensureVisible(find.text('ยกเลิกระงับ 1 ช่วง'));
    await tester.tap(find.text('ยกเลิกระงับ 1 ช่วง'));
    await tester.pumpAndSettle();

    expect(changedAction, isFalse);
    expect(changedRanges, hasLength(1));
    expect(changedRanges!.single.start.isAtSameMomentAs(start), isTrue);
    expect(
      changedRanges!.single.end.isAtSameMomentAs(
        start.add(const Duration(hours: 1)),
      ),
      isTrue,
    );
  });

  testWidgets('managers can only unsuspend slots already suspended', (
    tester,
  ) async {
    var suspendAction = true;
    List<({DateTime start, DateTime end})>? changedRanges;
    await _openDialog(
      tester,
      canManageAvailability: true,
      manageAvailability: (courtId, suspend, ranges) async {
        suspendAction = suspend;
        changedRanges = ranges;
      },
      loadAvailability: (_, from, to) async => _availability(
        from,
        blocked: [
          (
            startsAt: VenueLocalTime.atWallTime(from, 'Asia/Bangkok', 18),
            endsAt: VenueLocalTime.atWallTime(from, 'Asia/Bangkok', 20),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('18:00'));
    await tester.tap(find.text('18:00'));
    await tester.pumpAndSettle();
    expect(find.text('ยกเลิกระงับ 1 ช่วง'), findsOneWidget);

    await tester.ensureVisible(find.text('20:00'));
    await tester.tap(find.text('20:00'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('เลือกได้ครั้งละอย่าง: ระงับเวลาว่าง'),
      findsOneWidget,
    );
    expect(find.text('ยกเลิกระงับ 1 ช่วง'), findsOneWidget);

    await tester.ensureVisible(find.text('ยกเลิกระงับ 1 ช่วง'));
    await tester.tap(find.text('ยกเลิกระงับ 1 ช่วง'));
    await tester.pumpAndSettle();

    expect(suspendAction, isFalse);
    expect(changedRanges, hasLength(1));
    expect(changedRanges!.single.start.hour, 18);
    expect(changedRanges!.single.end.hour, 19);
    expect(find.text('ยกเลิกระงับเวลาแล้ว 1 ช่วง'), findsOneWidget);
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
