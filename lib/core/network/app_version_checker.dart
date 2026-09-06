import 'dart:convert';
import 'package:http/http.dart as http';
import 'package:flutter/foundation.dart';

/// Minimum supported app version policy (Phase 13.2 compatibility).
///
/// Backend can reject clients below MIN_APP_VERSION with 426 Upgrade Required.
/// This helper checks the version on app start and during API calls.
class AppVersionChecker {
  static const String _minVersionHeader = 'x-min-app-version';
  static const String _forceUpdateHeader = 'x-force-update';

  /// Compare semantic version strings (e.g. "1.0.0" vs "1.2.3").
  /// Returns: -1 if a < b, 0 if a == b, 1 if a > b.
  static int compareVersions(String a, String b) {
    final partsA = a.split('.').map(int.parse).toList();
    final partsB = b.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va < vb) return -1;
      if (va > vb) return 1;
    }
    return 0;
  }

  /// Check if current app version meets minimum requirement.
  /// Called on app start and when receiving 426 from backend.
  static bool meetsMinimum(String currentVersion, String minVersion) {
    return compareVersions(currentVersion, minVersion) >= 0;
  }

  /// Extract min version from response headers (if backend sends it).
  static String? extractMinVersion(http.Response response) {
    final header = response.headers[_minVersionHeader];
    if (header != null && header.isNotEmpty) {
      return header;
    }
    return null;
  }

  /// Check if response indicates force update required (426).
  static bool isUpgradeRequired(http.Response response) {
    return response.statusCode == 426;
  }

  /// Parse upgrade required response body.
  static UpgradeRequiredInfo? parseUpgradeResponse(http.Response response) {
    if (response.statusCode != 426) return null;
    try {
      final data = jsonDecode(response.body);
      return UpgradeRequiredInfo(
        minVersion: data['minVersion'] ?? '0.0.0',
        message: data['message'] ?? 'Please update your app to continue.',
        storeUrl: data['storeUrl'],
      );
    } catch (err) {
      debugPrint('[AppVersionChecker] Failed to parse upgrade response: $err');
      return UpgradeRequiredInfo(
        minVersion: '0.0.0',
        message: 'Please update your app to continue.',
      );
    }
  }
}

class UpgradeRequiredInfo {
  final String minVersion;
  final String message;
  final String? storeUrl;

  UpgradeRequiredInfo({
    required this.minVersion,
    required this.message,
    this.storeUrl,
  });
}
