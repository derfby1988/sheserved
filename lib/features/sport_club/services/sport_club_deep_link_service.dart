import 'package:flutter/foundation.dart';

/// Data class representing extracted deep link parameters for Sport Club
class GroupDetailDeepLinkData {
  final String groupId;
  final String? sessionId;

  const GroupDetailDeepLinkData({
    required this.groupId,
    this.sessionId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupDetailDeepLinkData &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId &&
          sessionId == other.sessionId;

  @override
  int get hashCode => groupId.hashCode ^ sessionId.hashCode;

  @override
  String toString() =>
      'GroupDetailDeepLinkData(groupId: $groupId, sessionId: $sessionId)';
}

/// Service for generating, parsing, and managing Sport Club deep links
class SportClubDeepLinkService {
  static const String baseWebUrl = 'https://sheserved.com/sport-club/group';
  static const String customScheme = 'sheserved://sport-club/group';

  static GroupDetailDeepLinkData? _pendingDeepLink;

  /// Builds a web Universal Link for group or session invitation
  static String buildGroupInviteUrl(String groupId, {String? sessionId}) {
    final cleanGroupId = Uri.encodeComponent(groupId);
    final buffer = StringBuffer('$baseWebUrl/$cleanGroupId');
    if (sessionId != null && sessionId.trim().isNotEmpty) {
      final cleanSessionId = Uri.encodeComponent(sessionId.trim());
      buffer.write('?session_id=$cleanSessionId');
    }
    return buffer.toString();
  }

  /// Builds a custom scheme URL for deep linking inside mobile environments
  static String buildGroupCustomSchemeUrl(String groupId, {String? sessionId}) {
    final cleanGroupId = Uri.encodeComponent(groupId);
    final buffer = StringBuffer('$customScheme/$cleanGroupId');
    if (sessionId != null && sessionId.trim().isNotEmpty) {
      final cleanSessionId = Uri.encodeComponent(sessionId.trim());
      buffer.write('?session_id=$cleanSessionId');
    }
    return buffer.toString();
  }

  /// Parses a deep link URL or route path and returns [GroupDetailDeepLinkData]
  /// Returns `null` if the URL format does not match a sport club group route.
  static GroupDetailDeepLinkData? parseDeepLink(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;

    try {
      final uri = Uri.parse(rawUrl.trim());
      final pathSegments = uri.pathSegments;

      // Handle custom scheme: sheserved://sport-club/group/{groupId}
      if (uri.scheme == 'sheserved') {
        if (uri.host == 'sport-club' &&
            pathSegments.isNotEmpty &&
            pathSegments.first == 'group' &&
            pathSegments.length >= 2) {
          final groupId = Uri.decodeComponent(pathSegments[1]);
          final sessionId = uri.queryParameters['session_id'];
          return GroupDetailDeepLinkData(
            groupId: groupId,
            sessionId: sessionId?.isNotEmpty == true ? sessionId : null,
          );
        }
      }

      // Handle HTTP/HTTPS or relative path:
      // e.g., https://sheserved.com/sport-club/group/{groupId}
      // or /sport-club/group/{groupId}
      // or /community/sport-club/group/{groupId}
      int groupSegmentIdx = -1;
      for (int i = 0; i < pathSegments.length; i++) {
        if (pathSegments[i] == 'group') {
          groupSegmentIdx = i;
          break;
        }
      }

      if (groupSegmentIdx != -1 &&
          pathSegments.length > groupSegmentIdx + 1) {
        final groupId = Uri.decodeComponent(pathSegments[groupSegmentIdx + 1]);
        if (groupId.isNotEmpty) {
          final sessionId = uri.queryParameters['session_id'];
          return GroupDetailDeepLinkData(
            groupId: groupId,
            sessionId: sessionId?.isNotEmpty == true ? sessionId : null,
          );
        }
      }
    } catch (e) {
      debugPrint('Error parsing sport club deep link: $e');
    }

    return null;
  }

  /// Stores a pending deep link for deferred handling (e.g. after login)
  static void storePendingDeepLink(GroupDetailDeepLinkData data) {
    _pendingDeepLink = data;
  }

  /// Gets and clears the stored pending deep link
  static GroupDetailDeepLinkData? consumePendingDeepLink() {
    final pending = _pendingDeepLink;
    _pendingDeepLink = null;
    return pending;
  }

  /// Peek at pending deep link without clearing
  static GroupDetailDeepLinkData? peekPendingDeepLink() => _pendingDeepLink;
}
