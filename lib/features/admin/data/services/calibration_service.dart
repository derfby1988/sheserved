import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/body_landmark_model.dart';
import '../models/body_region_model.dart';

/// Service for resolving multi-point body region calibration.
///
/// Implements 4-layer resolution:
/// 1. Per-region override (body_regions.landmarks JSONB)
/// 2. Gender + platform specific defaults
/// 3. Gender + universal defaults
/// 4. Both + universal fallback defaults
///
/// Provides piecewise linear interpolation for both yRatio and xRatio.
class CalibrationService {
  final SupabaseClient _client;

  CalibrationService(this._client);

  // ── Cached defaults (simple in-memory cache) ────────────────────────────
  final Map<String, List<BodyLandmark>> _defaultsCache = {};

  String _cacheKey(String gender, String platform) => '${gender}_$platform';

  // ── Platform Detection ──────────────────────────────────────────────────

  /// Detects the current platform for calibration lookup.
  /// Returns: 'web' | 'mobile' | 'tablet' | 'universal'
  static String detectPlatform() {
    if (kIsWeb) return 'web';
    try {
      // Shortest side heuristic for tablet detection
      // (This is a best-effort; exact thresholds can be tuned.)
      // We can't import dart:ui View here without context, so callers
      // that have a BuildContext can pass explicit platform hints.
      return 'mobile';
    } catch (_) {
      return 'universal';
    }
  }

  // ── 4-Layer Landmark Resolution ────────────────────────────────────────

  /// Resolves the best available landmarks for a region.
  ///
  /// Returns the per-region override if present, otherwise queries
  /// calibration_defaults with cascading fallback:
  /// (gender,platform) → (gender,universal) → (both,universal)
  Future<List<BodyLandmark>> resolveLandmarks(
    BodyRegionModel region, {
    String? patientGender,
  }) async {
    // Layer 1: Per-region override
    if (region.landmarks != null && region.landmarks!.isNotEmpty) {
      return region.landmarks!;
    }

    // Determine lookup keys
    final gender = patientGender ?? region.calibrationGender;
    final platform = region.calibrationPlatform;

    // Layer 2-4: Query with fallback chain
    final result = await _queryWithFallback(
      gender: gender,
      platform: platform,
    );

    if (result != null && result.isNotEmpty) return result;

    // Ultimate fallback: built-in hardcoded defaults
    return _fallbackLandmarks();
  }

  /// Synchronous version for use when data is already loaded.
  /// This checks the per-region override only; global defaults must
  /// be pre-loaded via [loadDefaults] or use the async variant.
  List<BodyLandmark> resolveLandmarksSync(
    BodyRegionModel region, {
    String? patientGender,
  }) {
    // Layer 1: Per-region override
    if (region.landmarks != null && region.landmarks!.isNotEmpty) {
      return region.landmarks!;
    }

    // Layer 2-4: Check cache
    final gender = patientGender ?? region.calibrationGender;
    final platform = region.calibrationPlatform;

    final cached = _lookupCached(gender, platform);
    if (cached != null && cached.isNotEmpty) return cached;

    // Ultimate fallback
    return _fallbackLandmarks();
  }

  // ── Async DB Queries ───────────────────────────────────────────────────

  Future<List<BodyLandmark>?> _queryWithFallback({
    required String gender,
    required String platform,
  }) async {
    // Try: (gender, platform)
    var result = await _queryDefaults(gender: gender, platform: platform);
    if (result != null) return result;

    // Try: (gender, universal)
    if (platform != 'universal') {
      result = await _queryDefaults(gender: gender, platform: 'universal');
      if (result != null) return result;
    }

    // Try: (both, universal)
    if (gender != 'both') {
      result = await _queryDefaults(gender: 'both', platform: 'universal');
      if (result != null) return result;
    }

    return null;
  }

