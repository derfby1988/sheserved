/// Map Provider Config — Phase 1 (docs/guides/map_provider_rollout_plan.md §5.1)
///
/// Client-side mirror of the server document stored in `map_provider_config`
/// (local backend DB) and served by GET /api/map-config +
/// GET|PUT /api/admin/map-config.
///
/// Resolution order (§5.1):
///   feature override → platform default → environment default embedded here
///
/// Invariants enforced client-side (server re-validates — never trust client):
///   - `yield_way` always inherits `emergency` — it is NOT a key in
///     [featureOverrides]
///   - renderer `osm` requires a [tileSourceId] that exists in the registry
///   - config contains NO secrets — API keys live in server-side secrets
library;

import 'dart:convert';

/// Map renderer engines the app can switch between.
enum MapRendererKind { google, osm }

/// Features that own a map surface (§4.2.5). `yield_way` is intentionally
/// absent — it is hard-locked to inherit `emergency`.
enum MapFeature { home, rescue, emergency, groupCreate }

extension MapFeatureKey on MapFeature {
  String get key => const {
        MapFeature.home: 'home',
        MapFeature.rescue: 'rescue',
        MapFeature.emergency: 'emergency',
        MapFeature.groupCreate: 'group_create',
      }[this]!;

  String get labelTh => const {
        MapFeature.home: 'หน้าหลัก (Home)',
        MapFeature.rescue: 'กู้ภัย (Rescue)',
        MapFeature.emergency: 'เหตุฉุกเฉิน (Emergency)',
        MapFeature.groupCreate: 'สร้างก๊วน (Group Create)',
      }[this]!;

  static MapFeature? fromKey(String key) => switch (key) {
        'home' => MapFeature.home,
        'rescue' => MapFeature.rescue,
        'emergency' => MapFeature.emergency,
        'group_create' => MapFeature.groupCreate,
        _ => null,
      };
}

enum MapPlatform { web, ios, android }

extension MapPlatformKey on MapPlatform {
  String get key => name;

  String get labelTh => const {
        MapPlatform.web: 'Web',
        MapPlatform.ios: 'iOS',
        MapPlatform.android: 'Android',
      }[this]!;

  static MapPlatform? fromKey(String key) => switch (key) {
        'web' => MapPlatform.web,
        'ios' => MapPlatform.ios,
        'android' => MapPlatform.android,
        _ => null,
      };
}

/// Per-platform map target: whether the live map is enabled at all, which
/// renderer draws it, and (for OSM) which tile source feeds it.
class MapTarget {
  final bool enabled;
  final MapRendererKind renderer;
  final String? tileSourceId;

  const MapTarget({
    required this.enabled,
    required this.renderer,
    this.tileSourceId,
  });

  MapTarget copyWith({bool? enabled, MapRendererKind? renderer, String? Function()? tileSourceId}) =>
      MapTarget(
        enabled: enabled ?? this.enabled,
        renderer: renderer ?? this.renderer,
        tileSourceId: tileSourceId != null ? tileSourceId() : this.tileSourceId,
      );

  factory MapTarget.fromJson(Map<String, dynamic> json) => MapTarget(
        enabled: json['enabled'] == true,
        renderer: json['renderer'] == 'osm' ? MapRendererKind.osm : MapRendererKind.google,
        tileSourceId: json['tileSourceId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'renderer': renderer.name,
        'tileSourceId': tileSourceId,
      };
}

/// Feature-level override. `inherit` means "use the platform default".
class FeatureOverride {
  final bool isOverride;
  final MapRendererKind renderer;
  final String? tileSourceId;

  const FeatureOverride.inherit()
      : isOverride = false,
        renderer = MapRendererKind.google,
        tileSourceId = null;

  const FeatureOverride.override({required this.renderer, this.tileSourceId})
      : isOverride = true;

  factory FeatureOverride.fromJson(Map<String, dynamic>? json) {
    if (json == null || json['mode'] != 'override') {
      return const FeatureOverride.inherit();
    }
    return FeatureOverride.override(
      renderer: json['renderer'] == 'osm' ? MapRendererKind.osm : MapRendererKind.google,
      tileSourceId: json['tileSourceId'] as String?,
    );
  }

