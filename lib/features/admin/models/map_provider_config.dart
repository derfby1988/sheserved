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

  const TileSource({
    required this.id,
    required this.label,
    required this.urlTemplate,
    required this.attribution,
    required this.readiness,
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
    ),
    TileSource(
      id: 'opentopo',
      label: 'OpenTopoMap',
      urlTemplate: 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
      attribution: '© OpenStreetMap contributors, SRTM | style: © OpenTopoMap (CC-BY-SA)',
      readiness: TileSourceReadiness.devOnly,
    ),
    TileSource(
      id: 'carto_light',
      label: 'CARTO Light',
      urlTemplate: 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
      attribution: '© OpenStreetMap contributors © CARTO',
      readiness: TileSourceReadiness.needsKey,
    ),
    TileSource(
      id: 'carto_voyager',
      label: 'CARTO Voyager',
      urlTemplate: 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
      attribution: '© OpenStreetMap contributors © CARTO',
      readiness: TileSourceReadiness.needsKey,
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
        );
      }
    });
    return TileSourceRegistry(merged);
  }

  TileSource? operator [](String? id) => id == null ? null : sources[id];
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

  const MapProviderConfig({
    required this.revision,
    required this.environment,
    required this.platformDefaults,
    required this.featureOverrides,
    required this.services,
    required this.fallback,
    required this.rateConfig,
    this.incidentOverviewMapEnabled = false,
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
    return MapProviderConfig(
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      environment: json['environment'] as String? ?? 'dev',
      incidentOverviewMapEnabled: incidentGate == true,
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
      );

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
