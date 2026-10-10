import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sheserved/features/admin/presentation/widgets/map_provider_settings_section.dart';
import 'package:sheserved/services/map_config_service.dart';

Map<String, dynamic> _configDoc() => {
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
    };

/// Mirrors the server's MAP_LAYERS payload (routes/map-config.js).
Map<String, dynamic> _mapLayersPayload() => {
      'rain': {
        'readiness': 'dev_only',
        'type': 'points',
        'label': 'ปริมาณฝน 24 ชม.',
        'source': 'Thaiwater (HII)',
      },
      'waterLevel': {
        'readiness': 'dev_only',
        'type': 'points',
        'label': 'ระดับน้ำ',
        'source': 'Thaiwater (HII)',
      },
      'ews': {
        'readiness': 'needs_key',
        'type': 'points',
        'label': 'สถานีเตือนภัย (DWR EWS)',
        'source': 'DWR',
      },
    };

Map<String, dynamic> _adminPayload({int revision = 3}) => {
      'revision': revision,
      'environment': 'dev',
      'config': _configDoc(),
      'updatedAt': '2026-10-06T05:00:00Z',
      'updatedBy': 'u-admin',
      'reason': 'seed',
      'tileSources': {
        'osm_standard': {'readiness': 'dev_only'},
        'opentopo': {'readiness': 'dev_only'},
        'carto_light': {'readiness': 'needs_key'},
        'carto_voyager': {'readiness': 'needs_key'},
      },
      'mapLayers': _mapLayersPayload(),
    };

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// Routes fake requests by path. [putStatus] controls the save outcome.
class _FakeBackend {
  _FakeBackend({
    this.putStatus = 200,
    this.publicStatus = 200,
    this.adminStatus = 200,
    this.putUnreachable = false,
  });

  int putStatus;
  final int publicStatus;
  final int adminStatus;
  final bool putUnreachable;
  final List<Map<String, dynamic>> puts = [];

  Future<http.Response> request(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    Map<String, dynamic>? queryParams,
  }) async {
    if (path == '/api/admin/map-config' && method == 'GET') {
      if (adminStatus != 200) return _json(adminStatus, {'error': 'down'});
      return _json(200, _adminPayload());
    }
    if (path == '/api/admin/map-config' && method == 'PUT') {
      if (putUnreachable) throw http.ClientException('connection refused');
      puts.add(jsonDecode(body as String) as Map<String, dynamic>);
      switch (putStatus) {
        case 200:
          return _json(200, {
            'message': 'saved',
            'warnings': [],
            'data': {
              'revision': 4,
              'environment': 'dev',
              'config': _configDoc(),
              'updatedAt': '2026-10-06T05:10:00Z',
            },
          });
        case 409:
          return _json(409, {'error': 'conflict', 'currentRevision': 7});
        case 422:
          return _json(422, {
            'error': 'Validation failed',
            'details': ['tileSourceId: dev-only source not allowed in prod'],
          });
      }
    }
    if (path == '/api/admin/map-config/history') {
      return _json(200, {
        'items': [
          {
            // bigint id arrives as a string from node-postgres (real API).
            'id': '9',
            'revision': 2,
            'environment': 'dev',
            'old_config': null,
            'new_config': _configDoc(),
            'reason': 'try osm',
            'actor': 'u-admin',
            'created_at': '2026-10-05T10:00:00Z',
          }
        ],
      });
    }
    return _json(404, {'error': 'not found'});
  }

  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) async {
    if (uri.path.endsWith('/api/map-config')) {
      return publicStatus == 200
          ? _json(200, {
              'revision': 3,
              'environment': 'dev',
              'config': _configDoc(),
              'updatedAt': '2026-10-06T05:00:00Z',
            })
          : _json(publicStatus, {'error': 'down'});
    }
    return _json(404, {'error': 'not found'});
  }
}

MapConfigService _service(_FakeBackend backend) => MapConfigService(
      baseUrl: 'http://test.local',
      request: backend.request,
      get: backend.get,
    );

