import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/application/sport_club_intent.dart';

void main() {
  final groups = <Map<String, dynamic>>[
    {'id': 'g1', 'created_by': 'owner-1', 'requires_owner_approval': true},
    {'id': 'g2', 'created_by': 'owner-2', 'requires_owner_approval': false},
  ];

  group('resolveSportClubIntent', () {
    test('ignores missing or malformed arguments', () {
      expect(resolveSportClubIntent(null, groups, 'u').recognized, isFalse);
      expect(resolveSportClubIntent('x', groups, 'u').recognized, isFalse);
      expect(resolveSportClubIntent({}, groups, 'u').recognized, isFalse);
      expect(
        resolveSportClubIntent(
          {'intent': 'join_group'},
          groups,
          'u',
        ).recognized,
        isFalse,
      );
      expect(
        resolveSportClubIntent({'groupId': 'g1'}, groups, 'u').recognized,
        isFalse,
      );
      expect(
        resolveSportClubIntent(
          {'intent': 'bogus', 'groupId': 'g1'},
          groups,
          'u',
        ).recognized,
        isFalse,
      );
    });

    test('recognizes join_group and resolves the group', () {
      final r = resolveSportClubIntent(
        {'intent': 'join_group', 'groupId': 'g2'},
        groups,
        'u1',
      );
      expect(r.recognized, isTrue);
      expect(r.kind, 'join_group');
      expect(r.groupId, 'g2');
      expect(r.group?['id'], 'g2');
      expect(r.requiresOwnerApproval, isFalse);
    });

    test('recognizes review_pending', () {
      final r = resolveSportClubIntent(
        {'intent': 'review_pending', 'groupId': 'g1'},
        groups,
        'u1',
      );
      expect(r.recognized, isTrue);
      expect(r.kind, 'review_pending');
      expect(r.group?['id'], 'g1');
    });

    test('recognizes open_chat and resolves the group', () {
      final r = resolveSportClubIntent(
        {
          'intent': 'open_chat',
          'groupId': 'g2',
          'chatRoomId': 'legacy-room-id',
        },
        groups,
        'u1',
      );
      expect(r.recognized, isTrue);
      expect(r.kind, 'open_chat');
      expect(r.groupId, 'g2');
      expect(r.chatRoomId, 'legacy-room-id');
      expect(r.group?['id'], 'g2');
    });

    test('recognized even when the group is absent from the feed', () {
      final r = resolveSportClubIntent(
        {'intent': 'join_group', 'groupId': 'missing'},
        groups,
        'u1',
      );
      expect(r.recognized, isTrue);
      expect(r.group, isNull);
    });

    test('requiresOwnerApproval true for non-owner on approval groups', () {
      final r = resolveSportClubIntent(
        {'intent': 'join_group', 'groupId': 'g1'},
        groups,
        'u1',
      );
      expect(r.requiresOwnerApproval, isTrue);
    });

    test('requiresOwnerApproval false for the group owner', () {
      final r = resolveSportClubIntent(
        {'intent': 'join_group', 'groupId': 'g1'},
        groups,
        'owner-1',
      );
      expect(r.requiresOwnerApproval, isFalse);
    });
  });
}
