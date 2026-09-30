import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_repository.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/admin_platform_venue_terms_panel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeBookCourtRepository extends BookCourtRepository {
  _FakeBookCourtRepository(this.current)
    : super(
        SupabaseClient(
          'http://localhost:54321',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  PlatformVenueTerms current;
  String? savedText;
  int? savedCutoff;

  @override
  Future<PlatformVenueTerms> getPlatformVenueTerms(String adminId) async =>
      current;

  @override
  Future<PlatformVenueTerms> setPlatformVenueTerms({
    required String adminId,
    required String termsText,
    required int cancellationCutoffMinutes,
  }) async {
    savedText = termsText;
    savedCutoff = cancellationCutoffMinutes;
    current = PlatformVenueTerms(
      version: current.version + 1,
      termsText: termsText,
      cancellationCutoffMinutes: cancellationCutoffMinutes,
      isConfigured: true,
    );
    return current;
  }
}

void main() {
  testWidgets('saves platform terms as a new version after confirmation', (
    tester,
  ) async {
    final repo = _FakeBookCourtRepository(
      const PlatformVenueTerms(
        version: 0,
        termsText: 'เงื่อนไขการใช้สนามมาตรฐานของแพลตฟอร์ม',
        cancellationCutoffMinutes: 60,
        isConfigured: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminPlatformVenueTermsPanel(repo: repo, adminId: 'admin-id'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<FilledButton>(
        find.byKey(const ValueKey('platform-venue-terms-save')),
      ).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextField>(
        find.byKey(const ValueKey('platform-venue-terms-text')),
      ).controller!.text,
      isEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('platform-venue-terms-text')),
      'ยกเลิกล่วงหน้าได้ตามเงื่อนไขของสนาม',
    );
    await tester.enterText(
      find.byKey(const ValueKey('platform-venue-terms-cutoff')),
      '90',
    );
    await tester.tap(find.byKey(const ValueKey('platform-venue-terms-save')));
    await tester.pumpAndSettle();

    expect(find.text('ยืนยันการเปลี่ยนเงื่อนไขมาตรฐานสนาม'), findsOneWidget);
    await tester.tap(find.text('ยืนยันและบันทึก'));
    await tester.pumpAndSettle();

    expect(repo.savedText, 'ยกเลิกล่วงหน้าได้ตามเงื่อนไขของสนาม');
    expect(repo.savedCutoff, 90);
    expect(repo.current.version, 1);
    expect(repo.current.isConfigured, isTrue);
  });

  testWidgets('disables save for an invalid cancellation cutoff', (
    tester,
  ) async {
    final repo = _FakeBookCourtRepository(
      const PlatformVenueTerms(
        version: 1,
        termsText: 'เงื่อนไขปัจจุบัน',
        cancellationCutoffMinutes: 60,
        isConfigured: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminPlatformVenueTermsPanel(repo: repo, adminId: 'admin-id'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('platform-venue-terms-cutoff')),
      '-1',
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('platform-venue-terms-save')),
          )
          .onPressed,
      isNull,
    );
  });
}
