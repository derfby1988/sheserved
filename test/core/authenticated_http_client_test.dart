import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/core/network/authenticated_http_client.dart';

void main() {
  group('TokenRefreshResult', () {
    test('classifies successful refresh responses', () {
      expect(
        TokenRefreshResult.fromHttpStatus(200),
        TokenRefreshResult.refreshed,
      );
    });

    test('treats definitive auth rejection as rejected', () {
      for (final status in [400, 401, 403]) {
        expect(
          TokenRefreshResult.fromHttpStatus(status),
          TokenRefreshResult.rejected,
        );
      }
    });

    test('preserves tokens for transient or unexpected errors', () {
      for (final status in [201, 204, 408, 429, 500, 503]) {
        expect(
          TokenRefreshResult.fromHttpStatus(status),
          TokenRefreshResult.unavailable,
        );
      }
    });
  });
}
