import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../config/app_config.dart';
import '../../models/incident_map_models.dart';

/// Incident Overview Map repository (VIDEO_SYSTEM_PLAN.md §22.4)
///
/// Local API first (canonical first-GPS-point rule), Supabase RPC
/// `get_emergency_incident_map` as fallback — both return the same contract.
/// Fail-closed: a response that cannot be parsed throws instead of degrading
/// into an unfiltered map.
class IncidentMapRepository {
  final SupabaseClient _client;

  /// Normalizes legacy-host photo URLs (same rule as [VideoRepository.ensureFullUrl]).
  final String Function(String url) normalizeUrl;

  IncidentMapRepository({
    SupabaseClient? client,
    String Function(String url)? normalizeUrl,
  }) : _client = client ?? Supabase.instance.client,
       normalizeUrl = normalizeUrl ?? ((url) => url);

  Future<IncidentMapResponse> getIncidentMap({
    required String categoryId,
    required IncidentMapBounds bounds,
    required int zoom,
    String? cursor,
    int limit = 300,
  }) async {
    // ── 1. Local API ──────────────────────────────────────────────
    // Clamp bounds ก่อนส่ง — Google getVisibleRegion อาจคืนค่าเกิน ±90/±180
    // หรือคร่อม antimeridian จน server ตอบ 400 (§22.20)
    final safeBounds = bounds.clamped();
    String? localError;
    try {
      final uri = Uri.parse('${AppConfig.localApiUrl}/api/videos/emergency/map')
          .replace(
            queryParameters: {
              'category_id': categoryId,
              'bounds': safeBounds.toQueryParam(),
              'zoom': '$zoom',
              if (cursor != null) 'cursor': cursor,
              'limit': '$limit',
            },
          );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return _normalize(IncidentMapResponse.fromJson(decoded));
        }
        throw StateError('incident map response is not an object');
      }
      // 400 = contract violation (bad params) — fail-closed, no fallback.
      // 4xx/5xx อื่น (โดยเฉพาะ 429 rate limit / 5xx) เป็น transient →
      // ตกไป Supabase fallback แทนที่จะ fail-closed (§22.20)
      if (response.statusCode == 400) {
        throw StateError(
          'incident map request rejected (${response.statusCode})',
        );
      }
      localError = 'HTTP ${response.statusCode}';
    } on StateError {
      rethrow;
    } catch (e) {
      localError = e.toString();
      debugPrint('IncidentMapRepository: local fetch failed - $e');
    }

    // ── 2. Supabase RPC fallback (same shape, fail-closed) ────────
    try {
      final response = await _client.rpc<dynamic>(
        'get_emergency_incident_map',
        params: {
          'p_category_id': categoryId,
          'p_south': safeBounds.south,
          'p_west': safeBounds.west,
          'p_north': safeBounds.north,
          'p_east': safeBounds.east,
          'p_zoom': zoom,
          'p_cursor_created_at': _cursorCreatedAt(cursor),
          'p_cursor_id': _cursorId(cursor),
          'p_limit': limit,
        },
      );
      final decoded = response is Map<String, dynamic>
          ? response
          : (response is Map ? Map<String, dynamic>.from(response) : null);
      if (decoded == null) {
        throw StateError('incident map RPC returned no data');
      }
      return _normalize(IncidentMapResponse.fromJson(decoded));
    } catch (e) {
      debugPrint(
        'IncidentMapRepository: supabase fallback failed (local: $localError) - $e',
      );
      rethrow;
    }
  }

  static String? _cursorCreatedAt(String? cursor) {
    final key = _decodeCursor(cursor);
    return key?.$1;
  }

  static String? _cursorId(String? cursor) {
    final key = _decodeCursor(cursor);
    return key?.$2;
  }

  /// Cursor is opaque base64url JSON `{"c":iso,"i":id}` produced by the
  /// backend; decode defensively so either path can resume the other's page.
  static (String, String)? _decodeCursor(String? cursor) {
    if (cursor == null || cursor.isEmpty) return null;
    try {
      final normalized = cursor.replaceAll('-', '+').replaceAll('_', '/');
      final padded = normalized + '=' * ((4 - normalized.length % 4) % 4);
      final obj = jsonDecode(utf8.decode(base64Decode(padded)));
      if (obj is! Map) return null;
      final c = obj['c']?.toString() ?? '';
      final i = obj['i']?.toString() ?? '';
      if (c.isEmpty || i.isEmpty) return null;
      return (c, i);
    } catch (_) {
      return null;
    }
  }

  /// Normalize legacy-host photo URLs for display.
  IncidentMapResponse _normalize(IncidentMapResponse response) {
    final items = response.items.map((item) {
      if (item is! IncidentMapPointItem) return item;
      return IncidentMapPointItem(
        lat: item.lat,
        lng: item.lng,
        id: item.id,
        categoryId: item.categoryId,
        createdAt: item.createdAt,
        bucket: item.bucket,
        photos: item.photos
            .map(
              (p) => IncidentMapPhoto(
                id: p.id,
                url: normalizeUrl(p.url),
                blurStatus: p.blurStatus,
                createdAt: p.createdAt,
              ),
            )
            .toList(),
      );
    }).toList();
    return IncidentMapResponse(
      mode: response.mode,
      zoom: response.zoom,
      truncated: response.truncated,
      legend: response.legend,
      excluded: response.excluded,
      items: items,
      nextCursor: response.nextCursor,
    );
  }
}
