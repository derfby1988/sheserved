import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SheservedApp());

    // Verify that the app loads with the home page
    expect(find.text('SHESERVED'), findsOneWidget);
    expect(find.text('ช่องทางธรรมชาติ'), findsOneWidget);
  });
}
