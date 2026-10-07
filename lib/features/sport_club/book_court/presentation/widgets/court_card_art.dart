import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../domain/court_card_style.dart';

/// Isometric cube-stack artwork used by the 3D Court Card styles.
///
/// [level] is 1–5 (rating band / supply tier). Three implementations share the
/// same composition so the admin can compare them side by side:
///
/// * `painter3d` — drawn with [CustomPainter], no asset loading
/// * `shaderGlass` — the glass sheen comes from a fragment shader
/// * `lottieCubes` — the animated variant from `assets/lottie`
///
/// The shader and Lottie variants fall back to the painter art whenever the
/// program or asset is unavailable (widget tests, failed asset load) so the
/// card never renders blank.
class CourtCardCubeArt extends StatelessWidget {
  static const String painterKey = 'court_card_cubes_painter';
  static const String shaderKey = 'court_card_cubes_shader';
  static const String lottieKey = 'court_card_cubes_lottie';

  static const String lottieAsset = 'assets/lottie/court_card_cubes.json';
  static const String glassShaderAsset = 'shaders/court_card_glass.frag';

  final CourtCardStyle style;
  final int level;
  final double size;

  const CourtCardCubeArt({
    super.key,
    required this.style,
    required this.level,
    this.size = 96,
  });

  @override
  Widget build(BuildContext context) {
    if (style == CourtCardStyle.classic) return const SizedBox.shrink();
    if (style == CourtCardStyle.shaderGlass) {
      return SizedBox(
        key: const ValueKey(shaderKey),
        width: size,
        height: size,
        child: _ShaderCubeArt(level: level),
      );
    }
    if (style == CourtCardStyle.lottieCubes) {
      return SizedBox(
        key: const ValueKey(lottieKey),
        width: size,
        height: size,
        child: Lottie.asset(
          lottieAsset,
          fit: BoxFit.contain,
          repeat: true,
          errorBuilder: (_, _, _) => _PainterCubeArt(level: level),
        ),
      );
    }
    return SizedBox(
      key: const ValueKey(painterKey),
      width: size,
      height: size,
      child: _PainterCubeArt(level: level),
    );
  }
}

class _PainterCubeArt extends StatelessWidget {
  final int level;

  const _PainterCubeArt({required this.level});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: CourtCardCubePainter(level: level));
}

/// Paints the isometric pyramid: four cubes at the base, then three, two and
/// one. Brightness rises with height and with [level] so a low score reads as
/// a pale stack and a high score as a glowing one.
///
/// Faces are translucent with per-face gradients, a soft ground shadow and a
/// rim light on the top edges so the stack reads as volumetric glass instead
/// of flat vector shapes: rear cubes show through the front ones and each
/// cube shades from a lit top edge into a darker base.
class CourtCardCubePainter extends CustomPainter {
  static const List<List<double>> _levelOffsets = [
    [-3, -1, 1, 3],
    [-2, 0, 2],
    [-1, 1],
    [0],
  ];

  static const Color _lit = Color(0xFFD91E28);
  static const Color _pale = Color(0xFFEFD2D4);

  static const double _halfWidth = 24.0;
  static const double _halfDepth = 14.0;
  static const double _cubeHeight = 24.0;

  final int level;

