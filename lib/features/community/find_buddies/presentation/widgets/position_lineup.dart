import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';

/// Icon options for position markers with localized Thai names.
const Map<String, ({IconData icon, String label})> kPositionIconChoices = {
  'player': (icon: Icons.person_rounded, label: 'ผู้เล่นทั่วไป'),
  'forward': (icon: Icons.sports_soccer_rounded, label: 'กองหน้า / รุก'),
  'midfielder': (icon: Icons.all_inclusive_rounded, label: 'กองกลาง'),
  'defender': (icon: Icons.shield_rounded, label: 'กองหลัง / รับ'),
  'goalkeeper': (icon: Icons.front_hand_rounded, label: 'ผู้รักษาประตู'),
  'shooter': (icon: Icons.sports_basketball_rounded, label: 'ชู๊ตเตอร์ / ทำแต้ม'),
  'captain': (icon: Icons.stars_rounded, label: 'กัปตันทีม'),
  'marker': (icon: Icons.location_on_rounded, label: 'ตำแหน่งสนาม'),
};

/// Color choices available for position markers (#RRGGBB).
const List<String> kPositionColorChoices = [
  '#2196F3', // ฟ้า / Blue
  '#4CAF50', // เขียว / Green
  '#FF9800', // ส้ม / Orange
  '#E91E63', // ชมพู / Pink
  '#9C27B0', // ม่วง / Purple
  '#00BCD4', // ฟ้าคราม / Cyan
  '#F44336', // แดง / Red
  '#607D8B', // เทาน้ำเงิน / Blue Grey
];

Color parseHexColor(String? hexString, {Color fallback = const Color(0xFF2196F3)}) {
  if (hexString == null || hexString.isEmpty) return fallback;
  final buffer = StringBuffer();
  if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
  buffer.write(hexString.replaceFirst('#', ''));
  try {
    return Color(int.parse(buffer.toString(), radix: 16));
  } catch (_) {
    return fallback;
  }
}

/// Line-marking presets available for simulated fields.
const Map<String, String> kFieldStylePresets = {
  'generic': 'ทั่วไป (เส้นขอบ)',
  'football': 'ฟุตบอล / ฟุตซอล',
  'badminton': 'แบดมินตัน',
  'basketball': 'บาสเกตบอล',
  'volleyball': 'วอลเลย์บอล',
  'tennis': 'เทนนิส',
};

/// Surface color palette for simulated fields (#RRGGBB).
const List<String> kFieldSurfaceColors = [
  '#2E7D32', // หญ้าเขียว / Grass green
  '#1565C0', // น้ำเงิน / Blue court
  '#EF6C00', // ดิน/ส้ม / Clay orange
  '#6D4C41', // ไม้ / Wood brown
  '#00838F', // เทอร์ควอยซ์ / Teal
  '#546E7A', // เทา / Grey
  '#B71C1C', // แดง / Red
  '#7B1FA2', // ม่วง / Purple
];

/// Line color palette for field markings (#RRGGBB).
const List<String> kFieldLineColors = [
  '#FFFFFF', // ขาว
  '#FFF176', // เหลืองอ่อน
  '#212121', // ดำ
];

/// Field appearance config stored in sports.field_style (JSONB).
class FieldStyle {
  final String preset; // key in kFieldStylePresets
  final String surface; // '#RRGGBB'
  final String line; // '#RRGGBB'

  const FieldStyle({
    this.preset = 'generic',
    this.surface = '#2E7D32',
    this.line = '#FFFFFF',
  });

  static const FieldStyle fallback = FieldStyle();

  factory FieldStyle.fromJson(dynamic json) {
    if (json is! Map) return fallback;
    final preset = json['preset']?.toString() ?? 'generic';
    return FieldStyle(
      preset: kFieldStylePresets.containsKey(preset) ? preset : 'generic',
      surface: json['surface']?.toString() ?? '#2E7D32',
      line: json['line']?.toString() ?? '#FFFFFF',
    );
  }

  Map<String, dynamic> toJson() => {
        'preset': preset,
        'surface': surface,
        'line': line,
      };

  FieldStyle copyWith({String? preset, String? surface, String? line}) {
    return FieldStyle(
      preset: preset ?? this.preset,
      surface: surface ?? this.surface,
      line: line ?? this.line,
    );
  }
}

