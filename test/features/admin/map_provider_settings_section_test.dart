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
    };

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// Routes fake requests by path. [putStatus] controls the save outcome.
class _FakeBackend {
  _FakeBackend({this.putStatus = 200, this.publicStatus = 200, this.adminStatus = 200});

  int putStatus;
  final int publicStatus;
  final int adminStatus;
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
            'id': 9,
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

  testWidgets('compact web 320x568 + text scale 1.3 renders without overflow', (tester) async {
    final backend = _FakeBackend();
    await tester.binding.setSurfaceSize(const Size(320, 568));
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
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
    final exception = tester.takeException();
    if (exception != null) {
      if (exception is FlutterError) {
        for (final d in exception.diagnostics) {
          final desc = d.toDescription();
          if (desc.contains('widget was') ||
              desc.contains('Row') ||
              desc.contains('creator') ||
              desc.contains('cross axis')) {
            debugPrint('DIAG: $desc');
          }
        }
      }
      throw exception;
    }
  });

  testWidgets('422 shows server validation errors inline and keeps draft', (tester) async {
    final backend = _FakeBackend(putStatus: 422);
    await _pumpSection(tester, backend);

    await tester.tap(
      find.byWidgetPredicate((w) => w is Switch && w.value == false).first,
    );
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
}