  /// Omitted from the payload while in inherit mode — keeps the document lean.
  Map<String, dynamic>? toJson() => isOverride
      ? {'mode': 'override', 'renderer': renderer.name, 'tileSourceId': tileSourceId}
      : null;
}

class ServiceConfig {
  /// routing: google_directions | osrm | off
  final String routingProvider;
  final bool routingEnabled;

  /// search primary: nominatim | google_places (+ optional Places fallback)
  final String searchPrimary;
  final bool searchFallbackEnabled;

  /// traffic: google | none  (OSM basemaps carry no realtime traffic — §7.2)
  final String trafficProvider;

  const ServiceConfig({
    this.routingProvider = 'google_directions',
    this.routingEnabled = true,
    this.searchPrimary = 'nominatim',
    this.searchFallbackEnabled = true,
    this.trafficProvider = 'google',
  });

  factory ServiceConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ServiceConfig();
    final routing = json['routing'];
    final search = json['search'];
    final traffic = json['traffic'];
    return ServiceConfig(
      routingProvider:
          routing is Map ? (routing['provider'] as String? ?? 'google_directions') : 'google_directions',
      routingEnabled: routing is Map ? (routing['enabled'] as bool? ?? true) : true,
      searchPrimary: search is Map ? (search['primary'] as String? ?? 'nominatim') : 'nominatim',
      searchFallbackEnabled:
          search is Map ? (search['fallbackEnabled'] as bool? ?? true) : true,
      trafficProvider: traffic is Map ? (traffic['provider'] as String? ?? 'google') : 'google',
    );
  }

  ServiceConfig copyWith({
    String? routingProvider,
    bool? routingEnabled,
    String? searchPrimary,
    bool? searchFallbackEnabled,
    String? trafficProvider,
  }) =>
      ServiceConfig(
        routingProvider: routingProvider ?? this.routingProvider,
        routingEnabled: routingEnabled ?? this.routingEnabled,
        searchPrimary: searchPrimary ?? this.searchPrimary,
        searchFallbackEnabled: searchFallbackEnabled ?? this.searchFallbackEnabled,
        trafficProvider: trafficProvider ?? this.trafficProvider,
      );

  Map<String, dynamic> toJson() => {
        'routing': {'provider': routingProvider, 'enabled': routingEnabled},
        'search': {'primary': searchPrimary, 'fallbackEnabled': searchFallbackEnabled},
        'traffic': {'provider': trafficProvider},
      };
}

class FallbackConfig {
  final bool enabled;
  final String? providerId; // 'google' | 'osm'

  const FallbackConfig({this.enabled = false, this.providerId});

  factory FallbackConfig.fromJson(Map<String, dynamic>? json) => FallbackConfig(
        enabled: json?['enabled'] == true,
        providerId: json?['providerId'] as String?,
      );

  FallbackConfig copyWith({bool? enabled, String? Function()? providerId}) => FallbackConfig(
        enabled: enabled ?? this.enabled,
        providerId: providerId != null ? providerId() : this.providerId,
      );

  Map<String, dynamic> toJson() => {'enabled': enabled, 'providerId': providerId};
}

/// Google pricing knobs used by the cost banner (not a rate limiter).
class RateConfig {
  final double googleWebMapPerThousand;
  final double googleDirectionsPerThousand;
  final double googlePlacesPerThousand;

  const RateConfig({
    this.googleWebMapPerThousand = 7.0,
    this.googleDirectionsPerThousand = 5.0,
    this.googlePlacesPerThousand = 17.0,
  });

  factory RateConfig.fromJson(Map<String, dynamic>? json) => RateConfig(
        googleWebMapPerThousand: (json?['googleWebMapPerThousand'] as num?)?.toDouble() ?? 7.0,
        googleDirectionsPerThousand: (json?['googleDirectionsPerThousand'] as num?)?.toDouble() ?? 5.0,
        googlePlacesPerThousand: (json?['googlePlacesPerThousand'] as num?)?.toDouble() ?? 17.0,
      );

  Map<String, dynamic> toJson() => {
        'googleWebMapPerThousand': googleWebMapPerThousand,
        'googleDirectionsPerThousand': googleDirectionsPerThousand,
        'googlePlacesPerThousand': googlePlacesPerThousand,
      };
}