Color _darkenColor(Color c, double factor) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness * factor).clamp(0.0, 1.0))
      .toColor();
}

/// Custom painter for grass field (single or double side) with subtle markings.
class FieldCanvasPainter extends CustomPainter {
  final String layout; // 'single' or 'double'
  final bool isDark;
  final FieldStyle style;

  FieldCanvasPainter({
    required this.layout,
    this.isDark = false,
    this.style = FieldStyle.fallback,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Pitch base gradient
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    final surface = parseHexColor(style.surface, fallback: const Color(0xFF2E7D32));
    final surfaceDark = _darkenColor(surface, 0.66);
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [_darkenColor(surface, 0.45), _darkenColor(surface, 0.32)]
            : [surface, surfaceDark],
      ).createShader(rect);
    canvas.drawRRect(rrect, basePaint);

    // Subtle pitch stripes (alternating grass texture)
    final stripePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    final stripeCount = 6;
    final stripeWidth = size.width / stripeCount;
    for (int i = 0; i < stripeCount; i += 2) {
      final stripeRect = Rect.fromLTWH(i * stripeWidth, 0, stripeWidth, size.height);
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(stripeRect, stripePaint);
      canvas.restore();
    }

    // Boundary lines
    final lineColor = parseHexColor(style.line, fallback: Colors.white);
    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final innerInset = 10.0;
    final pitchRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(innerInset, innerInset, size.width - innerInset, size.height - innerInset),
      const Radius.circular(8),
    );
    canvas.drawRRect(pitchRect, linePaint);

