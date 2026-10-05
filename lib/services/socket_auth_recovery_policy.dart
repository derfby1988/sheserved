import 'dart:convert';

enum SocketConnectionAction {
  stopWithError,
  refreshThenRebuild,
  rebuild,
  reuse,
}

enum SocketAuthFailureAction {
  refresh,
  retryWithoutRefresh,
  logout,
  stopWithError,
}

class SocketAuthRecoveryPolicy {
  static const refreshWindow = Duration(seconds: 60);

  static DateTime? accessTokenExpiresAt(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map<String, dynamic> || payload['exp'] is! num) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(
        (payload['exp'] as num).toInt() * 1000,
        isUtc: true,
      );
    } catch (_) {
      return null;
    }
  }

  static bool needsPreemptiveRefresh(String? token, {DateTime? now}) {
    final expiresAt = accessTokenExpiresAt(token);
    final currentTime = (now ?? DateTime.now()).toUtc();
    return expiresAt == null ||
        !expiresAt.isAfter(currentTime.add(refreshWindow));
  }

  static SocketConnectionAction connectionAction({
    required bool backendAuthRequired,
    required String? accessToken,
    required bool hasSocket,
    required String? socketAuthToken,
    required String? socketUserId,
    required String? requestedUserId,
    DateTime? now,
  }) {
    if (backendAuthRequired &&
        (accessToken == null || accessToken.trim().isEmpty)) {
      return SocketConnectionAction.stopWithError;
    }
    if (backendAuthRequired && needsPreemptiveRefresh(accessToken, now: now)) {
      return SocketConnectionAction.refreshThenRebuild;
    }
    if (hasSocket &&
        (socketAuthToken != accessToken || socketUserId != requestedUserId)) {
      return SocketConnectionAction.rebuild;
    }
    return SocketConnectionAction.reuse;
  }

  static SocketAuthFailureAction authFailureAction({
    required String? code,
    required bool refreshedTokenRejected,
  }) {
    if (refreshedTokenRejected) return SocketAuthFailureAction.stopWithError;
    switch (code) {
      case 'auth_backend_unavailable':
        return SocketAuthFailureAction.retryWithoutRefresh;
      case 'session_revoked':
      case 'user_inactive':
      case 'user_not_found':
      case 'verified_login_required':
        return SocketAuthFailureAction.logout;
      default:
        return SocketAuthFailureAction.refresh;
    }
  }

  static String? userFacingAuthMessage(String error) {
    final normalized = error.toLowerCase();
    if (normalized.contains('session expired') ||
        normalized.contains('require logging in again') ||
        normalized.contains('require a valid login') ||
        normalized.contains('verified login required')) {
      return 'เซสชันหมดอายุหรือไม่ถูกต้อง กรุณาเข้าสู่ระบบใหม่';
    }
    if (normalized.contains('recovery paused') ||
        normalized.contains('refreshed access token')) {
      return 'การแจ้งเตือนเรียลไทม์ถูกพักชั่วคราว เนื่องจากตรวจสอบ token ไม่สำเร็จ กรุณาเข้าสู่ระบบใหม่หรือติดต่อผู้ดูแล';
    }
    return null;
  }

  static bool canAttemptRecovery(int attempts, {int maximum = 3}) =>
      attempts < maximum;
}
