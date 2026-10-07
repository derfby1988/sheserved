import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
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
    test('the Lottie cube stack parses into a real composition', () async {
      final bytes = await File(CourtCardCubeArt.lottieAsset).readAsBytes();
      final composition = await LottieComposition.fromBytes(bytes);

      expect(composition.layers, isNotEmpty);
      expect(composition.duration.inMilliseconds, greaterThan(0));
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