/// Tile-source readiness, mirrored from the server canonical list
/// (routes/map-config.js). `needsKey` entries cannot be saved until the
/// provider key is configured server-side.
enum TileSourceReadiness { ready, devOnly, needsKey }

/// A raster tile endpoint the OSM renderer can use. URLs carry no secrets —
/// key-required sources get their key appended by the tile provider layer.
class TileSource {
  final String id;
  final String label;
  final String urlTemplate;
  final String attribution;
  final TileSourceReadiness readiness;

  /// เพดาน zoom ของ tile pyramid จริงของ source — เกินนี้ flutter_map
  /// จะ scale tile จากระดับนี้แทนที่จะขอ z ที่ไม่มี (เช่น OSM ให้ถึง z19
  /// เท่านั้น การขอ z20 ได้ 400 แล้วจอเทา — บั๊กที่พบใน OSM verify 2026-10-19)
  final int maxNativeZoom;

  const TileSource({
    required this.id,
    required this.label,
    required this.urlTemplate,
    required this.attribution,
    required this.readiness,
    this.maxNativeZoom = 19,
  });

  bool get selectable => readiness != TileSourceReadiness.needsKey;
}

/// Built-in catalog — keep ids in sync with TILE_SOURCES in
/// websocket-server/routes/map-config.js. Readiness from the server response
/// overrides these defaults at load time (server is canonical).
class TileSourceRegistry {
  static const defaultSources = <TileSource>[
    TileSource(
      id: 'osm_standard',
      label: 'OSM Standard',
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      attribution: '© OpenStreetMap contributors',
      readiness: TileSourceReadiness.devOnly,
      maxNativeZoom: 19,
    ),
    TileSource(
      id: 'opentopo',
      label: 'OpenTopoMap',
      urlTemplate: 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
      attribution: '© OpenStreetMap contributors, SRTM | style: © OpenTopoMap (CC-BY-SA)',
      readiness: TileSourceReadiness.devOnly,
      maxNativeZoom: 18,
    ),
    TileSource(
      id: 'carto_light',
      label: 'CARTO Light',
      urlTemplate: 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
      attribution: '© OpenStreetMap contributors © CARTO',
      readiness: TileSourceReadiness.needsKey,
      maxNativeZoom: 21,
    ),
    TileSource(
      id: 'carto_voyager',
      label: 'CARTO Voyager',
      urlTemplate: 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
      attribution: '© OpenStreetMap contributors © CARTO',
      readiness: TileSourceReadiness.needsKey,
      maxNativeZoom: 21,
    ),
  ];

  final Map<String, TileSource> sources;

  const TileSourceRegistry(this.sources);

  factory TileSourceRegistry.defaults() =>
      TileSourceRegistry({for (final s in defaultSources) s.id: s});

  /// Merge server-reported readiness (`{id: {readiness: 'dev_only'|...}}`)
  /// into the embedded catalog — the server decides what may be saved.
  TileSourceRegistry withServerReadiness(Map<String, dynamic>? serverSources) {
    if (serverSources == null) return this;
    final merged = Map<String, TileSource>.of(sources);
    serverSources.forEach((id, meta) {
      final existing = merged[id];
      final readiness = switch (meta is Map ? meta['readiness'] : null) {
        'ready' => TileSourceReadiness.ready,
        'dev_only' => TileSourceReadiness.devOnly,
        'needs_key' => TileSourceReadiness.needsKey,
        _ => null,
      };
      if (existing != null && readiness != null) {
        merged[id] = TileSource(
          id: existing.id,
          label: existing.label,
          urlTemplate: existing.urlTemplate,
          attribution: existing.attribution,
          readiness: readiness,
          maxNativeZoom: existing.maxNativeZoom,
        );
      }
    });
    return TileSourceRegistry(merged);
  }

  TileSource? operator [](String? id) => id == null ? null : sources[id];
}

/// An optional external data layer for the incident map (Phase 24 —
/// VIDEO_SYSTEM_PLAN.md §24.9). The `features.<id>` gate in the config
/// document controls availability; [readiness] (server-canonical) decides
/// where the layer may be switched on. Reuses [TileSourceReadiness] —
/// the vocabulary is identical by design (§24.2).
class MapLayer {
  final String id;
  final String label;

