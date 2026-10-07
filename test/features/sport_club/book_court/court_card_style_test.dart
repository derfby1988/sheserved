import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/application/court_card_style_service.dart';
import 'package:sheserved/features/sport_club/book_court/domain/court_card_style.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_card_art.dart';

void main() {
  group('CourtCardStyle', () {
    test('exposes one classic style plus three 3D styles', () {
      expect(CourtCardStyle.values, hasLength(4));
      expect(CourtCardStyle.classic.isThreeDimensional, isFalse);
      expect(CourtCardStyle.painter3d.isThreeDimensional, isTrue);
      expect(CourtCardStyle.shaderGlass.isThreeDimensional, isTrue);
      expect(CourtCardStyle.lottieCubes.isThreeDimensional, isTrue);
    });

    test('round-trips every wire value', () {
      for (final style in CourtCardStyle.values) {
        expect(CourtCardStyle.fromWire(style.wireValue), style);
      }
    });

    test('falls back to the classic card for unknown or missing values', () {
      expect(CourtCardStyle.fromWire(null), CourtCardStyle.fallback);
      expect(CourtCardStyle.fromWire(''), CourtCardStyle.fallback);
      expect(CourtCardStyle.fromWire('future_style'), CourtCardStyle.fallback);
    });

    test('every style carries a label and a description', () {
      for (final style in CourtCardStyle.values) {
        expect(style.label.trim(), isNotEmpty);
        expect(style.description.trim(), isNotEmpty);
      }
    });
  });

  group('court card assets', () {
    test('the rendered cube sprite sheet is a valid PNG grid', () async {
      final bytes = await File(CourtCardCubeArt.cubeSheetAsset).readAsBytes();
      // PNG signature.
      expect(
        bytes.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      );
      // IHDR width/height at fixed offsets (big-endian).
      final width = bytes.buffer.asByteData().getUint32(16);
      final height = bytes.buffer.asByteData().getUint32(20);
      expect(width, greaterThan(0));
      expect(height, greaterThan(0));
      // A 4x4 grid of square frames.
      expect(width, height);
      expect(width % 4, 0);
      expect(height % 4, 0);
    });

    test('the glass shader source is bundled', () {
      expect(File(CourtCardCubeArt.glassShaderAsset).existsSync(), isTrue);
    });
  });

  group('CourtCardStyleService.parseSettingsValue', () {
    test('reads the stored jsonb object', () {
      expect(
        CourtCardStyleService.parseSettingsValue(const {
          'style': 'shader_glass',
        }),
        CourtCardStyle.shaderGlass,
      );
    });

    test('accepts a bare string value', () {
      expect(
        CourtCardStyleService.parseSettingsValue('lottie_cubes'),
        CourtCardStyle.lottieCubes,
      );
    });

    test('returns null when nothing usable is stored', () {
      expect(CourtCardStyleService.parseSettingsValue(null), isNull);
      expect(CourtCardStyleService.parseSettingsValue(const {}), isNull);
      expect(CourtCardStyleService.parseSettingsValue(''), isNull);
      expect(
        CourtCardStyleService.parseSettingsValue(const {'style': 'nope'}),
        CourtCardStyle.fallback,
      );
    });
  });
}
