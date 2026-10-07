import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/court_card_style.dart';

/// Isometric cube-stack artwork used by the 3D Court Card styles.
///
/// [level] is 1–5 (rating band / supply tier). Three implementations share the
/// same composition so the admin can compare them side by side:
///
/// * `painter3d` — 3D isometric voxel cube cluster matching prototype
/// * `shaderGlass` — the glass sheen comes from a fragment shader over the 3D cubes
/// * `lottieCubes` — animated floating / breathing voxel cluster variant
class CourtCardCubeArt extends StatelessWidget {
  static const String painterKey = 'court_card_cubes_painter';
  static const String shaderKey = 'court_card_cubes_shader';
  static const String lottieKey = 'court_card_cubes_lottie';

  static const String cubeSheetAsset = 'assets/cubes/court_card_cubes_sheet.png';
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
        child: _AnimatedVoxelCubeArt(level: level),
      );
    }
    return SizedBox(
      key: const ValueKey(painterKey),
      width: size,
      height: size,
      child: CustomPaint(painter: CourtCardCubePainter(level: level)),
    );
  }
}

/// Animated 3D voxel cube cluster: gently sways and pulses with breathing motion.
class _AnimatedVoxelCubeArt extends StatefulWidget {
  final int level;

  const _AnimatedVoxelCubeArt({required this.level});

  @override
  State<_AnimatedVoxelCubeArt> createState() => _AnimatedVoxelCubeArtState();
}

class _AnimatedVoxelCubeArtState extends State<_AnimatedVoxelCubeArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final floatDy = -math.sin(t * math.pi) * 3.5;
        final pulse = 0.95 + 0.10 * math.sin(t * math.pi);
        return Transform.translate(
          offset: Offset(0, floatDy),
          child: CustomPaint(
            painter: CourtCardCubePainter(
              level: widget.level,
              pulseFactor: pulse,
            ),
          ),
        );
      },
    );
  }
}

/// Paints the photorealistic 3D isometric voxel cube cluster matching the prototype:
/// - Three stepped columns of ruby glass cubes
/// - Lit top faces with specular chamfer outlines
/// - Left and right faces shaded for volumetric depth
/// - Internal ambient red glow radiating into the glass
class CourtCardCubePainter extends CustomPainter {
  final int level;
  final double pulseFactor;

  const CourtCardCubePainter({
    required this.level,
    this.pulseFactor = 1.0,
  });

  double get _levelFactor => (level.clamp(1, 5)) / 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final originX = size.width * 0.46;
    final originY = size.height * 0.70;
    final cubeS = size.width * 0.17;
    const cos30 = 0.866025;
    const sin30 = 0.50;

    Offset proj(double x, double y, double z) {
      final px = originX + (x - y) * cubeS * cos30;
      final py = originY + (x + y) * cubeS * sin30 - z * cubeS;
      return Offset(px, py);
    }

    _paintGroundShadow(canvas, size, originX, originY);
    _paintCoreGlow(canvas, size, originX, originY);

    // Voxel grid matching prototype:
    // (x, y, maxZ)
    final grid = const [
      (0, 0, 2),
      (1, 0, 2),
      (0, 1, 3),
      (1, 1, 4), // tallest tower in center
      (2, 0, 1),
      (0, 2, 2),
      (2, 1, 3),
      (1, 2, 4),
      (2, 2, 2),
    ];

    final voxels = <({double x, double y, double z})>[];
    for (final col in grid) {
      final maxZ = (col.$3 * (0.6 + 0.4 * _levelFactor)).ceil().clamp(1, col.$3);
      for (var z = 0; z < maxZ; z++) {
        voxels.add((x: col.$1.toDouble(), y: col.$2.toDouble(), z: z.toDouble()));
      }
    }

    // Back-to-front sorting (painter's algorithm)
    voxels.sort((a, b) {
      final depthComp = -(a.x + a.y).compareTo(-(b.x + b.y));
      if (depthComp != 0) return depthComp;
      return a.z.compareTo(b.z);
    });

    for (final v in voxels) {
      final heightFactor = (v.z + 1) / 4.0;
      final brightness =
          (0.45 + 0.55 * heightFactor) * (0.55 + 0.45 * _levelFactor) * pulseFactor;

      // 1. Left face (points left-down)
      _drawPolygon(
        canvas,
        [
          proj(v.x, v.y + 1, v.z),
          proj(v.x, v.y, v.z),
          proj(v.x, v.y, v.z + 1),
          proj(v.x, v.y + 1, v.z + 1),
        ],
        Color.lerp(const Color(0xFFC0101E), const Color(0xFFE52230), brightness.clamp(0.0, 1.0))!,
        alpha: 0.92,
      );

      // 2. Right face (points right-down, deeper ruby shadow)
      _drawPolygon(
        canvas,
        [
          proj(v.x, v.y, v.z),
          proj(v.x + 1, v.y, v.z),
          proj(v.x + 1, v.y, v.z + 1),
          proj(v.x, v.y, v.z + 1),
        ],
        Color.lerp(const Color(0xFF8B0912), const Color(0xFFB0101C), brightness.clamp(0.0, 1.0))!,
        alpha: 0.95,
      );

      // 3. Top face (points straight up, lit ruby red with specular edge)
      _drawPolygon(
        canvas,
        [
          proj(v.x, v.y, v.z + 1),
          proj(v.x + 1, v.y, v.z + 1),
          proj(v.x + 1, v.y + 1, v.z + 1),
          proj(v.x, v.y + 1, v.z + 1),
        ],
        Color.lerp(const Color(0xFFFF2535), const Color(0xFFFF5664), brightness.clamp(0.0, 1.0))!,
        alpha: 0.96,
        isTop: true,
      );
    }
  }

  void _drawPolygon(
    Canvas canvas,
    List<Offset> points,
    Color color, {
    required double alpha,
    bool isTop = false,
  }) {
    final path = Path()..addPolygon(points, true);
    final paint = Paint()..color = color.withValues(alpha: alpha);
    canvas.drawPath(path, paint);

    if (isTop) {
      final edgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withValues(alpha: 0.40);
      canvas.drawPath(path, edgePaint);
    }
  }

  void _paintGroundShadow(Canvas canvas, Size size, double originX, double originY) {
    final shadowPaint = Paint()
      ..color = const Color(0xFF280206).withValues(alpha: 0.25 * _levelFactor)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(originX, originY + 12),
        width: size.width * 0.85,
        height: 22,
      ),
      shadowPaint,
    );
  }

  void _paintCoreGlow(Canvas canvas, Size size, double originX, double originY) {
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFF2A3A).withValues(alpha: (0.35 * _levelFactor * pulseFactor).clamp(0.0, 1.0)),
          const Color(0xFFFF2A3A).withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(originX, originY - 14),
          radius: size.width * 0.55,
        ),
      );
    canvas.drawCircle(
      Offset(originX, originY - 14),
      size.width * 0.55,
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CourtCardCubePainter oldDelegate) =>
      oldDelegate.level != level || oldDelegate.pulseFactor != pulseFactor;
}

/// Shaded variant: overlays the fragment shader glass sheen on top of the 3D voxel cubes.
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
