import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/video/services/emergency_incident_deep_link_service.dart';

void main() {
  group('EmergencyIncidentDeepLinkService Tests', () {
    setUp(() {
      EmergencyIncidentDeepLinkService.clearPendingDeepLink();
    });

    tearDown(() {
      EmergencyIncidentDeepLinkService.clearPendingDeepLink();
    });

    test('buildIncidentShareUrl creates proper web universal link', () {
      final urlWithoutPhoto =
          EmergencyIncidentDeepLinkService.buildIncidentShareUrl('incident-123');
      expect(
        urlWithoutPhoto,
        'https://sheserved.com/emergency/incident/incident-123?src=share',
      );

      final urlWithPhoto =
          EmergencyIncidentDeepLinkService.buildIncidentShareUrl(
        'incident-123',
        photoId: 'photo-456',
      );
      expect(
        urlWithPhoto,
        'https://sheserved.com/emergency/incident/incident-123?src=share&photo=photo-456',
      );
    });

    test('buildIncidentShareUrl encodes special characters', () {
      final url = EmergencyIncidentDeepLinkService.buildIncidentShareUrl(
        'inc id/1',
        photoId: 'p id/2',
      );
      expect(
        url,
        'https://sheserved.com/emergency/incident/inc%20id%2F1?src=share&photo=p%20id%2F2',
      );
    });

    test('buildIncidentCustomSchemeUrl creates proper custom scheme', () {
      final urlWithoutPhoto =
          EmergencyIncidentDeepLinkService.buildIncidentCustomSchemeUrl(
        'incident-123',
      );
      expect(
        urlWithoutPhoto,
        'sheserved://emergency/incident/incident-123',
      );

      final urlWithPhoto =
          EmergencyIncidentDeepLinkService.buildIncidentCustomSchemeUrl(
        'incident-123',
        photoId: 'photo-456',
      );
      expect(
        urlWithPhoto,
        'sheserved://emergency/incident/incident-123?photo=photo-456',
      );
    });

    test('parseDeepLink correctly parses custom scheme URLs', () {
      final data = EmergencyIncidentDeepLinkService.parseDeepLink(
        'sheserved://emergency/incident/inc-789',
      );
      expect(data, isNotNull);
      expect(data!.videoId, 'inc-789');
      expect(data.photoId, isNull);
      expect(data.src, isNull);

      final dataWithPhoto = EmergencyIncidentDeepLinkService.parseDeepLink(
        'sheserved://emergency/incident/inc-789?photo=p-999&src=share',
      );
      expect(dataWithPhoto, isNotNull);
      expect(dataWithPhoto!.videoId, 'inc-789');
      expect(dataWithPhoto.photoId, 'p-999');
      expect(dataWithPhoto.src, 'share');
    });

    test('parseDeepLink correctly parses web universal links', () {
      final data = EmergencyIncidentDeepLinkService.parseDeepLink(
        'https://sheserved.com/emergency/incident/inc-789?src=share',
      );
      expect(data, isNotNull);
      expect(data!.videoId, 'inc-789');
      expect(data.photoId, isNull);
      expect(data.src, 'share');

      final dataWithPhoto = EmergencyIncidentDeepLinkService.parseDeepLink(
        'https://sheserved.com/emergency/incident/inc-789?src=share&photo=p-888',
      );
      expect(dataWithPhoto, isNotNull);
      expect(dataWithPhoto!.videoId, 'inc-789');
      expect(dataWithPhoto.photoId, 'p-888');
      expect(dataWithPhoto.src, 'share');
    });

    test('parseDeepLink correctly parses relative route paths', () {
      final data = EmergencyIncidentDeepLinkService.parseDeepLink(
        '/emergency/incident/inc-456?photo=p-123',
      );
      expect(data, isNotNull);
      expect(data!.videoId, 'inc-456');
      expect(data.photoId, 'p-123');
    });

    test('parseDeepLink handles invalid, malformed, or irrelevant URLs safely', () {
      expect(EmergencyIncidentDeepLinkService.parseDeepLink(null), isNull);
      expect(EmergencyIncidentDeepLinkService.parseDeepLink(''), isNull);
      expect(EmergencyIncidentDeepLinkService.parseDeepLink('   '), isNull);
      expect(
        EmergencyIncidentDeepLinkService.parseDeepLink('https://sheserved.com/other/path'),
        isNull,
      );
      expect(
        EmergencyIncidentDeepLinkService.parseDeepLink(
          'https://sheserved.com/emergency/incident/',
        ),
        isNull,
      );
      expect(
        EmergencyIncidentDeepLinkService.parseDeepLink(
          'sheserved://sport-club/group/grp-1',
        ),
        isNull,
      );
    });

    test('pending deep link store, peek, consume, and clear lifecycle', () {
      const sample = EmergencyIncidentDeepLinkData(
        videoId: 'inc-sample',
        photoId: 'photo-sample',
        src: 'share',
      );

      expect(EmergencyIncidentDeepLinkService.peekPendingDeepLink(), isNull);

      EmergencyIncidentDeepLinkService.storePendingDeepLink(sample);
      expect(
        EmergencyIncidentDeepLinkService.peekPendingDeepLink(),
        equals(sample),
      );

      final consumed = EmergencyIncidentDeepLinkService.consumePendingDeepLink();
      expect(consumed, equals(sample));
      expect(EmergencyIncidentDeepLinkService.peekPendingDeepLink(), isNull);
      expect(EmergencyIncidentDeepLinkService.consumePendingDeepLink(), isNull);

      EmergencyIncidentDeepLinkService.storePendingDeepLink(sample);
      EmergencyIncidentDeepLinkService.clearPendingDeepLink();
      expect(EmergencyIncidentDeepLinkService.peekPendingDeepLink(), isNull);
    });

    test('EmergencyIncidentDeepLinkData equality, hashCode, and toString', () {
      const data1 = EmergencyIncidentDeepLinkData(
        videoId: 'v1',
        photoId: 'p1',
        src: 'share',
      );
      const data2 = EmergencyIncidentDeepLinkData(
        videoId: 'v1',
        photoId: 'p1',
        src: 'share',
      );
      const data3 = EmergencyIncidentDeepLinkData(
        videoId: 'v1',
        photoId: 'p2',
        src: 'share',
      );

      expect(data1, equals(data2));
      expect(data1.hashCode, equals(data2.hashCode));
      expect(data1, isNot(equals(data3)));
      expect(
        data1.toString(),
        'EmergencyIncidentDeepLinkData(videoId: v1, photoId: p1, src: share)',
      );
    });
  });
}
