import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/dialogs/group_session_history_dialog.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sheets/group_detail_sheet.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sheets/session_picker_sheet.dart';

void main() {
  group('group member swipe chat access', () {
    test('allows a group member to chat with every active member', () {
      expect(
        canOpenGroupChatFromMemberSwipe(canChat: true, isActiveMember: true),
        isTrue,
      );
    });

    test('rejects inactive targets and users without group chat access', () {
      expect(
        canOpenGroupChatFromMemberSwipe(canChat: true, isActiveMember: false),
        isFalse,
      );
      expect(
        canOpenGroupChatFromMemberSwipe(canChat: false, isActiveMember: true),
        isFalse,
      );
    });
  });

  group('session picker availability', () {
    test('collects confirmed and pending bookings for the current user', () {
      final statuses = currentUserSessionBookingStatuses(
        userId: 'user-1',
        members: [
          {
            'user_id': 'user-1',
            'confirmed_sessions': [
              {'id': 'session-1'},
            ],
          },
        ],
        pendingBookings: [
          {
            'user': {'id': 'user-1'},
            'session': {'id': 'session-2'},
          },
          {
            'user': {'id': 'user-2'},
            'session': {'id': 'session-3'},
          },
        ],
      );

      expect(statuses, {'session-1': 'confirmed', 'session-2': 'pending'});
    });

    test('does not offer booked, full, or ended sessions', () {
      final now = DateTime.utc(2025, 1, 1);
      final available = {
        'id': 'available',
        'ends_at': '2025-01-02T00:00:00Z',
        'capacity': 5,
        'confirmed_count': 2,
      };
      final full = {
        'id': 'full',
        'ends_at': '2025-01-02T00:00:00Z',
        'capacity': 2,
        'confirmed_count': 2,
      };
      final ended = {
        'id': 'ended',
        'ends_at': '2024-12-31T00:00:00Z',
        'capacity': 5,
        'confirmed_count': 0,
      };

      expect(isSessionAvailableForBooking(available, now: now), isTrue);
      expect(isSessionAvailableForBooking(full, now: now), isFalse);
      expect(isSessionAvailableForBooking(ended, now: now), isFalse);
      expect(
        isSessionAvailableForBooking(
          available,
          excludedSessionIds: {'available'},
          now: now,
        ),
        isFalse,
      );
    });

    test('explains why no additional session can be selected', () {
      final session = {
        'id': 'session-1',
        'ends_at': '2025-01-02T00:00:00Z',
        'capacity': 5,
        'confirmed_count': 1,
      };

      expect(
        sessionPickerUnavailableMessage(
          [session],
          excludedSessionIds: {'session-1'},
        ),
        'คุณเข้าร่วมทุกรอบนัดที่เปิดอยู่แล้ว',
      );
      expect(
        sessionPickerUnavailableMessage([
          {...session, 'confirmed_count': 5},
        ]),
        'ขณะนี้รอบนัดที่ยังไม่ได้เข้าร่วมเต็มแล้ว',
      );
    });
  });

  group('group session history', () {
    test('classifies sessions by end time without hiding active sessions', () {
      final now = DateTime.utc(2025, 1, 2);
      expect(
        isSportClubSessionEnded({'ends_at': '2025-01-01T23:59:00Z'}, now: now),
        isTrue,
      );
      expect(
        isSportClubSessionEnded({'ends_at': '2025-01-02T23:59:00Z'}, now: now),
        isFalse,
      );
      expect(
        isSportClubSessionEnded({'ends_at': 'not-a-date'}, now: now),
        isFalse,
      );
    });

    testWidgets('opens the ended-session history dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => GroupSessionHistoryDialog.show(
                context,
                groupName: 'ก๊วนทดสอบ',
                groupOwnerId: 'owner-1',
                sessions: [
                  {
                    'id': 'session-1',
                    'starts_at': '2025-01-01T10:00:00Z',
                    'ends_at': '2025-01-01T11:00:00Z',
                    'capacity': 5,
                    'confirmed_count': 1,
                  },
                ],
                confirmedMembersBySession: const {},
              ),
              child: const Text('เปิดประวัติ'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('เปิดประวัติ'));
      await tester.pumpAndSettle();

      expect(find.text('ประวัติรอบนัดของก๊วน'), findsOneWidget);
      expect(find.text('ก๊วนทดสอบ · 1 รอบที่สิ้นสุดแล้ว'), findsOneWidget);
      expect(find.textContaining('รอบที่ 1'), findsOneWidget);
    });
  });
}