Future<void> _pumpSection(
  WidgetTester tester,
  _FakeBackend backend,
) async {
  await tester.binding.setSurfaceSize(const Size(1280, 2400));
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MapProviderSettingsSection(service: _service(backend)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads config and renders all sections without save bar', (tester) async {
    final backend = _FakeBackend();
    await _pumpSection(tester, backend);

    expect(find.text('ผู้ให้บริการแผนที่ (Map Provider)'), findsOneWidget);
    expect(find.text('ค่าเริ่มต้นตามแพลตฟอร์ม'), findsOneWidget);
    expect(find.text('การตั้งค่าเฉพาะระบบ'), findsOneWidget);
    expect(find.text('ค่าที่จะใช้จริง (Preview)'), findsOneWidget);
    expect(find.text('ประวัติการตั้งค่า'), findsOneWidget);
    expect(find.text('rev 3'), findsOneWidget);
    // Not dirty → no save bar.
    expect(find.text('บันทึกการตั้งค่า'), findsNothing);
    // History loaded → rollback button.
    expect(find.text('ย้อนกลับ'), findsOneWidget);
  });

  testWidgets('server down → app-default banner, no fake success', (tester) async {
    final backend = _FakeBackend(publicStatus: 500, adminStatus: 500);
    await _pumpSection(tester, backend);
    expect(find.textContaining('เชื่อมต่อ server ไม่ได้'), findsOneWidget);
  });

  testWidgets('enabling web makes it dirty; save asks Google budget confirmation', (tester) async {
    final backend = _FakeBackend();
    await _pumpSection(tester, backend);

    // Flip the Web platform switch (first Switch in the platform cards).
    final webSwitch = find.byWidgetPredicate(
      (w) => w is Switch && w.value == false,
    );
    expect(webSwitch, findsWidgets);
    await tester.tap(webSwitch.first);
    await tester.pumpAndSettle();

    // Dirty → save bar appears.
    expect(find.text('บันทึกการตั้งค่า'), findsOneWidget);

    // §22.10 gate card ทำให้เนื้อหาสูงขึ้น — scroll ให้ปุ่มบันทึกมองเห็นก่อน
    await tester.ensureVisible(find.text('บันทึกการตั้งค่า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึกการตั้งค่า'));
    await tester.pumpAndSettle();

    // Google-on-web requires ticking the budget acknowledgement.
    expect(find.textContaining('ยืนยันว่ามี Google key'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึก').last);
    await tester.pumpAndSettle();

    // PUT issued with the confirmation flag and correct expectedRevision.
    expect(backend.puts, hasLength(1));
    expect(backend.puts[0]['expectedRevision'], 3);
    expect((backend.puts[0]['confirmations'] as Map)['googleWebBudget'], isTrue);
    expect(find.text('บันทึกการตั้งค่าแล้ว'), findsOneWidget);
  });

  testWidgets('409 surfaces conflict banner instead of overwriting', (tester) async {
    final backend = _FakeBackend(putStatus: 409);
    await _pumpSection(tester, backend);

    await tester.tap(
      find.byWidgetPredicate((w) => w is Switch && w.value == false).first,
    );
    await tester.pumpAndSettle();
    // §22.10 gate card ทำให้เนื้อหาสูงขึ้น — scroll ให้ปุ่มบันทึกมองเห็นก่อน
    await tester.ensureVisible(find.text('บันทึกการตั้งค่า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึกการตั้งค่า'));
    await tester.pumpAndSettle();
    // Confirm dialog (googleWebBudget) must be accepted before the PUT.
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึก').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('มีการบันทึกจากผู้ใช้อื่น'), findsOneWidget);
    expect(find.text('โหลดใหม่'), findsOneWidget);
  });

  for (final (size, scale, name) in [
    (const Size(320, 568), 1.3, 'compact web 320x568 + text scale 1.3'),
    (const Size(393, 852), 1.0, 'mobile web 393x852'),
    (const Size(1280, 800), 1.0, 'desktop web 1280x800'),
  ]) {
    testWidgets('$name renders without overflow', (tester) async {
      final backend = _FakeBackend();
      await tester.binding.setSurfaceSize(size);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: MapProviderSettingsSection(service: _service(backend)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ผู้ให้บริการแผนที่ (Map Provider)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('422 shows server validation errors inline and keeps draft', (tester) async {
    final backend = _FakeBackend(putStatus: 422);
    await _pumpSection(tester, backend);

    await tester.tap(
      find.byWidgetPredicate((w) => w is Switch && w.value == false).first,
    );
    await tester.pumpAndSettle();
    // §22.10 gate card ทำให้เนื้อหาสูงขึ้น — scroll ให้ปุ่มบันทึกมองเห็นก่อน
    await tester.ensureVisible(find.text('บันทึกการตั้งค่า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึกการตั้งค่า'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึก').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('dev-only source not allowed'), findsOneWidget);
    // Draft not reset → save bar still present.
    expect(find.text('บันทึกการตั้งค่า'), findsOneWidget);
  });

  testWidgets('server down → app-default snapshot disables save (no fake saved state)',
      (tester) async {
    final backend = _FakeBackend(publicStatus: 500, adminStatus: 500, putUnreachable: true);
    await _pumpSection(tester, backend);

    await tester.tap(
      find.byWidgetPredicate((w) => w is Switch && w.value == false).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('บันทึกการตั้งค่า'));
    await tester.pumpAndSettle();

    // §24.A — writing the embedded default would fabricate a revision the
    // server never produced, so the button must be disabled, not just fail.
    final saveButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('บันทึกการตั้งค่า'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(saveButton.onPressed, isNull);
    expect(backend.puts, isEmpty);
    expect(find.text('บันทึกการตั้งค่าแล้ว'), findsNothing);
  });

  testWidgets('toggling platform enabled keeps renderer and tileSourceId unchanged in PUT', (tester) async {
    final backend = _FakeBackend();
    await _pumpSection(tester, backend);

    await tester.tap(
      find.byWidgetPredicate((w) => w is Switch && w.value == false).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('บันทึกการตั้งค่า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึกการตั้งค่า'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึก').last);
    await tester.pumpAndSettle();

    final pd = (backend.puts.single['config'] as Map)['platformDefaults'] as Map;
    for (final p in ['web', 'ios', 'android']) {
      final target = pd[p] as Map;
      expect(target['renderer'], 'google', reason: p);
      expect(target['tileSourceId'], isNull, reason: p);
    }
    expect(((pd['web'] as Map)['enabled']), isTrue);
    expect(((pd['ios'] as Map)['enabled']), isTrue);
  });

  // ── Phase 24.A — map data layers card ──────────────────────────────

  testWidgets('layers card renders one switch per registry layer; needs_key disabled',
      (tester) async {
    final backend = _FakeBackend();
    await _pumpSection(tester, backend);

    expect(find.text('ชั้นข้อมูลบนแผนที่ (Map Data Layers)'), findsOneWidget);
    for (final id in ['rain', 'waterLevel', 'ews']) {
      expect(find.byKey(Key('map-layer-switch-$id')), findsOneWidget);
    }
    // needs_key stays off until the server deploys the missing asset.
    final ews = tester.widget<Switch>(
      find.byKey(const Key('map-layer-switch-ews')),
    );
    expect(ews.onChanged, isNull);
    // dev_only is toggleable while the config environment is dev.
    final rain = tester.widget<Switch>(
      find.byKey(const Key('map-layer-switch-rain')),
    );
    expect(rain.onChanged, isNotNull);
  });

  testWidgets('toggling a layer switch writes features.<id> into the PUT doc',
      (tester) async {
    final backend = _FakeBackend();
    await _pumpSection(tester, backend);

    await tester.ensureVisible(find.byKey(const Key('map-layer-switch-rain')));
    await tester.tap(find.byKey(const Key('map-layer-switch-rain')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('บันทึกการตั้งค่า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึกการตั้งค่า'));
    await tester.pumpAndSettle();

    expect(backend.puts, hasLength(1));
    final features = (backend.puts[0]['config'] as Map)['features'] as Map;
    expect((features['rain'] as Map)['enabled'], isTrue);
    // Sibling gate untouched.
    expect((features['incidentOverviewMap'] as Map)['enabled'], isFalse);
    expect(find.text('บันทึกการตั้งค่าแล้ว'), findsOneWidget);
  });

  testWidgets('layer switches stay off while showing the app default', (tester) async {
    final backend = _FakeBackend(publicStatus: 500, adminStatus: 500);
    await _pumpSection(tester, backend);

    final rain = tester.widget<Switch>(
      find.byKey(const Key('map-layer-switch-rain')),
    );
    expect(rain.onChanged, isNull);
  });
}
