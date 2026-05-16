import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/consultation_package.dart';

class PackageWheelSelector extends StatefulWidget {
  final List<ConsultationPackage> packages;
  final Function(ConsultationPackage) onPackageSelected;
  final ConsultationPackage? initialPackage;
  final Color themeColor;

  const PackageWheelSelector({
    super.key,
    required this.packages,
    required this.onPackageSelected,
    this.initialPackage,
    this.themeColor = AppColors.primary,
  });

  @override
  State<PackageWheelSelector> createState() => _PackageWheelSelectorState();
}

class _PackageWheelSelectorState extends State<PackageWheelSelector> {
  late FixedExtentScrollController _scrollController;
  int _selectedIndex = 0;
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.initialPackage != null) {
      _selectedIndex = widget.packages.indexWhere((p) => p.id == widget.initialPackage!.id);
      if (_selectedIndex == -1) _selectedIndex = 0;
    }
    _scrollController = FixedExtentScrollController(initialItem: _selectedIndex);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (mounted) {
      setState(() {
        _scrollOffset = _scrollController.offset / 80.0;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.packages.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final wheelRadius = width * 0.75;
        final centerX = -width * 0.35;
        final centerY = height * 0.5;
        final slices = 10;
        final spacingAngle = (math.pi * 2) / slices;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Wheel Hub & Spokes
            Positioned(
              left: centerX - wheelRadius,
              top: centerY - wheelRadius,
              child: Transform.rotate(
                angle: -_scrollOffset * spacingAngle,
                child: _WheelVisual(
                  radius: wheelRadius,
                  color: widget.themeColor,
                  slices: slices,
                ),
              ),
            ),

            // Package Labels
            for (var i = 0; i < slices; i++)
              _buildCurvedLabel(
                index: i,
                name: widget.packages[i % widget.packages.length].shortName,
                centerX: centerX,
                centerY: centerY,
                radius: wheelRadius - 38,
                spacingAngle: spacingAngle,
              ),

            // Invisible physics controller
            Positioned.fill(
              child: ListWheelScrollView.useDelegate(
                controller: _scrollController,
                itemExtent: 80,
                perspective: 0.005,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (index) {
                  setState(() {
                    _selectedIndex = index % widget.packages.length;
                  });
                  widget.onPackageSelected(widget.packages[_selectedIndex]);
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  builder: (context, index) => const SizedBox(height: 80),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCurvedLabel({
    required int index,
    required String name,
    required double centerX,
    required double centerY,
    required double radius,
    required double spacingAngle,
  }) {
    final slices = 10;
    final currentOffset = _scrollOffset % slices;
    double angle = (index - currentOffset) * spacingAngle;

    while (angle > math.pi) angle -= 2 * math.pi;
    while (angle < -math.pi) angle += 2 * math.pi;

    if (angle.abs() > math.pi / 2.2) return const SizedBox.shrink();

    final isSelected = index % widget.packages.length == _selectedIndex;
    final arcWidthAvailable = radius * (spacingAngle * 0.82);
    
    double fontSize = isSelected ? 24 : 16;
    final estimatedWidth = name.length * fontSize * 0.72;
    if (estimatedWidth > arcWidthAvailable) {
      fontSize = arcWidthAvailable / (name.length * 0.72);
    }

    final x = centerX + radius * math.cos(angle);
    final y = centerY + radius * math.sin(angle);

    return Positioned(
      left: x - 100,
      top: y - 25,
      child: Transform.rotate(
        angle: angle,
        child: Opacity(
          opacity: (1.0 - (angle.abs() / (math.pi / 2))).clamp(0.0, 1.0),
          child: SizedBox(
            width: 200,
            height: 50,
            child: CustomPaint(
              painter: _CurvedTextPainter(
                text: name,
                radius: radius,
                style: TextStyle(
                  color: isSelected ? widget.themeColor : Colors.grey.shade600,
                  fontSize: fontSize,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WheelVisual extends StatelessWidget {
  final double radius;
  final Color color;
  final int slices;

  const _WheelVisual({
    required this.radius,
    required this.color,
    required this.slices,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      child: CustomPaint(
        painter: _WheelPainter(color: color, slices: slices),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final Color color;
  final int slices;

  _WheelPainter({required this.color, required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final ringPaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, ringPaint);
    canvas.drawCircle(center, radius - 40, ringPaint);

    final spokePaint = Paint()
      ..color = color.withOpacity(0.1)
      ..strokeWidth = 1.0;

    for (var i = 0; i < slices; i++) {
      final angle = (math.pi * 2 * i) / slices;
      final start = Offset(
        center.dx + (radius - 40) * math.cos(angle),
        center.dy + (radius - 40) * math.sin(angle),
      );
      final end = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(start, end, spokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CurvedTextPainter extends CustomPainter {
  final String text;
  final double radius;
  final TextStyle style;

  _CurvedTextPainter({
    required this.text,
    required this.radius,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    double totalAngle = (text.length * (style.fontSize ?? 14) * 0.7) / radius;
    double currentAngle = -totalAngle / 2;

    for (var i = 0; i < text.length; i++) {
      textPainter.text = TextSpan(text: text[i], style: style);
      textPainter.layout();
      
      final charAngle = textPainter.width / radius;
      final angle = currentAngle + charAngle / 2;
      
      final x = size.width / 2 + radius * math.cos(angle - math.pi / 2);
      final y = radius + radius * math.sin(angle - math.pi / 2);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
      canvas.restore();
      
      currentAngle += charAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