  const CourtCardCubePainter({required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    final originX = size.width / 2;
    final originY = size.height - 18;

    final cubes = <({double x, double y, double brightness})>[];
    for (var row = 0; row < _levelOffsets.length; row++) {
      for (final offset in _levelOffsets[row]) {
        final heightFactor = (row + 1) / _levelOffsets.length;
        cubes.add((
          x: originX + offset * _halfWidth,
          y: originY - row * _cubeHeight,
          brightness: (0.35 + 0.65 * heightFactor) * _levelFactor,
        ));
      }
    }
    // Front-most cubes last so they overlap the rows behind them.
    cubes.sort((a, b) => b.y.compareTo(a.y));

    _paintGroundShadow(canvas, originX, originY);
    _paintCoreGlow(canvas, size, originX, originY);

    for (final cube in cubes) {
      final top = Color.lerp(_pale, _lit, cube.brightness)!;
      _fillFace(
        canvas,
        cube,
        top,
        const [
          Offset(-_halfWidth, 0),
          Offset(0, -_halfDepth),
          Offset(_halfWidth, 0),
          Offset(0, _halfDepth),
        ],
        shade: 1.0,
        alpha: 0.96,
      );
      _fillFace(
        canvas,
        cube,
        top,
        const [
          Offset(0, _halfDepth),
          Offset(_halfWidth, 0),
          Offset(_halfWidth, _cubeHeight),
          Offset(0, _halfDepth + _cubeHeight),
        ],
        shade: 0.82,
        alpha: 0.58,
      );
      _fillFace(
        canvas,
        cube,
        top,
        const [
          Offset(-_halfWidth, 0),
          Offset(0, _halfDepth),
          Offset(0, _halfDepth + _cubeHeight),
          Offset(-_halfWidth, _cubeHeight),
        ],
        shade: 0.58,
        alpha: 0.42,
      );
      _paintRimLight(canvas, cube);
    }
  }

  double get _levelFactor => (level.clamp(1, 5)) / 5;

  /// Blurred dark ellipse beneath the stack so it looks like it sits on the
  /// card instead of floating. Stronger when the level is higher.
  void _paintGroundShadow(Canvas canvas, double originX, double originY) {
    final strength = 0.10 + 0.30 * _levelFactor;
    final paint = Paint()
      ..color = const Color(0xFF3A0208).withValues(alpha: strength)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(originX, originY + _halfDepth * 0.8),
        width: _halfWidth * 5.8,
        height: _halfDepth * 2.2,
      ),
      paint,
    );
  }

  /// Soft red radial glow behind the stack; its strength tracks the level so
  /// a high score reads as a lit glass cluster.
  void _paintCoreGlow(Canvas canvas, Size size, double originX, double originY) {
    final glowRect = Rect.fromCenter(
      center: Offset(originX, originY - _cubeHeight * 1.4),
      width: size.width * 0.9,
      height: size.height * 0.7,
    );
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFF3C46)
              .withValues(alpha: 0.08 + 0.20 * _levelFactor),
          const Color(0xFFFF3C46).withValues(alpha: 0.0),
        ],
      ).createShader(glowRect);
    canvas.drawOval(glowRect, paint);
  }

  /// One translucent face: a vertical gradient from a lit top edge into a
  /// darker base, with the alpha baked into the gradient stops so rear cubes
  /// stay visible through the front ones.
  void _fillFace(
    Canvas canvas,
    ({double x, double y, double brightness}) cube,
    Color base,
    List<Offset> vertices, {
    required double shade,
    required double alpha,
  }) {
    final path = Path()
      ..addPolygon([
        for (final vertex in vertices)
          Offset(cube.x + vertex.dx, cube.y + vertex.dy),
      ], true);
    final lighter = _shade(base, shade * 1.28);
    final darker = _shade(base, shade * 0.7);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lighter.withValues(alpha: alpha),
          darker.withValues(alpha: alpha),
        ],
      ).createShader(path.getBounds());
    canvas.drawPath(path, paint);
  }

  /// Specular highlight along the top edges: a bright V on the top face plus
  /// a fainter edge on the right face, scaled with the cube brightness.
  void _paintRimLight(
    Canvas canvas,
    ({double x, double y, double brightness}) cube,
  ) {
    final topEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.30 + 0.25 * cube.brightness);
    final topPath = Path()
      ..moveTo(cube.x - _halfWidth, cube.y)
      ..lineTo(cube.x, cube.y - _halfDepth)
      ..lineTo(cube.x + _halfWidth, cube.y);
    canvas.drawPath(topPath, topEdge);

    final sideEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(
        alpha: 0.16 + 0.12 * cube.brightness,
      );
    final rightPath = Path()
      ..moveTo(cube.x, cube.y + _halfDepth)
      ..lineTo(cube.x + _halfWidth, cube.y);
    canvas.drawPath(rightPath, sideEdge);
  }

  static Color _shade(Color base, double factor) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((hsl.lightness * factor).clamp(0.05, 1.0))
        .withSaturation(
          (hsl.saturation * (factor < 1 ? 1.05 : 0.9)).clamp(0.0, 1.0),
        )
        .toColor();
  }

  @override
  bool shouldRepaint(covariant CourtCardCubePainter oldDelegate) =>
      oldDelegate.level != level;
}

/// Same pyramid, but the glass/glow layer is computed by a fragment shader.
/// Falls back to the painter art when the shader cannot be compiled or loaded
/// (for example inside widget tests, where no asset bundle is available).
class _ShaderCubeArt extends StatefulWidget {
  final int level;

  const _ShaderCubeArt({required this.level});

  @override
  State<_ShaderCubeArt> createState() => _ShaderCubeArtState();
}

class _ShaderCubeArtState extends State<_ShaderCubeArt> {
  static Future<ui.FragmentProgram?>? _program;

  ui.FragmentProgram? _loaded;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _program ??= _loadProgram();
    _program!.then((program) {
      if (!mounted) return;
      setState(() {
        _loaded = program;
        _failed = program == null;
      });
    });
  }

  static Future<ui.FragmentProgram?> _loadProgram() async {
    try {
      return await ui.FragmentProgram.fromAsset(
        CourtCardCubeArt.glassShaderAsset,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final program = _loaded;
    if (_failed || program == null) {
      // Shader not ready yet (or unavailable) — show the painter art so the
      // stack is visible from the first frame.
      return CustomPaint(painter: CourtCardCubePainter(level: widget.level));
    }
    return CustomPaint(
      painter: _ShaderGlassPainter(
        shader: program.fragmentShader(),
        level: widget.level,
      ),
      child: CustomPaint(painter: CourtCardCubePainter(level: widget.level)),
    );
  }
}

class _ShaderGlassPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final int level;

  _ShaderGlassPainter({required this.shader, required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, level.clamp(1, 5) / 5);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _ShaderGlassPainter oldDelegate) =>
      oldDelegate.level != level;
}
