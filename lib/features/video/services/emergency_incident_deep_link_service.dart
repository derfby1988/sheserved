import 'package:flutter/foundation.dart';

/// Data class representing extracted deep link parameters for an Emergency Incident
class EmergencyIncidentDeepLinkData {
  final String videoId;
  final String? photoId;
  final String? src;

  const EmergencyIncidentDeepLinkData({
    required this.videoId,
    this.photoId,
    this.src,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmergencyIncidentDeepLinkData &&
          runtimeType == other.runtimeType &&
          videoId == other.videoId &&
          photoId == other.photoId &&
          src == other.src;

  @override
  int get hashCode => videoId.hashCode ^ photoId.hashCode ^ src.hashCode;

  @override
  String toString() =>
      'EmergencyIncidentDeepLinkData(videoId: $videoId, photoId: $photoId, src: $src)';
}

/// Service for generating, parsing, and managing Emergency Incident deep links
class EmergencyIncidentDeepLinkService {
  static const String baseWebUrl = 'https://sheserved.me/emergency/incident';
  static const String customScheme = 'sheserved://emergency/incident';

  static EmergencyIncidentDeepLinkData? _pendingDeepLink;

  /// Builds a web Universal Link for incident sharing
  static String buildIncidentShareUrl(String videoId, {String? photoId}) {
    final cleanVideoId = Uri.encodeComponent(videoId.trim());
    final buffer = StringBuffer('$baseWebUrl/$cleanVideoId?src=share');
    if (photoId != null && photoId.trim().isNotEmpty) {
      final cleanPhotoId = Uri.encodeComponent(photoId.trim());
      buffer.write('&photo=$cleanPhotoId');
    }
    return buffer.toString();
  }

  /// Builds the share link. Always returns the `https://sheserved.me` web
  /// universal link because the `sheserved://` custom scheme renders as
  /// non-clickable plain text in chat apps (LINE, Messenger). The web link
  /// opens the app directly on Android (verified App Links) and falls back to
  /// the deployed web app everywhere else — including iOS debug builds that
  /// cannot sign Associated Domains (personal team), where the SPA at
  /// sheserved.me still routes `/emergency/incident/<id>` to the incident view.
  static String buildIncidentShareLink(String videoId, {String? photoId}) {
    return buildIncidentShareUrl(videoId, photoId: photoId);
  }

  /// Builds a custom scheme URL for deep linking inside mobile environments
  static String buildIncidentCustomSchemeUrl(String videoId, {String? photoId}) {
    final cleanVideoId = Uri.encodeComponent(videoId.trim());
    final buffer = StringBuffer('$customScheme/$cleanVideoId');
    final queryParams = <String>[];
    if (photoId != null && photoId.trim().isNotEmpty) {
      queryParams.add('photo=${Uri.encodeComponent(photoId.trim())}');
    }
    if (queryParams.isNotEmpty) {
      buffer.write('?${queryParams.join('&')}');
    }
    return buffer.toString();
  }

  /// Parses a deep link URL or route path and returns [EmergencyIncidentDeepLinkData]
  /// Returns `null` if the URL format does not match an emergency incident route.
  static EmergencyIncidentDeepLinkData? parseDeepLink(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;

    try {
      final uri = Uri.parse(rawUrl.trim());
      final pathSegments = uri.pathSegments;

      // Case 1: Custom Scheme (sheserved://emergency/incident/{videoId})
      if (uri.scheme == 'sheserved') {
        if (uri.host == 'emergency' &&
            pathSegments.isNotEmpty &&
            pathSegments.first == 'incident' &&
            pathSegments.length >= 2) {
          final videoId = Uri.decodeComponent(pathSegments[1]).trim();
          if (videoId.isNotEmpty) {
            return _createData(videoId, uri);
          }
        }
      }

      // Case 2: Web Universal Link or relative path
      // e.g., https://sheserved.me/emergency/incident/{videoId}
      // or /emergency/incident/{videoId}
      int incidentSegmentIdx = -1;
      for (int i = 0; i < pathSegments.length; i++) {
        if (pathSegments[i] == 'incident') {
          // Verify preceding segment is 'emergency' if available
          if (i == 0 || pathSegments[i - 1] == 'emergency') {
            incidentSegmentIdx = i;
            break;
          }
        }
      }

      if (incidentSegmentIdx != -1 && pathSegments.length > incidentSegmentIdx + 1) {
        final videoId = Uri.decodeComponent(pathSegments[incidentSegmentIdx + 1]).trim();
        if (videoId.isNotEmpty) {
          return _createData(videoId, uri);
        }
      }
    } catch (e) {
      debugPrint('Error parsing emergency incident deep link: $e');
    }

    return null;
  }

  static EmergencyIncidentDeepLinkData _createData(String videoId, Uri uri) {
    final rawPhoto = uri.queryParameters['photo']?.trim();
    final rawSrc = uri.queryParameters['src']?.trim();
    return EmergencyIncidentDeepLinkData(
      videoId: videoId,
      photoId: (rawPhoto != null && rawPhoto.isNotEmpty) ? rawPhoto : null,
      src: (rawSrc != null && rawSrc.isNotEmpty) ? rawSrc : null,
    );
  }

  /// Stores a pending deep link for deferred handling (e.g. after login or page init)
  static void storePendingDeepLink(EmergencyIncidentDeepLinkData data) {
    _pendingDeepLink = data;
  }

  /// Gets and clears the stored pending deep link
  static EmergencyIncidentDeepLinkData? consumePendingDeepLink() {
    final pending = _pendingDeepLink;
    _pendingDeepLink = null;
    return pending;
  }

  /// Peek at pending deep link without clearing
  static EmergencyIncidentDeepLinkData? peekPendingDeepLink() => _pendingDeepLink;

  /// Clears stored pending deep link
  static void clearPendingDeepLink() {
    _pendingDeepLink = null;
  }
}
