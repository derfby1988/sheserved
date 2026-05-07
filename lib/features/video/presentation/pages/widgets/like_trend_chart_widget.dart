import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import '../../../../../config/app_config.dart';

/// ✅ [Support Analytics] กราฟแนวโน้มยอดส่งกำลังใจ (Like Trend Chart)
///
/// - แสดง Area Chart แบบ Real-time โดยดึง 10-second bucket ย้อนหลัง 5 นาที (30 จุด)
/// - Polls ทุก 10 วินาที และ refresh ทันทีเมื่อ [triggerRefresh] เปลี่ยน
/// - ปุ่ม Toggle Like (+/♥) อยู่ที่ปลายขวาของกราฟ
class LikeTrendChartWidget extends StatefulWidget {
  final String videoId;
  final bool isLiked;
  final int likeCount;
  final VoidCallback onToggleLike;
  /// เปลี่ยนค่าเพื่อบังคับ refresh กราฟทันที (ใช้ timestamp หรือ counter)
  final int triggerRefresh;

  const LikeTrendChartWidget({
    super.key,
    required this.videoId,
    required this.isLiked,
    required this.likeCount,
    required this.onToggleLike,
    this.triggerRefresh = 0,
  });

  @override
  State<LikeTrendChartWidget> createState() => _LikeTrendChartWidgetState();
}

class _LikeTrendChartWidgetState extends State<LikeTrendChartWidget>
    with SingleTickerProviderStateMixin {
  List<FlSpot> _spots = [];
  Timer? _pollTimer;
  bool _isLoading = false;
  int _lastTrigger = 0;

  // Heart animation
  late AnimationController _heartCtrl;
  late Animation<double> _heartScale;

  static const _orange = Color(0xFFFF6B35);
  static const _orangeLight = Color(0xFFFF9F6B);
  static const _glass = Color(0xAA1A1A2E);

  @override
  void initState() {
    super.initState();
    _heartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _heartScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.5), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _heartCtrl, curve: Curves.easeOutBack));

    _loadTrend();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadTrend());
  }

  @override
  void didUpdateWidget(LikeTrendChartWidget old) {
    super.didUpdateWidget(old);
    // Refresh chart immediately when videoId changes or triggerRefresh increments
    if (old.videoId != widget.videoId) {
      setState(() => _spots = []);
      _loadTrend();
    } else if (old.triggerRefresh != widget.triggerRefresh && widget.triggerRefresh != _lastTrigger) {
      _lastTrigger = widget.triggerRefresh;
      _loadTrend();
    }
    // Play heart animation on new like
    if (!old.isLiked && widget.isLiked) {
      _heartCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _heartCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTrend() async {
    if (_isLoading || !mounted) return;
    _isLoading = true;
    try {
      final response = await http
          .get(Uri.parse(
              '${AppConfig.localApiUrl}/api/videos/${widget.videoId}/likes/trend'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200 && mounted) {
        final List data = jsonDecode(response.body);
        _buildSpots(data);
      }
    } catch (_) {
    } finally {
      _isLoading = false;
    }
  }

  void _buildSpots(List data) {
    // Fill 30 buckets: from (now - 290s) to (now) in 10-second intervals
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final nowBucket = (nowEpoch ~/ 10) * 10;
    final startBucket = nowBucket - 290;

    final bucketMap = <double, double>{};
    for (final d in data) {
      bucketMap[(d['bucket'] as num).toDouble()] =
          (d['count'] as num).toDouble();
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < 30; i++) {
      final bucket = (startBucket + i * 10).toDouble();
      spots.add(FlSpot(i.toDouble(), bucketMap[bucket] ?? 0));
    }
    if (mounted) setState(() => _spots = spots);
  }

  String _fmt(int n) {
    if (n >= 1000) {
      final k = n / 1000;
      return k == k.roundToDouble() ? '${k.round()}K' : '${k.toStringAsFixed(1)}K';
    }
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: _glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isLiked
              ? _orange.withOpacity(0.4)
              : Colors.white.withOpacity(0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            // ── Chart Area ────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                child: _spots.isEmpty || _spots.every((s) => s.y == 0)
                    ? Row(
                        children: [
                          Icon(Icons.show_chart_rounded,
                              size: 14, color: _orange.withOpacity(0.5)),
                          const SizedBox(width: 6),
                          Text(
                            'ยอดส่งกำลังใจ (5 นาทีล่าสุด)',
                            style: TextStyle(
                              fontFamily: 'SukhumvitSet',
                              fontSize: 10,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ],
                      )
                    : LineChart(
                        duration: const Duration(milliseconds: 300),
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          clipData: const FlClipData.all(),
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (_) =>
                                  const Color(0xEE2A2A2A),
                              tooltipRoundedRadius: 8,
                              getTooltipItems: (spots) => spots
                                  .map((s) => LineTooltipItem(
                                        '${s.y.toInt()} 💛',
                                        const TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'SukhumvitSet',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                          minX: 0,
                          maxX: 29,
                          minY: 0,
                          lineBarsData: [
                            LineChartBarData(
                              spots: _spots,
                              isCurved: true,
                              curveSmoothness: 0.35,
                              color: _orange,
                              barWidth: 2.5,
                              isStrokeCapRound: true,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  colors: [
                                    _orange.withOpacity(0.35),
                                    _orange.withOpacity(0.0),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),

            // ── Divider ───────────────────────────────────────────────
            Container(
              width: 1,
              height: 34,
              color: Colors.white.withOpacity(0.12),
            ),

            // ── Toggle Like Button ─────────────────────────────────────
            GestureDetector(
              onTap: widget.onToggleLike,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 52,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: widget.isLiked
                      ? LinearGradient(
                          colors: [
                            _orange.withOpacity(0.25),
                            _orange.withOpacity(0.10),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                      : null,
                ),
                child: AnimatedBuilder(
                  animation: _heartCtrl,
                  builder: (ctx, child) => Transform.scale(
                    scale: _heartScale.value,
                    child: child,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: Icon(
                          widget.isLiked
                              ? Icons.favorite_rounded
                              : Icons.add_circle_outline_rounded,
                          key: ValueKey(widget.isLiked),
                          color: widget.isLiked ? _orange : Colors.white70,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fmt(widget.likeCount),
                        style: TextStyle(
                          fontFamily: 'SukhumvitSet',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: widget.isLiked ? _orangeLight : Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
