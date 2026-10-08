import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_repository.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_owner_evidence_queue.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeBookCourtRepository extends BookCourtRepository {
  _FakeBookCourtRepository(this.queue)
    : super(
        SupabaseClient(
          'https://example.com',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  OwnerEvidenceQueue queue;
  String? decision;
  String? decisionReason;
  String? decisionReasonCode;
  String? decisionRequirementKey;

  @override
  Future<OwnerEvidenceQueue> listEvidenceQueue(
    String userId,
    String venueId, {
    String filter = 'all',
    int limit = 50,
    OwnerQueueCursor? cursor,
  }) async => queue;

  @override
  Future<String> decideBookingGroup({
    required String userId,
    required String groupId,
    required String decision,
    String? reason,
    String? requirementKey,
    String? reasonCode,
  }) async {
    this.decision = decision;
    decisionReason = reason;
    decisionReasonCode = reasonCode;
    decisionRequirementKey = requirementKey;
    queue = const OwnerEvidenceQueue();
    return 'evidence_rejected';
  }
}

class _OwnerQueueHost extends StatefulWidget {
  final _FakeBookCourtRepository repo;

  const _OwnerQueueHost({required this.repo});

  @override
  State<_OwnerQueueHost> createState() => _OwnerQueueHostState();
}

class _OwnerQueueHostState extends State<_OwnerQueueHost> {
  bool _reloading = false;

  Future<void> _reloadParent() async {
    setState(() => _reloading = true);
    await Future<void>.delayed(Duration.zero);
    if (mounted) setState(() => _reloading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _reloading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                CourtOwnerEvidenceQueue(
                  repo: widget.repo,
                  userId: 'owner-1',
                  venue: const VenueSummary(id: 'venue-1', name: 'สนามทดสอบ'),
                  onChanged: _reloadParent,
                ),
              ],
            ),
    );
  }
}

OwnerEvidenceQueue _queueWithPendingSlip() => OwnerEvidenceQueue(
  groups: [
    OwnerQueueGroup(
      id: 'group-1',
      venueId: 'venue-1',
      venueName: 'สนามทดสอบ',
      timezone: 'Asia/Bangkok',
      status: BookingGroupStatus.awaitingEvidence,
      stage: 'payment',
      approvalMode: BookingApprovalMode.ownerApproval,
      totalAmount: 1,
      evidence: const [
        GroupEvidenceItem(
          id: 'evidence-1',
          requirementKey: 'req_1',
          kind: 'payment_slip',
          verificationStatus: GroupEvidenceVerification.pending,
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets('rejecting evidence with a reason refreshes the owner queue', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repo = _FakeBookCourtRepository(_queueWithPendingSlip());

    await tester.pumpWidget(MaterialApp(home: _OwnerQueueHost(repo: repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ปฏิเสธ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('อื่น ๆ (ระบุเพิ่มเติม)').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ทดสอบระบบ');
    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.decision, 'reject');
    expect(repo.decisionReason, 'ทดสอบระบบ');
    expect(repo.decisionReasonCode, 'other');
    expect(repo.decisionRequirementKey, 'req_1');
  });
}