    final isDouble = layout == 'double';
    final midX = size.width / 2;
    final netPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;
    final dotPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    switch (style.preset) {
      case 'football':
        _paintFootball(canvas, size, linePaint, dotPaint, innerInset, isDouble, midX);
        break;
      case 'badminton':
        _paintBadminton(canvas, size, linePaint, netPaint, innerInset, isDouble, midX);
        break;
      case 'volleyball':
        _paintVolleyball(canvas, size, linePaint, netPaint, innerInset, isDouble, midX);
        break;
      case 'tennis':
        _paintTennis(canvas, size, linePaint, netPaint, innerInset, isDouble, midX);
        break;
      case 'basketball':
        _paintBasketball(canvas, size, linePaint, dotPaint, innerInset, isDouble, midX);
        break;
      default: // generic — boundary only + center line when double
        if (isDouble) {
          canvas.drawLine(
            Offset(midX, innerInset),
            Offset(midX, size.height - innerInset),
            linePaint,
          );
        }
    }
  }

  void _paintFootball(Canvas canvas, Size size, Paint linePaint, Paint dotPaint,
      double innerInset, bool isDouble, double midX) {
    if (isDouble) {
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        linePaint,
      );
      final centerCircleRadius = (size.height - innerInset * 2) * 0.22;
      canvas.drawCircle(Offset(midX, size.height / 2), centerCircleRadius, linePaint);
      canvas.drawCircle(Offset(midX, size.height / 2), 3.5, dotPaint);

      final boxWidth = size.width * 0.16;
      final boxHeight = size.height * 0.45;
      final boxTop = (size.height - boxHeight) / 2;
      canvas.drawRect(
        Rect.fromLTWH(innerInset, boxTop, boxWidth, boxHeight),
        linePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(size.width - innerInset - boxWidth, boxTop, boxWidth, boxHeight),
        linePaint,
      );
    } else {
      final boxWidth = size.width * 0.44;
      final boxHeight = size.height * 0.26;
      final boxLeft = (size.width - boxWidth) / 2;
      canvas.drawRect(
        Rect.fromLTWH(boxLeft, size.height - innerInset - boxHeight, boxWidth, boxHeight),
        linePaint,
      );
      final arcRadius = size.width * 0.22;
      canvas.drawCircle(Offset(size.width / 2, innerInset), arcRadius, linePaint);
    }
  }

  void _paintBadminton(Canvas canvas, Size size, Paint linePaint, Paint netPaint,
      double innerInset, bool isDouble, double midX) {
    // Singles sidelines inset from top/bottom edges.
    final sideInset = size.height * 0.12;
    final topY = innerInset + sideInset;
    final botY = size.height - innerInset - sideInset;

    if (isDouble) {
      // Net at center.
      canvas.drawLine(Offset(midX, innerInset), Offset(midX, size.height - innerInset), netPaint);
      // Per half: short service line ~22% from net + singles sidelines.
      final halfW = midX - innerInset;
      for (final dir in [-1.0, 1.0]) {
        final shortServiceX = midX + dir * halfW * 0.22;
        canvas.drawLine(Offset(shortServiceX, innerInset), Offset(shortServiceX, size.height - innerInset), linePaint);
        // Long service (doubles) line near back boundary.
        final backX = midX + dir * halfW * 0.88;
        canvas.drawLine(Offset(backX, topY), Offset(backX, botY), linePaint);
      }
    } else {
      // Full court without net: doubles boundary + singles sidelines + service lines.
      canvas.drawLine(Offset(innerInset, topY), Offset(size.width - innerInset, topY), linePaint);
      canvas.drawLine(Offset(innerInset, botY), Offset(size.width - innerInset, botY), linePaint);
      final courtW = size.width - innerInset * 2;
      canvas.drawLine(Offset(innerInset + courtW * 0.28, topY), Offset(innerInset + courtW * 0.28, botY), linePaint);
      canvas.drawLine(Offset(innerInset + courtW * 0.72, topY), Offset(innerInset + courtW * 0.72, botY), linePaint);
      canvas.drawLine(Offset(midX, topY), Offset(midX, botY), linePaint);
    }
  }

  void _paintVolleyball(Canvas canvas, Size size, Paint linePaint, Paint netPaint,
      double innerInset, bool isDouble, double midX) {
    if (isDouble) {
      canvas.drawLine(Offset(midX, innerInset), Offset(midX, size.height - innerInset), netPaint);
      // Attack (3m) line ~25% from net on each half.
      final halfW = midX - innerInset;
      for (final dir in [-1.0, 1.0]) {
        final attackX = midX + dir * halfW * 0.30;
        canvas.drawLine(Offset(attackX, innerInset), Offset(attackX, size.height - innerInset), linePaint);
      }
    } else {
      // Center + attack lines.
      canvas.drawLine(Offset(midX, innerInset), Offset(midX, size.height - innerInset), netPaint);
      final courtW = size.width - innerInset * 2;
      canvas.drawLine(Offset(innerInset + courtW * 0.25, innerInset), Offset(innerInset + courtW * 0.25, size.height - innerInset), linePaint);
      canvas.drawLine(Offset(innerInset + courtW * 0.75, innerInset), Offset(innerInset + courtW * 0.75, size.height - innerInset), linePaint);
    }
  }

  void _paintTennis(Canvas canvas, Size size, Paint linePaint, Paint netPaint,
      double innerInset, bool isDouble, double midX) {
    // Singles sidelines inset from top/bottom edges.
    final sideInset = size.height * 0.10;
    final topY = innerInset + sideInset;
    final botY = size.height - innerInset - sideInset;
    final midY = size.height / 2;

    if (isDouble) {
      canvas.drawLine(Offset(midX, innerInset), Offset(midX, size.height - innerInset), netPaint);
      final halfW = midX - innerInset;
      for (final dir in [-1.0, 1.0]) {
        // Service line ~32% from net.
        final serviceX = midX + dir * halfW * 0.34;
        canvas.drawLine(Offset(serviceX, topY), Offset(serviceX, botY), linePaint);
        // Center service line from net to service line.
        canvas.drawLine(Offset(midX, midY), Offset(serviceX, midY), linePaint);
      }
      // Singles sidelines.
      canvas.drawLine(Offset(innerInset, topY), Offset(midX, topY), linePaint);
      canvas.drawLine(Offset(innerInset, botY), Offset(midX, botY), linePaint);
      canvas.drawLine(Offset(midX, topY), Offset(size.width - innerInset, topY), linePaint);
      canvas.drawLine(Offset(midX, botY), Offset(size.width - innerInset, botY), linePaint);
    } else {
      canvas.drawLine(Offset(innerInset, topY), Offset(size.width - innerInset, topY), linePaint);
      canvas.drawLine(Offset(innerInset, botY), Offset(size.width - innerInset, botY), linePaint);
      canvas.drawLine(Offset(midX, innerInset), Offset(midX, size.height - innerInset), netPaint);
      final halfW = midX - innerInset;
      for (final dir in [-1.0, 1.0]) {
        final serviceX = midX + dir * halfW * 0.38;
        canvas.drawLine(Offset(serviceX, topY), Offset(serviceX, botY), linePaint);
        canvas.drawLine(Offset(midX, midY), Offset(serviceX, midY), linePaint);
      }
    }
  }

  void _paintBasketball(Canvas canvas, Size size, Paint linePaint, Paint dotPaint,
      double innerInset, bool isDouble, double midX) {
    if (isDouble) {
      canvas.drawLine(Offset(midX, innerInset), Offset(midX, size.height - innerInset), linePaint);
      final centerCircleRadius = (size.height - innerInset * 2) * 0.20;
      canvas.drawCircle(Offset(midX, size.height / 2), centerCircleRadius, linePaint);
      canvas.drawCircle(Offset(midX, size.height / 2), 3.5, dotPaint);
      // Key + free-throw arc near each end.
      final keyW = size.width * 0.13;
      final keyH = size.height * 0.34;
      final keyTop = (size.height - keyH) / 2;
      canvas.drawRect(Rect.fromLTWH(innerInset, keyTop, keyW, keyH), linePaint);
      canvas.drawRect(Rect.fromLTWH(size.width - innerInset - keyW, keyTop, keyW, keyH), linePaint);
      canvas.drawArc(
        Rect.fromCenter(center: Offset(innerInset + keyW, size.height / 2), width: keyH, height: keyH),
        -1.5708, 3.1416, false, linePaint,
      );
      canvas.drawArc(
        Rect.fromCenter(center: Offset(size.width - innerInset - keyW, size.height / 2), width: keyH, height: keyH),
        1.5708, 3.1416, false, linePaint,
      );
    } else {
      final keyW = size.width * 0.36;
      final keyH = size.height * 0.26;
      final keyLeft = (size.width - keyW) / 2;
      canvas.drawRect(Rect.fromLTWH(keyLeft, size.height - innerInset - keyH, keyW, keyH), linePaint);
      canvas.drawArc(
        Rect.fromCenter(center: Offset(size.width / 2, size.height - innerInset - keyH), width: keyW, height: keyW * 0.7),
        3.1416, 3.1416, false, linePaint,
      );
      canvas.drawCircle(Offset(size.width / 2, innerInset), size.width * 0.20, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant FieldCanvasPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.isDark != isDark ||
        oldDelegate.style.preset != style.preset ||
        oldDelegate.style.surface != style.surface ||
        oldDelegate.style.line != style.line;
  }
}

/// Interactive Editor for sport group positions on a pitch canvas.
class PositionLineupEditor extends StatefulWidget {
  final String layout; // 'single' or 'double'
  final List<Map<String, dynamic>> positions;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool enabled;
  final FieldStyle fieldStyle;

  const PositionLineupEditor({
    super.key,
    required this.layout,
    required this.positions,
    required this.onChanged,
    this.enabled = true,
    this.fieldStyle = FieldStyle.fallback,
  });

  @override
  State<PositionLineupEditor> createState() => _PositionLineupEditorState();
}

class _PositionLineupEditorState extends State<PositionLineupEditor> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(
      widget.positions.map((p) => Map<String, dynamic>.from(p)),
    );
  }

  @override
  void didUpdateWidget(covariant PositionLineupEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.positions != oldWidget.positions) {
      _items = List<Map<String, dynamic>>.from(
        widget.positions.map((p) => Map<String, dynamic>.from(p)),
      );
    }
  }

  void _notify() {
    widget.onChanged(List<Map<String, dynamic>>.from(_items));
  }

  Future<void> _openMarkerModal({Map<String, dynamic>? existing, int? index}) async {
    if (!widget.enabled) return;
    final res = await showPositionMarkerEditor(
      context,
      existing: existing,
      layout: widget.layout,
    );
    if (res == null) return;

    setState(() {
      if (index != null && index >= 0 && index < _items.length) {
        _items[index] = {..._items[index], ...res};
      } else {
        // Default placement near center or tapped position
        final nextX = 0.5;
        final nextY = 0.5;
        _items.add({
          ...res,
          'x': nextX,
          'y': nextY,
          'side': widget.layout == 'double' ? (nextX >= 0.5 ? 1 : 0) : 0,
          'is_active': true,
        });
      }
    });
    _notify();
  }

  void _deleteMarker(int index) {
    if (!widget.enabled) return;
    setState(() {
      _items.removeAt(index);
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final isDouble = widget.layout == 'double';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Canvas Header Bar
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isDouble ? Icons.compare_arrows_rounded : Icons.crop_portrait_rounded,
                    size: 16,
                    color: AppColors.primaryDark,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isDouble ? 'สนาม 2 ฝั่ง' : 'สนาม 1 ฝั่ง',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (widget.enabled)
              TextButton.icon(
                onPressed: () => _openMarkerModal(),
                icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                label: const Text('เพิ่มตำแหน่ง'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Interactive Pitch Box
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final w = constraints.maxWidth;
              final h = w * (isDouble ? 0.60 : 0.82);

              return GestureDetector(
                onTapUp: widget.enabled
                    ? (details) {
                        final nx = (details.localPosition.dx / w).clamp(0.05, 0.95);
                        final ny = (details.localPosition.dy / h).clamp(0.05, 0.95);
                        final side = isDouble ? (nx >= 0.5 ? 1 : 0) : 0;
                        showPositionMarkerEditor(
                          context,
                          layout: widget.layout,
                        ).then((res) {
                          if (res != null) {
                            setState(() {
                              _items.add({
                                ...res,
                                'x': nx,
                                'y': ny,
                                'side': side,
                                'is_active': true,
                              });
                            });
                            _notify();
                          }
                        });
                      }
                    : null,
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Stack(
                    children: [
                      // Pitch background
                      Positioned.fill(
                        child: CustomPaint(
                          painter: FieldCanvasPainter(
                            layout: widget.layout,
                            style: widget.fieldStyle,
                          ),
                        ),
                      ),

                      // Hint text if empty
                      if (_items.isEmpty)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.touch_app_rounded, color: Colors.white70, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'แตะที่สนามเพื่อวางตำแหน่งผู้เล่น',
                                  style: TextStyle(color: Colors.white, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Markers
                      for (int i = 0; i < _items.length; i++) ...[
                        _buildDraggableMarker(
                          index: i,
                          item: _items[i],
                          canvasWidth: w,
                          canvasHeight: h,
                          isDouble: isDouble,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),

        // Marker summary chips below pitch
        if (_items.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < _items.length; i++)
                _buildPositionPill(index: i, item: _items[i]),
            ],
          ),
      ],
    );
  }

  Widget _buildDraggableMarker({
    required int index,
    required Map<String, dynamic> item,
    required double canvasWidth,
    required double canvasHeight,
    required bool isDouble,
  }) {
    final x = ((item['x'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
    final y = ((item['y'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
    final iconKey = item['icon']?.toString() ?? 'player';
    final iconMeta = kPositionIconChoices[iconKey] ?? kPositionIconChoices['player']!;
    final color = parseHexColor(item['color']?.toString());
    final label = item['label']?.toString() ?? 'ตำแหน่ง';
    final slots = (item['slots'] as num?)?.toInt() ?? 1;

    final markerSize = 44.0;
    final left = (x * canvasWidth - markerSize / 2).clamp(0.0, canvasWidth - markerSize);
    final top = (y * canvasHeight - markerSize / 2).clamp(0.0, canvasHeight - markerSize);

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: widget.enabled
            ? (details) {
                setState(() {
                  final newLeft = left + details.delta.dx;
                  final newTop = top + details.delta.dy;
                  final nx = ((newLeft + markerSize / 2) / canvasWidth).clamp(0.05, 0.95);
                  final ny = ((newTop + markerSize / 2) / canvasHeight).clamp(0.05, 0.95);
                  item['x'] = nx;
                  item['y'] = ny;
                  if (isDouble) {
                    item['side'] = nx >= 0.5 ? 1 : 0;
                  }
                });
                _notify();
              }
            : null,
        onTap: () => _openMarkerModal(existing: item, index: index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: markerSize,
              height: markerSize,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Icon(iconMeta.icon, color: Colors.white, size: 22),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$label ($slots)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionPill({
    required int index,
    required Map<String, dynamic> item,
  }) {
    final iconKey = item['icon']?.toString() ?? 'player';
    final iconMeta = kPositionIconChoices[iconKey] ?? kPositionIconChoices['player']!;
    final color = parseHexColor(item['color']?.toString());
    final label = item['label']?.toString() ?? '';
    final slots = (item['slots'] as num?)?.toInt() ?? 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(iconMeta.icon, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$slots คน',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryDark,
              ),
            ),
          ),
          if (widget.enabled) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: () => _openMarkerModal(existing: item, index: index),
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
              ),
            ),
            InkWell(
              onTap: () => _deleteMarker(index),
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close_rounded, size: 16, color: Colors.redAccent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Read-only pitch viewer displaying lineup and slot availability.
class PositionLineupView extends StatelessWidget {
  final String layout; // 'single' or 'double'
  final List<Map<String, dynamic>> positions;
  final Map<String, int>? takenCounts; // position_id -> taken count
  final String? selectedPositionId;
  final ValueChanged<String>? onPositionSelected;
  final FieldStyle fieldStyle;

  const PositionLineupView({
    super.key,
    required this.layout,
    required this.positions,
    this.takenCounts,
    this.selectedPositionId,
    this.onPositionSelected,
    this.fieldStyle = FieldStyle.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final isDouble = layout == 'double';
    final activePositions = positions.where((p) => p['is_active'] != false).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final w = constraints.maxWidth;
          final h = w * (isDouble ? 0.60 : 0.82);

          return SizedBox(
            width: w,
            height: h,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: FieldCanvasPainter(
                      layout: layout,
                      style: fieldStyle,
                    ),
                  ),
                ),
                for (final pos in activePositions) ...[
                  _buildMarker(pos, w, h),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMarker(Map<String, dynamic> pos, double canvasWidth, double canvasHeight) {
    final posId = pos['id']?.toString() ?? '';
    final x = ((pos['x'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
    final y = ((pos['y'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
    final iconKey = pos['icon']?.toString() ?? 'player';
    final iconMeta = kPositionIconChoices[iconKey] ?? kPositionIconChoices['player']!;
    final color = parseHexColor(pos['color']?.toString());
    final label = pos['label']?.toString() ?? '';
    final slots = (pos['slots'] as num?)?.toInt() ?? 1;

    final taken = takenCounts != null && posId.isNotEmpty ? (takenCounts![posId] ?? 0) : 0;
    final remaining = (slots - taken).clamp(0, slots);
    final isFull = takenCounts != null && remaining <= 0;
    final isSelected = selectedPositionId != null && selectedPositionId == posId;

    final markerSize = 42.0;
    final left = (x * canvasWidth - markerSize / 2).clamp(0.0, canvasWidth - markerSize);
    final top = (y * canvasHeight - markerSize / 2).clamp(0.0, canvasHeight - markerSize);

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: (onPositionSelected != null && !isFull && posId.isNotEmpty)
            ? () => onPositionSelected!(posId)
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: markerSize,
              height: markerSize,
              decoration: BoxDecoration(
                color: isFull ? Colors.grey.shade500 : color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.amberAccent : Colors.white,
                  width: isSelected ? 3.5 : 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? Colors.amber.withValues(alpha: 0.6)
                        : Colors.black.withValues(alpha: 0.35),
                    blurRadius: isSelected ? 10 : 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  iconMeta.icon,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryDark : Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                takenCounts != null
                    ? '$label (${isFull ? 'เต็ม' : 'เหลือ $remaining'})'
                    : '$label ($slots)',
                style: TextStyle(
                  color: isFull ? Colors.red.shade200 : Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet dialog to create or edit a position marker.
Future<Map<String, dynamic>?> showPositionMarkerEditor(
  BuildContext context, {
  Map<String, dynamic>? existing,
  String layout = 'single',
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final labelCtrl = TextEditingController(
        text: existing?['label']?.toString() ?? '',
      );
      String selectedIcon = existing?['icon']?.toString() ?? 'player';
      String selectedColor = existing?['color']?.toString() ?? kPositionColorChoices.first;
      int slots = (existing?['slots'] as num?)?.toInt() ?? 1;
      int side = (existing?['side'] as num?)?.toInt() ?? 0;
      String? errorText;

      return StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 14,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: parseHexColor(selectedColor).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          (kPositionIconChoices[selectedIcon] ?? kPositionIconChoices['player']!).icon,
                          color: parseHexColor(selectedColor),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        existing != null ? 'แก้ไขตำแหน่งผู้เล่น' : 'เพิ่มตำแหน่งผู้เล่น',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Label Input
                  TextField(
                    controller: labelCtrl,
                    maxLength: 60,
                    decoration: InputDecoration(
                      labelText: 'ชื่อตำแหน่ง (เช่น กองหน้า, ผู้รักษาประตู)',
                      hintText: 'ระบุชื่อตำแหน่งผู้เล่น',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      errorText: errorText,
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Icon Picker
                  const Text('เลือกไอคอนตำแหน่ง', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kPositionIconChoices.entries.map((entry) {
                      final isSelected = selectedIcon == entry.key;
                      return ChoiceChip(
                        selected: isSelected,
                        avatar: Icon(
                          entry.value.icon,
                          size: 16,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                        label: Text(entry.value.label),
                        selectedColor: AppColors.primary,
                        onSelected: (_) => setModalState(() => selectedIcon = entry.key),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Color Palette Picker
                  const Text('เลือกสีหมุดตำแหน่ง', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: kPositionColorChoices.map((hex) {
                      final c = parseHexColor(hex);
                      final isSelected = selectedColor.toUpperCase() == hex.toUpperCase();
                      return GestureDetector(
                        onTap: () => setModalState(() => selectedColor = hex),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.black87 : Colors.white,
                              width: isSelected ? 3 : 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Slots Stepper
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('จำนวนที่รับในตำแหน่งนี้', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('1 – 50 คน', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: slots > 1 ? () => setModalState(() => slots--) : null,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$slots',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: slots < 50 ? () => setModalState(() => slots++) : null,
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Side selector if double
                  if (layout == 'double') ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text('ฝั่งสนาม:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 12),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 0, label: Text('ฝั่งซ้าย / เจ้าบ้าน')),
                            ButtonSegment(value: 1, label: Text('ฝั่งขวา / ทีมเยือน')),
                          ],
                          selected: {side},
                          onSelectionChanged: (set) => setModalState(() => side = set.first),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        final trimmed = labelCtrl.text.trim();
                        if (trimmed.isEmpty) {
                          setModalState(() => errorText = 'กรุณาระบุชื่อตำแหน่ง');
                          return;
                        }
                        Navigator.pop(ctx, {
                          if (existing?['id'] != null) 'id': existing!['id'],
                          'label': trimmed,
                          'icon': selectedIcon,
                          'color': selectedColor,
                          'slots': slots,
                          'side': side,
                          if (existing?['x'] != null) 'x': existing!['x'],
                          if (existing?['y'] != null) 'y': existing!['y'],
                        });
                      },
                      child: const Text('ตกลง', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Shared picker for field appearance (line preset + surface/line colors).
/// Controlled widget — parent keeps the [value] and rebuilds on [onChanged].
class FieldStylePicker extends StatelessWidget {
  final FieldStyle value;
  final ValueChanged<FieldStyle> onChanged;

  const FieldStylePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ลักษณะเส้นสนาม',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: kFieldStylePresets.entries.map((e) {
            final selected = value.preset == e.key;
            return ChoiceChip(
              label: Text(e.value, style: const TextStyle(fontSize: 12)),
              selected: selected,
              onSelected: (_) => onChanged(value.copyWith(preset: e.key)),
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                color: selected ? AppColors.primaryDark : Colors.black87,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        const Text(
          'สีพื้นสนาม',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kFieldSurfaceColors.map((hex) {
            final c = parseHexColor(hex);
            final selected = value.surface.toUpperCase() == hex.toUpperCase();
            return Semantics(
              label: 'สีพื้นสนาม $hex',
              selected: selected,
              button: true,
              child: GestureDetector(
                onTap: () => onChanged(value.copyWith(surface: hex)),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.primaryDark : Colors.white,
                      width: selected ? 3 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        const Text(
          'สีเส้นสนาม',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: kFieldLineColors.map((hex) {
            final c = parseHexColor(hex);
            final selected = value.line.toUpperCase() == hex.toUpperCase();
            return Semantics(
              label: 'สีเส้นสนาม $hex',
              selected: selected,
              button: true,
              child: GestureDetector(
                onTap: () => onChanged(value.copyWith(line: hex)),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.primaryDark : Colors.grey.shade400,
                      width: selected ? 3 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: selected
                      ? Icon(Icons.check,
                          color: hex == '#212121' ? Colors.white : Colors.black87,
                          size: 16)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
