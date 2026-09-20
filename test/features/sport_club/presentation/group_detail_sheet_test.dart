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
      expect(find.textContaining('รอบ ·'), findsOneWidget);
    });

    testWidgets('shows five cards first, then loads more on scroll', (
      tester,
    ) async {
      final sessions = List.generate(
        12,
        (i) => {
          'id': 'session-$i',
          'starts_at': '2025-01-01T10:00:00Z',
          'ends_at': '2025-01-01T11:00:00Z',
          'capacity': 5,
          'confirmed_count': 1,
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => GroupSessionHistoryDialog.show(
                context,
                groupName: 'ก๊วนทดสอบ',
                groupOwnerId: 'owner-1',
                sessions: sessions,
                confirmedMembersBySession: const {},
              ),
              child: const Text('เปิดประวัติ'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('เปิดประวัติ'));
      await tester.pumpAndSettle();

      // ListView.separated interleaves separators, so the delegate's
      // childCount is 2 * items - 1; invert it to get the visible sessions.
      int visibleSessions() {
        final childCount =
            (tester.widget<ListView>(find.byType(ListView)).childrenDelegate
                    as SliverChildBuilderDelegate)
                .childCount ??
            0;
        return (childCount + 1) ~/ 2;
      }

      // Initial page renders only the first five cards.
      expect(visibleSessions(), 5);
      expect(find.text('เลื่อนลงเพื่อดูรอบก่อนหน้า'), findsOneWidget);
      expect(find.byType(Scrollbar), findsOneWidget);

      // Scroll to the bottom to load the next page of five.
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(visibleSessions(), 10);

      // One more scroll reveals the remaining cards (12 total).
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(visibleSessions(), 12);
      expect(find.text('เลื่อนลงเพื่อดูรอบก่อนหน้า'), findsNothing);
    });

    testWidgets('sizes the dialog to its cards without a bottom close button', (
      tester,
    ) async {
      final sessions = [
        {
          'id': 'session-1',
          'starts_at': '2025-01-01T10:00:00Z',
          'ends_at': '2025-01-01T11:00:00Z',
          'capacity': 5,
          'confirmed_count': 1,
        },
        {
          'id': 'session-2',
          'starts_at': '2025-01-02T10:00:00Z',
          'ends_at': '2025-01-02T11:00:00Z',
          'capacity': 5,
          'confirmed_count': 1,
        },
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => GroupSessionHistoryDialog.show(
                context,
                groupName: 'ก๊วนทดสอบ',
                groupOwnerId: 'owner-1',
                sessions: sessions,
                confirmedMembersBySession: const {},
              ),
              child: const Text('เปิดประวัติ'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('เปิดประวัติ'));
      await tester.pumpAndSettle();

      // The bottom "ปิด" button is gone (only the header close icon remains).
      expect(find.text('ปิด'), findsNothing);

      // The dialog hugs its content instead of stretching to the max height.
      // (The Dialog widget itself fills the screen; its Material is the box.)
      final dialogBox = tester.getSize(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(dialogBox.height, lessThan(600 * 0.82));
    });

    testWidgets('sorts ended sessions with the most recent on top', (
      tester,
    ) async {
      Map<String, dynamic> session(String id, String startsAt) => {
        'id': id,
        'starts_at': startsAt,
        'ends_at': startsAt,
        'capacity': 5,
        'confirmed_count': 1,
      };
      // Deliberately out of order: oldest first.
      final sessions = [
        session('s1', '2025-01-01T10:00:00Z'),
        session('s3', '2025-01-03T10:00:00Z'),
        session('s2', '2025-01-02T10:00:00Z'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => GroupSessionHistoryDialog.show(
                context,
                groupName: 'ก๊วนทดสอบ',
                groupOwnerId: 'owner-1',
                sessions: sessions,
                confirmedMembersBySession: const {},
              ),
              child: const Text('เปิดประวัติ'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('เปิดประวัติ'));
      await tester.pumpAndSettle();

      final titles = tester
          .widgetList<Text>(find.textContaining('รอบ ·'))
          .map((t) => t.data ?? '')
          .toList();
      expect(titles, hasLength(3));
      expect(titles[0], contains('รอบ · 3 ม.ค.'));
      expect(titles[1], contains('รอบ · 2 ม.ค.'));
      expect(titles[2], contains('รอบ · 1 ม.ค.'));
    });
  });
}