  Future<List<BodyLandmark>?> _queryDefaults({
    required String gender,
    required String platform,
  }) async {
    final key = _cacheKey(gender, platform);
    if (_defaultsCache.containsKey(key)) {
      return _defaultsCache[key];
    }

    try {
      final response = await _client
          .from('body_region_calibration_defaults')
          .select('landmarks')
          .eq('gender', gender)
          .eq('platform', platform)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null || response['landmarks'] == null) return null;

      final list = (response['landmarks'] as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => BodyLandmark.fromJson(e))
          .toList();

      _defaultsCache[key] = list;
      return list;
    } catch (_) {
      return null;
    }
  }

  List<BodyLandmark>? _lookupCached(String gender, String platform) {
    final key = _cacheKey(gender, platform);
    if (_defaultsCache.containsKey(key)) return _defaultsCache[key];

    if (platform != 'universal') {
      final fallback = _cacheKey(gender, 'universal');
      if (_defaultsCache.containsKey(fallback)) return _defaultsCache[fallback];
    }

    if (gender != 'both') {
      final fallback = _cacheKey('both', 'universal');
      if (_defaultsCache.containsKey(fallback)) return _defaultsCache[fallback];
    }

    return null;
  }

  /// Returns the best-matching global default landmarks for the given gender
  /// and platform, querying the DB if not already cached. Falls back to the
  /// hardcoded fallback defaults when no DB record is available.
  Future<List<BodyLandmark>> getDefaultLandmarks({
    String gender = 'both',
    String platform = 'universal',
  }) async {
    final normalizedGender = gender.toLowerCase();
    final normalizedPlatform = platform.toLowerCase();

    var cached = _lookupCached(normalizedGender, normalizedPlatform);
    if (cached != null) return cached;

    // Try DB with cascading fallback (gender,platform) → (gender,universal) → (both,universal)
    var fromDb = await _queryWithFallback(
      gender: normalizedGender,
      platform: normalizedPlatform,
    );
    if (fromDb != null && fromDb.isNotEmpty) return fromDb;

    return _fallbackLandmarks();
  }

  // ── Pre-load defaults into cache ───────────────────────────────────────

  /// Loads all active defaults into memory cache.
  /// Call this once at app startup for sync access.
  Future<void> loadDefaults() async {
    try {
      final response = await _client
          .from('body_region_calibration_defaults')
          .select()
          .eq('is_active', true);

      for (final row in response) {
        final gender = row['gender'] as String? ?? 'both';
        final platform = row['platform'] as String? ?? 'universal';
        final list = (row['landmarks'] as List)
            .whereType<Map<String, dynamic>>()
            .map((e) => BodyLandmark.fromJson(e))
            .toList();
        _defaultsCache[_cacheKey(gender, platform)] = list;
      }
    } catch (_) {
      // Cache remains empty; sync fallback will use hardcoded defaults.
    }
  }

  // ── Piecewise Interpolation ────────────────────────────────────────────

  /// Piecewise linear interpolation: maps a 2D silhouette yRatio
  /// to the corresponding 3D model viewport yRatio using landmarks.
  static double modelYRatio(List<BodyLandmark> landmarks, double yRatio2d) {
    if (landmarks.isEmpty) return yRatio2d;

    final sorted = [...landmarks]..sort((a, b) => a.y2d.compareTo(b.y2d));

    for (int i = 0; i < sorted.length - 1; i++) {
      final l1 = sorted[i];
      final l2 = sorted[i + 1];
      if (yRatio2d >= l1.y2d && yRatio2d <= l2.y2d) {
        final t = (yRatio2d - l1.y2d) / (l2.y2d - l1.y2d);
        return l1.y3d + t * (l2.y3d - l1.y3d);
      }
    }

    // Extrapolation fallback (linear beyond first/last landmark)
    return sorted.first.y3d +
        (yRatio2d - sorted.first.y2d) *
        (sorted.last.y3d - sorted.first.y3d) /
        (sorted.last.y2d - sorted.first.y2d);
  }

  /// Piecewise linear interpolation: maps a 2D silhouette xRatio
  /// to the corresponding 3D model viewport xRatio using landmarks.
  static double modelXRatio(List<BodyLandmark> landmarks, double xRatio2d) {
    if (landmarks.isEmpty) return xRatio2d;

    final sorted = [...landmarks]..sort((a, b) => a.x2d.compareTo(b.x2d));

    for (int i = 0; i < sorted.length - 1; i++) {
      final l1 = sorted[i];
      final l2 = sorted[i + 1];
      if (xRatio2d >= l1.x2d && xRatio2d <= l2.x2d) {
        final t = (xRatio2d - l1.x2d) / (l2.x2d - l1.x2d);
        return l1.x3d + t * (l2.x3d - l1.x3d);
      }
    }

    // Most landmarks are centered (x2d=x3d=0.5), so fallback is identity.
    return xRatio2d;
  }

  /// Backward-compatible wrapper that falls back to top/bottom linear
  /// interpolation when no landmarks are available.
  static double modelYRatioCompat(
    List<BodyLandmark>? landmarks,
    double yRatio2d, {
    double modelTopRatio = 0.08,
    double modelBottomRatio = 0.93,
  }) {
    if (landmarks == null || landmarks.isEmpty) {
      final top = modelTopRatio;
      final bottom = modelBottomRatio;
      final effectiveTop = (top < bottom) ? top : 0.0;
      final effectiveBottom = (top < bottom) ? bottom : 1.0;
      return effectiveTop + yRatio2d * (effectiveBottom - effectiveTop);
    }
    return modelYRatio(landmarks, yRatio2d);
  }

  // ── Fallback Defaults ─────────────────────────────────────────────────

  /// Hardcoded fallback landmarks used when no DB data is available.
  static List<BodyLandmark> _fallbackLandmarks() => [
        const BodyLandmark(
          id: 0,
          name: 'ศีรษะ',
          nameEn: 'Head Top',
          y2d: 0.0,
          y3d: 0.08,
          x2d: 0.5,
          x3d: 0.5,
          autoDetected: true,
        ),
        const BodyLandmark(
          id: 1,
          name: 'คอ',
          nameEn: 'Neck',
          y2d: 0.12,
          y3d: 0.18,
          x2d: 0.5,
          x3d: 0.5,
        ),
        const BodyLandmark(
          id: 2,
          name: 'ไหล่',
          nameEn: 'Shoulders',
          y2d: 0.18,
          y3d: 0.25,
          x2d: 0.5,
          x3d: 0.5,
        ),
        const BodyLandmark(
          id: 3,
          name: 'สะดือ',
          nameEn: 'Navel',
          y2d: 0.50,
          y3d: 0.52,
          x2d: 0.5,
          x3d: 0.5,
        ),
        const BodyLandmark(
          id: 4,
          name: 'อวัยวะเพศ',
          nameEn: 'Groin',
          y2d: 0.68,
          y3d: 0.70,
          x2d: 0.5,
          x3d: 0.5,
        ),
        const BodyLandmark(
          id: 5,
          name: 'หัวเข่า',
          nameEn: 'Knees',
          y2d: 0.82,
          y3d: 0.85,
          x2d: 0.5,
          x3d: 0.5,
        ),
        const BodyLandmark(
          id: 6,
          name: 'เท้า',
          nameEn: 'Feet',
          y2d: 1.00,
          y3d: 0.93,
          x2d: 0.5,
          x3d: 0.5,
          autoDetected: true,
        ),
      ];

  // ── Admin helpers ─────────────────────────────────────────────────────

  /// Saves global defaults for a given gender+platform combination.
  Future<void> saveDefaults({
    required String gender,
    required String platform,
    required List<BodyLandmark> landmarks,
  }) async {
    await _client.from('body_region_calibration_defaults').upsert({
      'gender': gender,
      'platform': platform,
      'landmarks': landmarks.map((l) => l.toJson()).toList(),
      'is_active': true,
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Invalidate cache
    _defaultsCache.remove(_cacheKey(gender, platform));
  }

  /// Auto-detects landmarks from a 3D model by simple heuristics.
  /// In a real implementation this might use model vertex analysis
  /// or pre-defined anatomical knowledge.
  static List<BodyLandmark> autoDetectLandmarks() {
    // Heuristic: head = top, feet = bottom, others spaced proportionally
    return [
      const BodyLandmark(
        id: 0,
        name: 'ศีรษะ',
        nameEn: 'Head Top',
        y2d: 0.0,
        y3d: 0.08,
        x2d: 0.5,
        x3d: 0.5,
        autoDetected: true,
      ),
      const BodyLandmark(
        id: 1,
        name: 'คอ',
        nameEn: 'Neck',
        y2d: 0.12,
        y3d: 0.18,
        x2d: 0.5,
        x3d: 0.5,
        autoDetected: true,
      ),
      const BodyLandmark(
        id: 2,
        name: 'ไหล่',
        nameEn: 'Shoulders',
        y2d: 0.18,
        y3d: 0.25,
        x2d: 0.5,
        x3d: 0.5,
        autoDetected: true,
      ),
      const BodyLandmark(
        id: 3,
        name: 'สะดือ',
        nameEn: 'Navel',
        y2d: 0.50,
        y3d: 0.52,
        x2d: 0.5,
        x3d: 0.5,
        autoDetected: true,
      ),
      const BodyLandmark(
        id: 4,
        name: 'อวัยวะเพศ',
        nameEn: 'Groin',
        y2d: 0.68,
        y3d: 0.70,
        x2d: 0.5,
        x3d: 0.5,
        autoDetected: true,
      ),
      const BodyLandmark(
        id: 5,
        name: 'หัวเข่า',
        nameEn: 'Knees',
        y2d: 0.82,
        y3d: 0.85,
        x2d: 0.5,
        x3d: 0.5,
        autoDetected: true,
      ),
      const BodyLandmark(
        id: 6,
        name: 'เท้า',
        nameEn: 'Feet',
        y2d: 1.00,
        y3d: 0.93,
        x2d: 0.5,
        x3d: 0.5,
        autoDetected: true,
      ),
    ];
  }
}