  /// 'points' | 'raster_tile' | 'polygon' | 'polyline'
  final String type;
  final int minZoom;
  final int maxPoints;
  final int cacheTtlSec;
  final int staleAfterSec;
  final String source;
  final String attribution;
  final TileSourceReadiness readiness;

  const MapLayer({
    required this.id,
    required this.label,
    required this.type,
    this.minZoom = 0,
    this.maxPoints = 0,
    this.cacheTtlSec = 0,
    this.staleAfterSec = 0,
    this.source = '',
    this.attribution = '',
    required this.readiness,
  });

  /// needs_key layers cannot be enabled until the server deploys the
  /// credential/license/data asset — the switch stays off everywhere.
  bool get selectable => readiness != TileSourceReadiness.needsKey;

  /// dev_only/needs_key layers stay off in prod (the server also rejects
  /// the save with HTTP 422 — this mirrors it for the admin UI).
  bool prodBlocked(String environment) =>
      readiness != TileSourceReadiness.ready && environment == 'prod';

  factory MapLayer.fromJson(String id, Map<String, dynamic> json) => MapLayer(
        id: id,
        label: json['label'] as String? ?? id,
        type: json['type'] as String? ?? 'points',
        minZoom: (json['minZoom'] as num?)?.toInt() ?? 0,
        maxPoints: (json['maxPoints'] as num?)?.toInt() ?? 0,
        cacheTtlSec: (json['cacheTtlSec'] as num?)?.toInt() ?? 0,
        staleAfterSec: (json['staleAfterSec'] as num?)?.toInt() ?? 0,
        source: json['source'] as String? ?? '',
        attribution: json['attribution'] as String? ?? '',
        // Unknown readiness defaults to the most restrictive state.
        readiness: switch (json['readiness']) {
          'ready' => TileSourceReadiness.ready,
          'dev_only' => TileSourceReadiness.devOnly,
          _ => TileSourceReadiness.needsKey,
        },
      );
}

/// Client-side mirror of MAP_LAYERS in websocket-server/routes/map-config.js
/// — keep ids and readiness in sync. The embedded catalog backs the
/// app-default snapshot; the server's `mapLayers` payload replaces it
/// entirely at load time (server is canonical — newer layer kinds unknown
/// to this client still parse so they get a toggle).
class MapLayerRegistry {
  static const defaultLayers = <MapLayer>[
    MapLayer(
      id: 'rain',
      label: 'ปริมาณฝน 24 ชม.',
      type: 'points',
      minZoom: 6,
      maxPoints: 400,
      cacheTtlSec: 900,
      staleAfterSec: 86400,
      source: 'Thaiwater (HII)',
      attribution: 'ข้อมูล สสนก. (Thaiwater)',
      readiness: TileSourceReadiness.devOnly,
    ),
    MapLayer(
      id: 'waterLevel',
      label: 'ระดับน้ำ (Thaiwater)',
      type: 'points',
      minZoom: 6,
      maxPoints: 400,
      cacheTtlSec: 900,
      staleAfterSec: 43200,
      source: 'Thaiwater (HII)',
      attribution: 'ข้อมูล สสนก. (Thaiwater)',
      readiness: TileSourceReadiness.devOnly,
    ),
    MapLayer(
      id: 'dam',
      label: 'เขื่อน/อ่างเก็บน้ำ',
      type: 'points',
      minZoom: 5,
      maxPoints: 100,
      cacheTtlSec: 3600,
      staleAfterSec: 604800,
      source: 'Thaiwater (HII)',
      attribution: 'ข้อมูล สสนก. (Thaiwater)',
      readiness: TileSourceReadiness.devOnly,
    ),
    MapLayer(
      id: 'ews',
      label: 'สถานีเตือนภัย (DWR EWS)',
      type: 'points',
      minZoom: 7,
      maxPoints: 300,
      cacheTtlSec: 600,
      staleAfterSec: 7200,
      source: 'DWR',
      attribution: 'กรมชลประทาน (DWR)',
      readiness: TileSourceReadiness.needsKey,
    ),
    MapLayer(
      id: 'radar',
      label: 'เรดาร์ฝน (RainViewer)',
      type: 'raster_tile',
      minZoom: 4,
      cacheTtlSec: 600,
      staleAfterSec: 3600,
      source: 'RainViewer',
      attribution: 'RainViewer',
      readiness: TileSourceReadiness.devOnly,
    ),
    MapLayer(
      id: 'forecast',
      label: 'พยากรณ์รายจุด',
      type: 'points',
      minZoom: 6,
      maxPoints: 300,
      cacheTtlSec: 1800,
      staleAfterSec: 21600,
      source: 'Open-Meteo',
      attribution: 'Open-Meteo',
      readiness: TileSourceReadiness.devOnly,
    ),
    MapLayer(
      id: 'province',
      label: 'ขอบเขตจังหวัด',
      type: 'polygon',
      minZoom: 5,
      cacheTtlSec: 86400,
      staleAfterSec: 2592000,
      source: 'official GeoJSON (pending)',
      readiness: TileSourceReadiness.needsKey,
    ),
    MapLayer(
      id: 'floodRoute',
      label: 'เส้นทางลุ่มน้ำ',
      type: 'polyline',
      minZoom: 8,
      cacheTtlSec: 3600,
      staleAfterSec: 86400,
      source: 'official dataset (pending)',
      readiness: TileSourceReadiness.needsKey,
    ),
  ];

