import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/admin/models/map_provider_config.dart';

MapProviderConfig seedConfig({int revision = 3, String env = 'dev'}) =>
    MapProviderConfig.fromJson({
      'revision': revision,
      'environment': env,
      'config': {
        'platformDefaults': {
          'web': {'enabled': false, 'renderer': 'google', 'tileSourceId': null},
          'ios': {'enabled': true, 'renderer': 'google', 'tileSourceId': null},
          'android': {'enabled': true, 'renderer': 'google', 'tileSourceId': null},
        },
        'featureOverrides': {},
        'services': {
          'routing': {'provider': 'google_directions', 'enabled': true},
          'search': {'primary': 'nominatim', 'fallbackEnabled': true},
          'traffic': {'provider': 'google'},
        },
        'fallback': {'enabled': false, 'providerId': null},
        'rateConfig': {
          'googleWebMapPerThousand': 7,
          'googleDirectionsPerThousand': 5,
          'googlePlacesPerThousand': 17,
        },
      },
    });

void main() {
  group('MapProviderConfig.fromJson', () {
    test('parses revision, environment and all three platforms', () {
      final c = seedConfig();
      expect(c.revision, 3);
      expect(c.environment, 'dev');
      expect(c.platformDefaults.keys, containsAll(MapPlatform.values));
      expect(c.platformDefaults[MapPlatform.ios]!.enabled, isTrue);
      expect(c.platformDefaults[MapPlatform.web]!.enabled, isFalse);
    });

    test('unknown feature keys are dropped, not fatal', () {
      final c = MapProviderConfig.fromJson({
        'revision': 1,
        'environment': 'dev',
        'config': {
          'featureOverrides': {
            'future_feature': {'mode': 'override', 'renderer': 'osm'},
            'yield_way': {'mode': 'override', 'renderer': 'osm'},
          },
        },
      });
      // yield_way key never materializes as an override entry.
      expect(c.featureOverrides.keys, isNot(contains('yield_way')));
      expect(c.featureOverrides, isEmpty);
    });

    test('missing platform falls back to disabled google', () {
      final c = MapProviderConfig.fromJson({
        'revision': 1,
        'environment': 'dev',
        'config': {
          'platformDefaults': {
            'ios': {'enabled': true, 'renderer': 'google'},
          },
        },
      });
      expect(c.platformDefaults[MapPlatform.web]!.enabled, isFalse);
      expect(c.platformDefaults[MapPlatform.android]!.renderer, MapRendererKind.google);
    });
  });

  group('resolveTarget — feature override → platform default', () {
    test('inherit uses the platform default', () {
      final c = seedConfig();
      final t = c.resolveTarget(MapFeature.home, MapPlatform.ios);
      expect(t.renderer, MapRendererKind.google);
      expect(t.enabled, isTrue);
    });

    test('feature override wins over platform default', () {
      var c = seedConfig();
      c = c.copyWith(featureOverrides: {
        MapFeature.groupCreate: const FeatureOverride.override(
          renderer: MapRendererKind.osm,
          tileSourceId: 'osm_standard',
        ),
      });
      final t = c.resolveTarget(MapFeature.groupCreate, MapPlatform.ios);
      expect(t.renderer, MapRendererKind.osm);
      expect(t.tileSourceId, 'osm_standard');
      // enabled still comes from the platform.
      expect(t.enabled, isTrue);
    });

    test('override on web keeps platform enabled=false', () {
      var c = seedConfig();
      c = c.copyWith(featureOverrides: {
        MapFeature.home: const FeatureOverride.override(
          renderer: MapRendererKind.osm,
          tileSourceId: 'osm_standard',
        ),
      });
      expect(c.resolveTarget(MapFeature.home, MapPlatform.web).enabled, isFalse);
    });
  });

  group('toConfigJson round-trip + dirty check', () {
    test('toConfigJson omits inherit overrides and metadata', () {
      final c = seedConfig().copyWith(featureOverrides: const {
        MapFeature.home: FeatureOverride.inherit(),
      });
      final json = c.toConfigJson();
      expect((json['featureOverrides'] as Map).containsKey('home'), isFalse);
      expect(json.containsKey('revision'), isFalse);
    });

    test('isSameConfig ignores revision but catches payload edits', () {
      final a = seedConfig(revision: 1);
      final b = seedConfig(revision: 9);
      expect(a.isSameConfig(b), isTrue);
      final c = b.copyWith(platformDefaults: {
        ...b.platformDefaults,
        MapPlatform.web: const MapTarget(enabled: true, renderer: MapRendererKind.google),
      });
      expect(a.isSameConfig(c), isFalse);
    });
  });

  group('validate', () {
    test('google-only config is valid', () {
      final v = seedConfig().validate(TileSourceRegistry.defaults());
      expect(v.isValid, isTrue);
      expect(v.usesOsm, isFalse);
    });

    test('osm without tileSourceId is an error', () {
      var c = seedConfig();
      c = c.copyWith(platformDefaults: {
        ...c.platformDefaults,
        MapPlatform.ios: const MapTarget(enabled: true, renderer: MapRendererKind.osm),
      });
      final v = c.validate(TileSourceRegistry.defaults());
      expect(v.isValid, isFalse);
      expect(v.errors.join(' '), contains('tile source'));
    });

    test('needsKey tile source cannot be saved', () {
      var c = seedConfig();
      c = c.copyWith(platformDefaults: {
        ...c.platformDefaults,
        MapPlatform.ios: const MapTarget(
          enabled: true,
          renderer: MapRendererKind.osm,
          tileSourceId: 'carto_light',
        ),
      });
      final v = c.validate(TileSourceRegistry.defaults());
      expect(v.isValid, isFalse);
      expect(v.errors.join(' '), contains('API key'));
    });

    test('devOnly tile source blocked in prod', () {
      var c = seedConfig(env: 'prod');
      c = c.copyWith(platformDefaults: {
        ...c.platformDefaults,
        MapPlatform.ios: const MapTarget(
          enabled: true,
          renderer: MapRendererKind.osm,
          tileSourceId: 'osm_standard',
        ),
      });
      final v = c.validate(TileSourceRegistry.defaults());
      expect(v.isValid, isFalse);
      expect(v.errors.join(' '), contains('dev/staging'));
    });

    test('osm usage flags usesOsm for the traffic acknowledgement', () {
      var c = seedConfig();
      c = c.copyWith(platformDefaults: {
        ...c.platformDefaults,
        MapPlatform.ios: const MapTarget(
          enabled: true,
          renderer: MapRendererKind.osm,
          tileSourceId: 'osm_standard',
        ),
      });
      expect(c.validate(TileSourceRegistry.defaults()).usesOsm, isTrue);
    });
  });

  group('TileSourceRegistry', () {
    test('server readiness overrides embedded defaults', () {
      final r = TileSourceRegistry.defaults().withServerReadiness({
        'carto_light': {'readiness': 'ready'},
      });
      expect(r['carto_light']!.readiness, TileSourceReadiness.ready);
      expect(r['carto_light']!.selectable, isTrue);
      // Unknown server ids do not create phantom sources.
      expect(r['ghost'], isNull);
    });
  });

  group('feature gates passthrough (Phase 24.A)', () {
    test('unknown + layer gates round-trip verbatim', () {
      final c = MapProviderConfig.fromJson({
        'revision': 3,
        'environment': 'dev',
        'config': {
          'features': {
            'incidentOverviewMap': {'enabled': false},
            'rain': {'enabled': true},
            'futureGate': {'enabled': true, 'note': 'keep me'},
          },
        },
      });
      expect(c.featureGateEnabled('rain'), isTrue);
      expect(c.featureGateEnabled('futureGate'), isTrue);
      final out = c.toConfigJson()['features'] as Map<String, dynamic>;
      expect((out['incidentOverviewMap'] as Map)['enabled'], isFalse);
      expect((out['rain'] as Map)['enabled'], isTrue);
      // Sibling fields on the gate object survive the round trip.
      expect(out['futureGate'], {'enabled': true, 'note': 'keep me'});
    });

    test('withFeatureGate toggles a layer flag without dropping siblings', () {
      var c = seedConfig()
          .withFeatureGate('rain', true)
          .withFeatureGate('dam', true);
      c = c.withFeatureGate('rain', false);
      final features = c.toConfigJson()['features'] as Map<String, dynamic>;
      expect((features['rain'] as Map)['enabled'], isFalse);
      expect((features['dam'] as Map)['enabled'], isTrue);
    });

    test('withFeatureGate routes incidentOverviewMap to the typed field', () {
      final c = seedConfig().withFeatureGate('incidentOverviewMap', true);
      expect(c.incidentOverviewMapEnabled, isTrue);
      expect(c.extraFeatureGates.containsKey('incidentOverviewMap'), isFalse);
    });

    test('toggling a layer gate makes the config dirty', () {
      final a = seedConfig();
      final b = a.withFeatureGate('rain', true);
      expect(a.isSameConfig(b), isFalse);
    });
  });

  group('MapLayerRegistry', () {
    test('defaults mirror the server MAP_LAYERS ids', () {
      final r = MapLayerRegistry.defaults();
      expect(
        r.layers.keys,
        containsAll([
          'rain',
          'waterLevel',
          'dam',
          'ews',
          'radar',
          'forecast',
          'province',
          'floodRoute',
        ]),
      );
      expect(r['ews']!.selectable, isFalse);
      expect(r['rain']!.prodBlocked('prod'), isTrue);
      expect(r['rain']!.prodBlocked('dev'), isFalse);
    });

    test('fromServer parses entries and keeps kinds unknown to the client', () {
      final r = MapLayerRegistry.fromServer({
        'rain': {'readiness': 'ready', 'label': 'Rain', 'type': 'points'},
        'newKind': {'readiness': 'dev_only', 'label': 'New', 'type': 'points'},
      });
      expect(r['rain']!.readiness, TileSourceReadiness.ready);
      expect(r['newKind'], isNotNull);
      // Server canonical — kinds the server removed do not come back.
      expect(r['dam'], isNull);
    });

    test('fromServer(null) falls back to embedded defaults', () {
      expect(MapLayerRegistry.fromServer(null).layers, isNotEmpty);
    });
  });
}
