import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/services/socket_auth_recovery_policy.dart';
import 'package:sheserved/services/socket_auth_socket_factory.dart';

String _tokenWithExpiry(DateTime expiry) {
  final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
  final payload = base64Url.encode(
    utf8.encode(jsonEncode({'exp': expiry.millisecondsSinceEpoch ~/ 1000})),
  );
  return '${header.replaceAll('=', '')}.${payload.replaceAll('=', '')}.signature';
}

void main() {
  group('SocketAuthRecoveryPolicy', () {
    final now = DateTime.utc(2026, 10, 5, 12);

    test('refreshes malformed or soon-to-expire tokens before connecting', () {
      final expiresSoon = _tokenWithExpiry(
        now.add(const Duration(seconds: 60)),
      );
      final expiresLater = _tokenWithExpiry(
        now.add(const Duration(minutes: 2)),
      );

      expect(
        SocketAuthRecoveryPolicy.needsPreemptiveRefresh(expiresSoon, now: now),
        isTrue,
      );
      expect(
        SocketAuthRecoveryPolicy.needsPreemptiveRefresh(expiresLater, now: now),
        isFalse,
      );
      expect(
        SocketAuthRecoveryPolicy.needsPreemptiveRefresh('not-a-jwt', now: now),
        isTrue,
      );
    });

    test('selects stop, refresh, rebuild, and reuse connection paths', () {
      final freshToken = _tokenWithExpiry(now.add(const Duration(minutes: 5)));
      final expiredToken = _tokenWithExpiry(
        now.subtract(const Duration(seconds: 1)),
      );

      SocketConnectionAction decide({
        String? token = 'unused',
        bool hasSocket = false,
        String? socketToken,
        String? socketUserId,
        String? userId = 'user-1',
      }) => SocketAuthRecoveryPolicy.connectionAction(
        backendAuthRequired: true,
        accessToken: token,
        hasSocket: hasSocket,
        socketAuthToken: socketToken,
        socketUserId: socketUserId,
        requestedUserId: userId,
        now: now,
      );

      expect(decide(token: null), SocketConnectionAction.stopWithError);
      expect(
        decide(token: expiredToken),
        SocketConnectionAction.refreshThenRebuild,
      );
      expect(decide(token: freshToken), SocketConnectionAction.reuse);
      expect(
        decide(
          token: freshToken,
          hasSocket: true,
          socketToken: 'old-token',
          socketUserId: 'user-1',
        ),
        SocketConnectionAction.rebuild,
      );
      expect(
        decide(
          token: freshToken,
          hasSocket: true,
          socketToken: freshToken,
          socketUserId: 'user-2',
        ),
        SocketConnectionAction.rebuild,
      );
    });

    test('stops after rejecting a token minted during recovery', () {
      expect(
        SocketAuthRecoveryPolicy.authFailureAction(
          code: 'token_expired',
          refreshedTokenRejected: true,
        ),
        SocketAuthFailureAction.stopWithError,
      );
      expect(
        SocketAuthRecoveryPolicy.authFailureAction(
          code: 'auth_backend_unavailable',
          refreshedTokenRejected: false,
        ),
        SocketAuthFailureAction.retryWithoutRefresh,
      );
      expect(
        SocketAuthRecoveryPolicy.authFailureAction(
          code: 'session_revoked',
          refreshedTokenRejected: false,
        ),
        SocketAuthFailureAction.logout,
      );
      expect(
        SocketAuthRecoveryPolicy.authFailureAction(
          code: 'token_expired',
          refreshedTokenRejected: false,
        ),
        SocketAuthFailureAction.refresh,
      );
    });

    test(
      'returns user-facing copy only for terminal authentication failures',
      () {
        expect(
          SocketAuthRecoveryPolicy.userFacingAuthMessage(
            'Session expired — please log in again',
          ),
          contains('เข้าสู่ระบบใหม่'),
        );
        expect(
          SocketAuthRecoveryPolicy.userFacingAuthMessage(
            'Realtime authentication recovery paused; log in again',
          ),
          contains('ติดต่อผู้ดูแล'),
        );
        expect(
          SocketAuthRecoveryPolicy.userFacingAuthMessage(
            'Realtime authentication temporarily unavailable; retry scheduled',
          ),
          isNull,
        );
      },
    );

    test(
      'caps recovery attempts until a successful connection or explicit reset',
      () {
        expect(SocketAuthRecoveryPolicy.canAttemptRecovery(0), isTrue);
        expect(SocketAuthRecoveryPolicy.canAttemptRecovery(2), isTrue);
        expect(SocketAuthRecoveryPolicy.canAttemptRecovery(3), isFalse);
      },
    );
  });

  test('creates a fresh Socket.IO socket with the new auth token', () {
    final first = SocketAuthSocketFactory.create(
      serverUrl: 'http://127.0.0.1:8080',
      userId: 'user-1',
      token: 'token-a',
      reconnectionAttempts: 1,
      autoConnect: false,
    );
    final second = SocketAuthSocketFactory.create(
      serverUrl: 'http://127.0.0.1:8080',
      userId: 'user-1',
      token: 'token-b',
      reconnectionAttempts: 1,
      autoConnect: false,
    );

    try {
      expect(identical(first, second), isFalse);
      expect(second.auth['token'], 'token-b');
    } finally {
      first.dispose();
      second.dispose();
    }
  });
}