  final Map<String, MapLayer> layers;

  const MapLayerRegistry(this.layers);

  factory MapLayerRegistry.defaults() =>
      MapLayerRegistry({for (final l in defaultLayers) l.id: l});

  /// Parse the server's `mapLayers` payload. Absent → embedded defaults
  /// (older server); present → the server is canonical.
  factory MapLayerRegistry.fromServer(Map<String, dynamic>? serverLayers) {
    if (serverLayers == null) return MapLayerRegistry.defaults();
    return MapLayerRegistry({
      for (final e in serverLayers.entries)
        if (e.value is Map)
          e.key.toString(): MapLayer.fromJson(
            e.key.toString(),
            Map<String, dynamic>.from(e.value as Map),
          ),
    });
  }

  MapLayer? operator [](String? id) => id == null ? null : layers[id];
}

/// The full config document (§5.1) plus server-managed metadata.
class MapProviderConfig {
  final int revision;
  final String environment; // dev | staging | prod
  final Map<MapPlatform, MapTarget> platformDefaults;
  final Map<MapFeature, FeatureOverride> featureOverrides;
  final ServiceConfig services;
  final FallbackConfig fallback;
  final RateConfig rateConfig;

  /// Server-driven UI feature gate (VIDEO_SYSTEM_PLAN.md §22.6): shows the
  /// per-category "แผนที่เกิดเหตุ" entry in the trending filter sheet.
  /// Absent/false = hidden (safe default — §4.9).
  final bool incidentOverviewMapEnabled;

  /// Raw passthrough of every `features.*` gate other than
  /// `incidentOverviewMap` — Phase 24 layer gates (`rain`, `waterLevel`, …)
  /// plus unknown gates written by newer servers. Verbatim round-trip is
  /// mandatory (§24.A): a client that dropped unknown gates would delete
  /// them on every save. Entries keep the full gate object, not just
  /// `enabled`, so sibling fields survive too.
  final Map<String, Map<String, dynamic>> extraFeatureGates;

  const MapProviderConfig({
    required this.revision,
    required this.environment,
    required this.platformDefaults,
    required this.featureOverrides,
    required this.services,
    required this.fallback,
    required this.rateConfig,
    this.incidentOverviewMapEnabled = false,
    this.extraFeatureGates = const {},
  });

  /// Environment default embedded in the app — used when the server config
  /// cannot be loaded (§4.9: safe default, never a fake success).
  factory MapProviderConfig.appDefault() => const MapProviderConfig(
        revision: 0,
        environment: 'dev',
        platformDefaults: {
          MapPlatform.web: MapTarget(enabled: false, renderer: MapRendererKind.google),
          MapPlatform.ios: MapTarget(enabled: true, renderer: MapRendererKind.google),
          MapPlatform.android: MapTarget(enabled: true, renderer: MapRendererKind.google),
        },
        featureOverrides: {},
        services: ServiceConfig(),
        fallback: FallbackConfig(),
        rateConfig: RateConfig(),
      );

