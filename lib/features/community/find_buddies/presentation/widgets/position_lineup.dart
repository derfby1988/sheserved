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

/// Custom painter for grass field (single or double side) with subtle markings.
class FieldCanvasPainter extends CustomPainter {
  final String layout; // 'single' or 'double'
  final bool isDark;

  FieldCanvasPainter({required this.layout, this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    // Pitch base gradient
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [const Color(0xFF1E3A2B), const Color(0xFF14291E)]
            : [const Color(0xFF2E7D32), const Color(0xFF1B5E20)],
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
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final innerInset = 10.0;
    final pitchRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(innerInset, innerInset, size.width - innerInset, size.height - innerInset),
      const Radius.circular(8),
    );
    canvas.drawRRect(pitchRect, linePaint);

    // Center markings
    if (layout == 'double') {
      final midX = size.width / 2;
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        linePaint,
      );
      // Center circle
      final centerCircleRadius = (size.height - innerInset * 2) * 0.22;
      canvas.drawCircle(Offset(midX, size.height / 2), centerCircleRadius, linePaint);
      final dotPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(midX, size.height / 2), 3.5, dotPaint);

      // Penalty boxes on left & right
      final boxWidth = size.width * 0.16;
      final boxHeight = size.height * 0.45;
      final boxTop = (size.height - boxHeight) / 2;

      // Left box
      canvas.drawRect(
        Rect.fromLTWH(innerInset, boxTop, boxWidth, boxHeight),
        linePaint,
      );
      // Right box
      canvas.drawRect(
        Rect.fromLTWH(size.width - innerInset - boxWidth, boxTop, boxWidth, boxHeight),
        linePaint,
      );
    } else {
      // Single side: Goal box at top or bottom (standard half-pitch / court)
      final boxWidth = size.width * 0.44;
      final boxHeight = size.height * 0.26;
      final boxLeft = (size.width - boxWidth) / 2;

      // Bottom box
      canvas.drawRect(
        Rect.fromLTWH(boxLeft, size.height - innerInset - boxHeight, boxWidth, boxHeight),
        linePaint,
      );

      // Top arc or center arc
      final arcRadius = size.width * 0.22;
      canvas.drawCircle(Offset(size.width / 2, innerInset), arcRadius, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant FieldCanvasPainter oldDelegate) {
    return oldDelegate.layout != layout || oldDelegate.isDark != isDark;
  }
}

/// Interactive Editor for sport group positions on a pitch canvas.
class PositionLineupEditor extends StatefulWidget {
  final String layout; // 'single' or 'double'
  final List<Map<String, dynamic>> positions;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool enabled;

  const PositionLineupEditor({
    super.key,
    required this.layout,
    required this.positions,
    required this.onChanged,
    this.enabled = true,
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

  const PositionLineupView({
    super.key,
    required this.layout,
    required this.positions,
    this.takenCounts,
    this.selectedPositionId,
    this.onPositionSelected,
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
