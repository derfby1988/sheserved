import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../core/network/authenticated_http_client.dart';
import '../features/admin/models/map_provider_config.dart';
import 'auth_service.dart';

/// A successfully loaded config snapshot.
class MapConfigSnapshot {
  final MapProviderConfig config;
  final TileSourceRegistry registry;

  /// Phase 24.A — data-layer registry mirrored from the server's
  /// `mapLayers` payload (embedded defaults when the server omits it).
  final MapLayerRegistry mapLayers;
  final String? updatedBy;
  final String? reason;

  /// True when this is the embedded app default because the server could not
  /// be reached — callers must surface this, never fake a saved state (§4.9).
  final bool isAppDefault;

  MapConfigSnapshot({
    required this.config,
    required this.registry,
    MapLayerRegistry? mapLayers,
    this.updatedBy,
    this.reason,
    this.isAppDefault = false,
  }) : mapLayers = mapLayers ?? MapLayerRegistry.defaults();
}

/// Audit row from GET /api/admin/map-config/history.
class MapConfigRevision {
  final int id;
  final int revision;
  final String environment;
  final Map<String, dynamic>? oldConfig;
  final Map<String, dynamic> newConfig;
  final String? reason;
  final String? actor;
  final DateTime createdAt;

  const MapConfigRevision({
    required this.id,
    required this.revision,
    required this.environment,
    this.oldConfig,
    required this.newConfig,
    this.reason,
    this.actor,
    required this.createdAt,
  });