  factory MapProviderConfig.fromJson(Map<String, dynamic> json) {
    final config = (json['config'] is Map<String, dynamic>)
        ? json['config'] as Map<String, dynamic>
        : json; // tolerate bare config docs
    final pd = config['platformDefaults'];
    final fo = config['featureOverrides'];
    final features = config['features'];
    final incidentGate =
        (features is Map && features['incidentOverviewMap'] is Map)
            ? (features['incidentOverviewMap'] as Map)['enabled']
            : null;
    final extraGates = <String, Map<String, dynamic>>{};
    if (features is Map) {
      for (final e in features.entries) {
        final name = e.key.toString();
        if (name == 'incidentOverviewMap') continue;
        if (e.value is Map) {
          extraGates[name] = Map<String, dynamic>.from(e.value as Map);
        }
      }
    }
    return MapProviderConfig(
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      environment: json['environment'] as String? ?? 'dev',
      incidentOverviewMapEnabled: incidentGate == true,
      extraFeatureGates: extraGates,
      platformDefaults: {
        for (final p in MapPlatform.values)
          p: MapTarget.fromJson(
            (pd is Map && pd[p.key] is Map)
                ? Map<String, dynamic>.from(pd[p.key] as Map)
                : const {'enabled': false, 'renderer': 'google'},
          ),
      },
      featureOverrides: {
        if (fo is Map)
          for (final entry in fo.entries)
            if (MapFeatureKey.fromKey(entry.key.toString()) != null)
              MapFeatureKey.fromKey(entry.key.toString())!: FeatureOverride.fromJson(
                entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : null,
              ),
      },
      services: ServiceConfig.fromJson(
        config['services'] is Map ? Map<String, dynamic>.from(config['services'] as Map) : null,
      ),
      fallback: FallbackConfig.fromJson(
        config['fallback'] is Map ? Map<String, dynamic>.from(config['fallback'] as Map) : null,
      ),
      rateConfig: RateConfig.fromJson(
        config['rateConfig'] is Map ? Map<String, dynamic>.from(config['rateConfig'] as Map) : null,
      ),
    );
  }

  /// Document sent to PUT /api/admin/map-config (metadata stays server-side).
  Map<String, dynamic> toConfigJson() => {
        'platformDefaults': {for (final e in platformDefaults.entries) e.key.key: e.value.toJson()},
        'featureOverrides': {
          for (final e in featureOverrides.entries)
            if (e.value.isOverride) e.key.key: e.value.toJson()!,
        },
        'services': services.toJson(),
        'fallback': fallback.toJson(),
        'rateConfig': rateConfig.toJson(),
        'features': {
          'incidentOverviewMap': {'enabled': incidentOverviewMapEnabled},
          ...extraFeatureGates,
        },
      };

  /// Dirty check: compares config payload only (revision/env excluded).
  bool isSameConfig(MapProviderConfig other) =>
      jsonEncode(toConfigJson()) == jsonEncode(other.toConfigJson());

  MapProviderConfig copyWith({
    int? revision,
    String? environment,
    Map<MapPlatform, MapTarget>? platformDefaults,
    Map<MapFeature, FeatureOverride>? featureOverrides,
    ServiceConfig? services,
    FallbackConfig? fallback,
    RateConfig? rateConfig,
    bool? incidentOverviewMapEnabled,
    Map<String, Map<String, dynamic>>? extraFeatureGates,
  }) =>
      MapProviderConfig(
        revision: revision ?? this.revision,
        environment: environment ?? this.environment,
        platformDefaults: platformDefaults ?? this.platformDefaults,
        featureOverrides: featureOverrides ?? this.featureOverrides,
        services: services ?? this.services,
        fallback: fallback ?? this.fallback,
        rateConfig: rateConfig ?? this.rateConfig,
        incidentOverviewMapEnabled:
            incidentOverviewMapEnabled ?? this.incidentOverviewMapEnabled,
        extraFeatureGates: extraFeatureGates ?? this.extraFeatureGates,
      );

  /// Read a `features.*` gate — [incidentOverviewMapEnabled] for the
  /// incident-map gate, [extraFeatureGates] otherwise. Absent = off.
  bool featureGateEnabled(String name) => name == 'incidentOverviewMap'
      ? incidentOverviewMapEnabled
      : extraFeatureGates[name]?['enabled'] == true;

