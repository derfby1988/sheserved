import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../data/models/kpi_models.dart';

class KpiGauge extends StatelessWidget {
  final double achievementRate;
  final double? targetAmount;
  final double? actualAmount;
  final String title;
  final String subtitle;
  final double size;

  const KpiGauge({
    super.key,
    required this.achievementRate,
    this.targetAmount,
    this.actualAmount,
    required this.title,
    this.subtitle = '',
    this.size = 160,
  });

  Color _getColor(double rate) {
    if (rate >= 100) return const Color(0xFF4CAF50); // Green
    if (rate >= 80) return const Color(0xFFFFA726); // Orange
    if (rate >= 60) return const Color(0xFFFF7043); // Deep Orange
    return const Color(0xFFEF5350); // Red
  }

  String _formatNumber(double? value) {
    if (value == null) return '-';
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor(achievementRate);
    final clampedRate = achievementRate.clamp(0, 150);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            if (subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: size,
              height: size * 0.65,
              child: CustomPaint(
                size: Size(size, size * 0.65),
                painter: _GaugePainter(
                  rate: clampedRate,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${achievementRate.toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
            if (actualAmount != null || targetAmount != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (actualAmount != null)
                      _buildStat(
                        context,
                        'Actual',
                        _formatNumber(actualAmount),
                        color,
                      ),
                    if (actualAmount != null && targetAmount != null)
                      Container(
                        width: 1,
                        height: 24,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        color: Colors.grey[300],
                      ),
                    if (targetAmount != null)
                      _buildStat(
                        context,
                        'Target',
                        _formatNumber(targetAmount),
                        Colors.grey[700]!,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(BuildContext context, String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.grey[500],
              ),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double rate;
  final Color color;

  _GaugePainter({required this.rate, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, size.height - size.width / 2,
        size.width, size.width);
    final startAngle = math.pi;
    final sweepAngle = math.pi;

    // Background arc
    final bgPaint = Paint()
      ..color = Colors.grey[200]!
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startAngle, sweepAngle, false, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final progressAngle = (rate / 150) * math.pi;
    canvas.drawArc(rect, startAngle, progressAngle, false, progressPaint);

    // Tick marks
    final tickPaint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 1;
    for (int i = 0; i <= 10; i++) {
      final angle = startAngle + (sweepAngle * i / 10);
      final innerRadius = size.width / 2 - 20;
      final outerRadius = size.width / 2 - 10;
      final cx = size.width / 2;
      final cy = size.height;
      canvas.drawLine(
        Offset(cx + innerRadius * math.cos(angle), cy + innerRadius * math.sin(angle)),
        Offset(cx + outerRadius * math.cos(angle), cy + outerRadius * math.sin(angle)),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
