import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/services/sport_club_deep_link_service.dart';

void main() {
  group('SportClubDeepLinkService Tests', () {
    test('buildGroupInviteUrl creates correct HTTPS URL for group only', () {
      final url = SportClubDeepLinkService.buildGroupInviteUrl('g123');
      expect(url, equals('https://sheserved.com/sport-club/group/g123'));
    });

    test('buildGroupInviteUrl creates correct HTTPS URL with session_id', () {
      final url = SportClubDeepLinkService.buildGroupInviteUrl('g123', sessionId: 's456');
      expect(url, equals('https://sheserved.com/sport-club/group/g123?session_id=s456'));
    });

    test('buildGroupCustomSchemeUrl creates correct custom scheme URL', () {
      final url = SportClubDeepLinkService.buildGroupCustomSchemeUrl('g123', sessionId: 's456');
      expect(url, equals('sheserved://sport-club/group/g123?session_id=s456'));
    });

    test('parseDeepLink parses web link with group and session', () {
      final data = SportClubDeepLinkService.parseDeepLink(
        'https://sheserved.com/sport-club/group/g-uuid-123?session_id=s-uuid-456',
      );
      expect(data, isNotNull);
      expect(data!.groupId, equals('g-uuid-123'));
      expect(data.sessionId, equals('s-uuid-456'));
    });

    test('parseDeepLink parses custom scheme link', () {
      final data = SportClubDeepLinkService.parseDeepLink(
        'sheserved://sport-club/group/g-uuid-999?session_id=s-uuid-888',
      );
      expect(data, isNotNull);
      expect(data!.groupId, equals('g-uuid-999'));
      expect(data.sessionId, equals('s-uuid-888'));
    });

    test('parseDeepLink handles path without session_id', () {
      final data = SportClubDeepLinkService.parseDeepLink('/sport-club/group/group-777');
      expect(data, isNotNull);
      expect(data!.groupId, equals('group-777'));
      expect(data.sessionId, isNull);
    });

    test('parseDeepLink returns null for invalid URLs', () {
      expect(SportClubDeepLinkService.parseDeepLink(null), isNull);
      expect(SportClubDeepLinkService.parseDeepLink(''), isNull);
      expect(SportClubDeepLinkService.parseDeepLink('https://sheserved.com/other-page'), isNull);
    });

    test('storePendingDeepLink and consumePendingDeepLink lifecycle', () {
      const sampleData = GroupDetailDeepLinkData(groupId: 'g-test', sessionId: 's-test');
      SportClubDeepLinkService.storePendingDeepLink(sampleData);
      expect(SportClubDeepLinkService.peekPendingDeepLink(), equals(sampleData));

      final consumed = SportClubDeepLinkService.consumePendingDeepLink();
      expect(consumed, equals(sampleData));
      expect(SportClubDeepLinkService.peekPendingDeepLink(), isNull);
    });
  });
}