  factory MapConfigRevision.fromJson(Map<String, dynamic> json) => MapConfigRevision(
        // bigint columns arrive as strings from node-postgres — parse
        // through toString so both int and string payloads work.
        id: num.tryParse(json['id']?.toString() ?? '')?.toInt() ?? 0,
        revision: num.tryParse(json['revision']?.toString() ?? '')?.toInt() ?? 0,
        environment: json['environment'] as String? ?? 'dev',
        oldConfig: json['old_config'] as Map<String, dynamic>?,
        newConfig: Map<String, dynamic>.from(json['new_config'] as Map),
        reason: json['reason'] as String?,
        actor: json['actor'] as String?,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// Save outcomes — the caller distinguishes them to drive the UI
/// (conflict banner vs. inline error vs. toast).
sealed class MapConfigSaveResult {
  const MapConfigSaveResult();
}

class MapConfigSaved extends MapConfigSaveResult {
  final MapProviderConfig config;
  final List<String> warnings;
  const MapConfigSaved(this.config, {this.warnings = const []});
}

class MapConfigConflict extends MapConfigSaveResult {
  final int? currentRevision;
  const MapConfigConflict({this.currentRevision});
}

class MapConfigValidationFailed extends MapConfigSaveResult {
  final List<String> errors;
  final List<String> warnings;
  const MapConfigValidationFailed(this.errors, {this.warnings = const []});
}

class MapConfigUnauthorized extends MapConfigSaveResult {
  final String message;
  const MapConfigUnauthorized(this.message);
}

class MapConfigSaveError extends MapConfigSaveResult {
  final String message;
  const MapConfigSaveError(this.message);
}

/// Loads and saves the map provider config through the backend.
///
/// - Reads: GET /api/map-config (public safe shape). Admin metadata comes
///   from GET /api/admin/map-config when the session is authorized.
/// - Writes: PUT /api/admin/map-config only — the client NEVER touches
///   `app_settings` or the table directly (§5.2).
/// - Concurrency: `expectedRevision` optimistic lock; 409 → [MapConfigConflict].
/// - Availability: when the server cannot be reached, returns the embedded
///   app default flagged `isAppDefault` so the UI can show a degraded state.
class MapConfigService {
  final String _baseUrl;
  final Future<http.Response> Function(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    Map<String, dynamic>? queryParams,
  }) _request;
  final Future<http.Response> Function(Uri uri, {Map<String, String>? headers}) _get;

  /// Last successfully loaded snapshot — returned on transient failures so
  /// the UI can keep working with a stale-but-real config.
  MapConfigSnapshot? _lastGood;

  MapConfigService({
    String? baseUrl,
    Future<http.Response> Function(
      String method,
      String path, {
      Map<String, String>? headers,
      Object? body,
      Map<String, dynamic>? queryParams,
    })? request,
    Future<http.Response> Function(Uri uri, {Map<String, String>? headers})? get,
  })  : _baseUrl = baseUrl ?? AppConfig.backendApiUrl,
        _request = request ??
            ((method, path, {headers, body, queryParams}) =>
                AuthenticatedHttpClient.instance.request(
                  method,
                  path,
                  headers: headers,
                  body: body,
                  queryParams: queryParams,
                )),
        _get = get ?? ((uri, {headers}) => http.get(uri, headers: headers));

  /// Headers that identify the caller on legacy (x-user-id) deployments —
  /// the JWT path needs nothing extra (the client adds Bearer itself).
  Map<String, String> _legacyHeaders() {
    final headers = <String, String>{'x-app-version': AppConfig.appVersion};
    if (!AuthenticatedHttpClient.instance.isAuthenticated) {
      final userId = AuthService.instance.userId;
      if (userId != null && userId.isNotEmpty) headers['x-user-id'] = userId;
    }
    return headers;
  }

  Map<String, dynamic>? _decode(http.Response res) {
    try {
      final d = jsonDecode(res.body);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  /// Load the current config. [admin] adds write metadata (updatedBy/reason)
  /// when the session is authorized; falls back to the public shape.
  Future<MapConfigSnapshot> load({bool admin = false, bool forceRefresh = false}) async {
    if (admin) {
      try {
        final res = await _request('GET', '/api/admin/map-config', headers: _legacyHeaders());
        if (res.statusCode == 200) {
          final snap = _parse(res, includeMeta: true);
          if (snap != null) return _lastGood = snap;
        }
        // 401/403: fall through to the public read — the settings page shows
        // read-only state rather than an error (the role guard lives at the page).
      } catch (_) {/* fall through to public */}
    }

    try {
      final res = await _get(
        Uri.parse('$_baseUrl/api/map-config'),
        headers: {'x-app-version': AppConfig.appVersion},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final snap = _parse(res);
        if (snap != null) return _lastGood = snap;
      }
      throw StateError('map-config returned ${res.statusCode}');
    } catch (e) {
      debugPrint('MapConfigService: load failed ($e)');
      if (!forceRefresh && _lastGood != null) return _lastGood!;
      return MapConfigSnapshot(
        config: MapProviderConfig.appDefault(),
        registry: TileSourceRegistry.defaults(),
        isAppDefault: true,
      );
    }
  }

  MapConfigSnapshot? _parse(http.Response res, {bool includeMeta = false}) {
    final body = _decode(res);
    if (body == null) return null;
    final config = MapProviderConfig.fromJson(body);
    final registry = TileSourceRegistry.defaults()
        .withServerReadiness(body['tileSources'] as Map<String, dynamic>?);
    return MapConfigSnapshot(
      config: config,
      registry: registry,
      mapLayers:
          MapLayerRegistry.fromServer(body['mapLayers'] as Map<String, dynamic>?),
      updatedBy: includeMeta ? body['updatedBy'] as String? : null,
      reason: includeMeta ? body['reason'] as String? : null,
    );
  }

  /// Save [config] — [expectedRevision] is the revision the draft was based
  /// on (optimistic lock). [confirmations] carries the §4.5 acknowledgements
  /// (`googleWebBudget`, `osmNoTraffic`).
  Future<MapConfigSaveResult> save(
    MapProviderConfig config, {
    required int expectedRevision,
    String? reason,
    Map<String, dynamic> confirmations = const {},
  }) async {
    try {
      final res = await _request(
        'PUT',
        '/api/admin/map-config',
        headers: _legacyHeaders(),
        body: jsonEncode({
          'config': config.toConfigJson(),
          'expectedRevision': expectedRevision,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
          if (confirmations.isNotEmpty) 'confirmations': confirmations,
        }),
      );
      final body = _decode(res) ?? {};
      switch (res.statusCode) {
        case 200:
          final saved = MapProviderConfig.fromJson(Map<String, dynamic>.from(body['data'] as Map));
          _lastGood = MapConfigSnapshot(
            config: saved,
            registry: TileSourceRegistry.defaults(),
            mapLayers: _lastGood?.mapLayers,
          );
          return MapConfigSaved(
            saved,
            warnings: (body['warnings'] as List?)?.cast<String>() ?? const [],
          );
        case 401:
        case 403:
          return MapConfigUnauthorized(
            body['error']?.toString() ?? 'ไม่มีสิทธิ์แก้ไขการตั้งค่า (ต้องเป็น admin)',
          );
        case 409:
          return MapConfigConflict(currentRevision: (body['currentRevision'] as num?)?.toInt());
        case 422:
          return MapConfigValidationFailed(
            (body['details'] as List?)?.cast<String>() ?? [body['error']?.toString() ?? 'invalid'],
            warnings: (body['warnings'] as List?)?.cast<String>() ?? const [],
          );
        default:
          return MapConfigSaveError(body['error']?.toString() ?? 'HTTP ${res.statusCode}');
      }
    } catch (e) {
      return MapConfigSaveError(e.toString());
    }
  }

  /// Roll back to the config stored in audit entry [auditId].
  Future<MapConfigSaveResult> rollback(int auditId, {required int expectedRevision, String? reason}) async {
    try {
      final res = await _request(
        'POST',
        '/api/admin/map-config/rollback',
        headers: _legacyHeaders(),
        body: jsonEncode({
          'auditId': auditId,
          'expectedRevision': expectedRevision,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        }),
      );
      final body = _decode(res) ?? {};
      switch (res.statusCode) {
        case 200:
          return MapConfigSaved(
            MapProviderConfig.fromJson(Map<String, dynamic>.from(body['data'] as Map)),
          );
        case 401:
        case 403:
          return MapConfigUnauthorized(body['error']?.toString() ?? 'ไม่มีสิทธิ์');
        case 409:
          return MapConfigConflict(currentRevision: (body['currentRevision'] as num?)?.toInt());
        default:
          return MapConfigSaveError(body['error']?.toString() ?? 'HTTP ${res.statusCode}');
      }
    } catch (e) {
      return MapConfigSaveError(e.toString());
    }
  }

  Future<List<MapConfigRevision>> history({int limit = 20}) async {
    try {
      final res = await _request(
        'GET',
        '/api/admin/map-config/history',
        headers: _legacyHeaders(),
        queryParams: {'limit': '$limit'},
      );
      if (res.statusCode != 200) return const [];
      final body = _decode(res);
      final items = body?['items'] as List? ?? const [];
      return items
          .whereType<Map>()
          .map((e) => MapConfigRevision.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('MapConfigService: history failed ($e)');
      return const [];
    }
  }
}
