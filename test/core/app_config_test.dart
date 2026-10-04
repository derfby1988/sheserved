import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/config/app_config.dart';
import 'package:sheserved/features/video/models/video_models.dart';

const _expectedBackendApiUrl = String.fromEnvironment(
  'BACKEND_API_URL',
  defaultValue: 'http://192.168.0.101:8080',
);

void main() {
  group('backend endpoint configuration', () {
    test('all backend clients share the configured base URL', () {
      expect(AppConfig.backendApiUrl, _expectedBackendApiUrl);
      expect(AppConfig.localApiUrl, AppConfig.backendApiUrl);
      expect(AppConfig.websocketUrl, AppConfig.backendApiUrl);
    });

    test('normalizes stored local video URLs to the configured base URL', () {
      final video = Video(
        id: 'video-id',
        userId: 'user-id',
        title: 'Incident',
        createdAt: DateTime.utc(2026, 1, 1),
        thumbnailUrl: 'http://192.168.1.167:8080/temp/videos/thumbnail.webp',
      );

      expect(
        video.bestThumbnailUrl,
        '${AppConfig.localApiUrl}/temp/videos/thumbnail.webp',
      );
    });

    test('does not rewrite CDN thumbnail URLs', () {
      final video = Video(
        id: 'video-id',
        userId: 'user-id',
        title: 'Incident',
        createdAt: DateTime.utc(2026, 1, 1),
        thumbnailUrl: 'https://cdn.example.com/thumbnail.webp',
      );

      expect(video.bestThumbnailUrl, 'https://cdn.example.com/thumbnail.webp');
    });
  });
}
