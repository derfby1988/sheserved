import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/domain/book_court_filter.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic_button.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/book_court_filter_sheet.dart';
import 'package:sheserved/shared/widgets/thai_address_picker/thai_address_repository.dart';

class _FakeAddressRepository implements ThaiAddressRepository {
  @override
  Future<List<String>> getAllProvinces() async => const [
    'กรุงเทพมหานคร',
    'ขอนแก่น',
  ];

  @override
  Future<List<String>> getDistrictsByProvince(String province) async =>
      switch (province) {
        'ขอนแก่น' => const ['เมืองขอนแก่น'],
        'กรุงเทพมหานคร' => const ['ดินแดง', 'พระนคร'],
        _ => const <String>[],
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('edits the shared venue query in the filter sheet', (
    tester,
  ) async {
    final currentFilter = BookCourtFilter(
      date: DateTime(2026, 10, 3),
      startTime: const TimeOfDay(hour: 18, minute: 0),
      duration: const Duration(hours: 1),
      minPrice: 100,
    );
    BookCourtFilterSheetResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await BookCourtFilterSheet.show(
                    context,
                    current: currentFilter,
                    currentQuery: 'Old court',
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

    final queryField = find.byKey(const ValueKey('book_court_search_query'));
    expect(tester.widget<TextField>(queryField).controller?.text, 'Old court');

    await tester.enterText(queryField, '  New court  ');
    await tester.ensureVisible(find.text('ใช้ตัวกรอง'));
    await tester.tap(find.text('ใช้ตัวกรอง'));
    await tester.pumpAndSettle();

    expect(result?.query, 'New court');
    expect(result?.filter.minPrice, 100.0);
    expect(result?.province, isNull);
    expect(result?.district, isNull);
  });

  testWidgets('keeps the current province and district when applied', (
    tester,
  ) async {
    BookCourtFilterSheetResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await BookCourtFilterSheet.show(
                    context,
                    current: const BookCourtFilter(),
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
    BookCourtFilterSheetResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await BookCourtFilterSheet.show(
                    context,
                    current: const BookCourtFilter(),
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

  testWidgets('close button dismisses without applying changes', (
    tester,
  ) async {
    BookCourtFilterSheetResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await BookCourtFilterSheet.show(
                    context,
                    current: const BookCourtFilter(),
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
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();

    expect(find.text('ตัวกรองสถานที่'), findsNothing);
    expect(result, isNull);
  });

  testWidgets('requires a selected slot before applying a price filter', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => BookCourtFilterSheet.show(
                  context,
                  current: const BookCourtFilter(minPrice: 100),
                  currentQuery: '',
                  addressRepository: _FakeAddressRepository(),
                ),
                child: const Text('เปิดตัวกรอง'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เปิดตัวกรอง'));
    await tester.pumpAndSettle();
    expect(find.text('ตัวกรองสถานที่'), findsOneWidget);
    final applyButton = tester.widget<NeumorphicVerifyButton>(
      find.byType(NeumorphicVerifyButton),
    );
    expect(applyButton.isEnabled, isFalse);
    expect(applyButton.onPressed, isNull);
  });
}
