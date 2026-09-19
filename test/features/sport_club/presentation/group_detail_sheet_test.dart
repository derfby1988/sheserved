import 'package:flutter_test/flutter_test.dart';
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
}
