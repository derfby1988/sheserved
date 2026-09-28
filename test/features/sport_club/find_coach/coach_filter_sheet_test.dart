import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/find_coach/domain/find_coach_filter.dart';
import 'package:sheserved/features/sport_club/find_coach/presentation/widgets/coach_filter_sheet.dart';
import 'package:sheserved/shared/widgets/thai_address_picker/thai_address_repository.dart';

class _FakeAddressRepository implements ThaiAddressRepository {
  @override
  Future<List<String>> getAllProvinces() async =>
      const ['กรุงเทพมหานคร', 'ขอนแก่น'];

  @override
  Future<List<String>> getDistrictsByProvince(String province) async =>
      switch (province) {
        'ขอนแก่น' => const ['เมืองขอนแก่น'],
        'กรุงเทพมหานคร' => const ['ดินแดง', 'พระนคร'],
        _ => const <String>[],
      };

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError();
}

void main() {
  testWidgets('edits the shared coach query in the filter sheet', (
    tester,
  ) async {
    const currentFilter = FindCoachFilter(skillLevel: 'beginner');
    CoachFilterSheetResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await CoachFilterSheet.show(
                    context,
                    current: currentFilter,
                    currentQuery: 'Old coach',
                    addressRepository: _FakeAddressRepository(),
                  );
                },
                child: const Text('เปิดตัวกรอง'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เปิดตัวกรอง'));
    await tester.pumpAndSettle();

    final queryField = find.byKey(const ValueKey('coach_filter_search_query'));
    expect(tester.widget<TextField>(queryField).controller?.text, 'Old coach');

    await tester.enterText(queryField, '  New coach  ');
    await tester.ensureVisible(find.text('ใช้ตัวกรอง'));
    await tester.tap(find.text('ใช้ตัวกรอง'));
    await tester.pumpAndSettle();

    expect(result?.query, 'New coach');
    expect(result?.filter.skillLevel, 'beginner');
    expect(result?.province, isNull);
    expect(result?.district, isNull);
  });

  testWidgets('keeps the shared province and district when applied', (
    tester,
  ) async {
    CoachFilterSheetResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await CoachFilterSheet.show(
                    context,
                    current: const FindCoachFilter(),
                    currentQuery: '',
                    currentProvince: 'ขอนแก่น',
                    currentDistrict: 'เมืองขอนแก่น',
                    addressRepository: _FakeAddressRepository(),
                  );
                },
                child: const Text('เปิดตัวกรอง'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เปิดตัวกรอง'));
    await tester.pumpAndSettle();

    expect(find.text('ขอนแก่น'), findsOneWidget);
    expect(find.text('เมืองขอนแก่น'), findsOneWidget);

    await tester.ensureVisible(find.text('ใช้ตัวกรอง'));
    await tester.tap(find.text('ใช้ตัวกรอง'));
    await tester.pumpAndSettle();

    expect(result?.province, 'ขอนแก่น');
    expect(result?.district, 'เมืองขอนแก่น');
  });

  testWidgets('selecting a province loads its districts', (tester) async {
    CoachFilterSheetResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await CoachFilterSheet.show(
                    context,
                    current: const FindCoachFilter(),
                    currentQuery: '',
                    addressRepository: _FakeAddressRepository(),
                  );
                },
                child: const Text('เปิดตัวกรอง'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เปิดตัวกรอง'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('กรุงเทพมหานคร').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ดินแดง').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('ใช้ตัวกรอง'));
    await tester.tap(find.text('ใช้ตัวกรอง'));
    await tester.pumpAndSettle();

    expect(result?.province, 'กรุงเทพมหานคร');
    expect(result?.district, 'ดินแดง');
  });

  testWidgets('cancel dismisses without applying changes', (tester) async {
    CoachFilterSheetResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await CoachFilterSheet.show(
                    context,
                    current: const FindCoachFilter(),
                    currentQuery: 'Current query',
                    addressRepository: _FakeAddressRepository(),
                  );
                },
                child: const Text('เปิดตัวกรอง'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เปิดตัวกรอง'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ยกเลิก'));
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();

    expect(find.text('ตัวกรองโค้ช'), findsNothing);
    expect(result, isNull);
  });
}