  /// Toggle a `features.*` gate, preserving sibling fields on the gate
  /// object (e.g. `{'enabled': true, 'note': '…'}` keeps `note`).
  MapProviderConfig withFeatureGate(String name, bool enabled) {
    if (name == 'incidentOverviewMap') {
      return copyWith(incidentOverviewMapEnabled: enabled);
    }
    return copyWith(extraFeatureGates: {
      ...extraFeatureGates,
      name: {...?extraFeatureGates[name], 'enabled': enabled},
    });
  }

  /// Resolve the effective target for [feature] on [platform]:
  /// feature override → platform default (§5.1). `yieldWay` callers must pass
  /// [MapFeature.emergency] — yield way cannot be overridden independently.
  MapTarget resolveTarget(MapFeature feature, MapPlatform platform) {
    final platformDefault =
        platformDefaults[platform] ?? const MapTarget(enabled: false, renderer: MapRendererKind.google);
    final override = featureOverrides[feature];
    if (override == null || !override.isOverride) return platformDefault;
    return MapTarget(
      enabled: platformDefault.enabled,
      renderer: override.renderer,
      tileSourceId: override.tileSourceId,
    );
  }

  /// Client-side validation mirroring the server (§4.5). The server is
  /// authoritative — this exists to surface errors before the round trip.
  MapConfigValidation validate(TileSourceRegistry registry) {
    final errors = <String>[];
    final warnings = <String>[];

    for (final e in platformDefaults.entries) {
      _validateTarget(e.value, 'platformDefaults.${e.key.key}', registry, errors, warnings);
    }

    final web = platformDefaults[MapPlatform.web];
    if (web != null && web.enabled && web.renderer == MapRendererKind.google) {
      warnings.add('เปิด Google บน Web ต้องมี key และงบที่อนุมัติ (ต้องยืนยันตอนบันทึก)');
    }

    for (final e in featureOverrides.entries) {
      final o = e.value;
      if (!o.isOverride) continue;
      _validateTarget(
        MapTarget(enabled: true, renderer: o.renderer, tileSourceId: o.tileSourceId),
        'featureOverrides.${e.key.key}',
        registry,
        errors,
        warnings,
      );
    }

    final usesOsm = platformDefaults.values.any((t) => t.renderer == MapRendererKind.osm) ||
        featureOverrides.values.any((o) => o.isOverride && o.renderer == MapRendererKind.osm);
    if (usesOsm && services.trafficProvider == 'google') {
      warnings.add('เลือก OSM — ต้องยืนยันว่าแผนที่ไม่มีข้อมูลจราจรแบบเรียลไทม์');
    }

    if (fallback.enabled && fallback.providerId == null) {
      errors.add('fallback: ต้องเลือก provider เมื่อเปิดใช้งาน');
    }

    if (environment == 'prod') {
      warnings.add('การบันทึกบน production ต้องระบุเหตุผล');
    }

    return MapConfigValidation(errors: errors, warnings: warnings, usesOsm: usesOsm);
  }

  void _validateTarget(
    MapTarget t,
    String path,
    TileSourceRegistry registry,
    List<String> errors,
    List<String> warnings,
  ) {
    if (t.renderer == MapRendererKind.osm) {
      final src = registry[t.tileSourceId];
      if (t.tileSourceId == null || t.tileSourceId!.isEmpty) {
        errors.add('$path: ต้องเลือก tile source เมื่อใช้ OSM');
      } else if (src == null) {
        errors.add('$path: ไม่รู้จัก tile source \'${t.tileSourceId}\'');
      } else if (src.readiness == TileSourceReadiness.needsKey) {
        errors.add('$path: \'${src.label}\' ต้องมี API key (ยังไม่ได้ตั้งค่า)');
      } else if (src.readiness == TileSourceReadiness.devOnly && environment == 'prod') {
        errors.add('$path: \'${src.label}\' ใช้ได้เฉพาะ dev/staging เท่านั้น');
      }
    }
  }
}

class MapConfigValidation {
  final List<String> errors;
  final List<String> warnings;

  /// True when any resolved target uses OSM — drives the save-time
  /// "no realtime traffic" acknowledgement required by the server.
  final bool usesOsm;

  MapConfigValidation({required this.errors, required this.warnings, this.usesOsm = false});

  bool get isValid => errors.isEmpty;
}
