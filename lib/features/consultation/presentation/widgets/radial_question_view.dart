import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../chat/data/models/closed_ended_config.dart';
import 'closed_ended/adaptive_closed_ended_layout.dart';
import 'closed_ended/closed_ended_confirmation_dialog.dart';
import 'closed_ended/closed_ended_glass_primitives.dart';
import 'closed_ended/closed_ended_option_tile.dart';
import 'closed_ended/closed_ended_question_prompt.dart';
import 'closed_ended/qualitative_question_options.dart';
import 'closed_ended/quantitative_question_options.dart';
import 'closed_ended/radial_question_layout.dart';

export '../../../chat/data/models/closed_ended_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Phase 6.14 — Radial Question View (Closed-ended Question, Patient Side)
//
// Glass Morphism UI ตามหลักการ Photoshop Glass Morphism Effect:
//   1. Atmospheric Background — ไล่เฉดสีทไวไลท์/ภูเขาและทะเลสาบ พร้อมแสงเรืองรอบข้าง
//   2. Rounded Shape / Circular Prompt — การ์ดตรงกลางพร้อมแสงเงาสะท้อนสมจริง
//   3. Gaussian Blur — BackdropFilter + ImageFilter.blur (sigma 18-24)
//   4. Gradient Overlay & Transparency — สีขาวโปร่งใส 50-70%
//   5. Highlights & Shadows — แสงสะท้อนขอบบน (Inner Shine) + ขอบเส้นคมขาวโปร่งใส 40%
//   6. Translucent Lines — เส้นเชื่อมโยง (Spokes) และเส้นวงโคจรโปร่งแสง
// ─────────────────────────────────────────────────────────────────────────────

class RadialQuestionView extends StatefulWidget {
  /// ข้อความคำถาม
  final String questionText;

  /// Immutable question definition (from `chat_messages.closed_ended_config`).
  final ClosedEndedConfig config;

  /// Restored draft selection for this question (keyed by question id in the
  /// owner), so reopening or rotating keeps the unfinished choice.
  final int? initialSelectedIndex;

  /// Reports draft selection changes to the owner/controller.
  final ValueChanged<int?>? onDraftChanged;

  /// Persist the confirmed answer. Must return `true` only when the server
  /// confirmed the write; on `false` the confirmation dialog stays open with
  /// an inline error so the patient can retry. When null (standalone mode)
  /// confirming resolves immediately.
  final Future<bool> Function(int index, String label)? onConfirmAnswer;

  /// Callback เมื่อเลือกคำตอบ (สำหรับ backward compatibility)
  final void Function(int index, String label)? onAnswerSelected;

  /// Called when the view should close — either the patient dismissed it
  /// (question keeps `reading` status) or the answer was saved (`answered`).
  final VoidCallback? onClose;

  /// รูปโปรไฟล์ Expert (URL)
  final String? expertAvatarUrl;

  /// ชื่อ Expert
  final String? expertName;

  const RadialQuestionView({
    super.key,
    required this.questionText,
    required this.config,
    this.initialSelectedIndex,
    this.onDraftChanged,
    this.onConfirmAnswer,
    this.onAnswerSelected,
    this.onClose,
    this.expertAvatarUrl,
    this.expertName,
  });

  @override
  State<RadialQuestionView> createState() => _RadialQuestionViewState();
}

class _RadialQuestionViewState extends State<RadialQuestionView>
    with TickerProviderStateMixin {
  // ── Animation controllers ──
  late AnimationController _flyInController;
  late AnimationController _pulseController;
  late AnimationController _glowController;

  int? _selectedIndex;
  bool _isConfirming = false;
  bool _orientationOverrideActive = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialSelectedIndex;

    // Fly-in animation (staggered)
    _flyInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Pulse animation สำหรับ center question
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // Glow animation เมื่อเลือกคำตอบ
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _allowDeviceRotation();

    // เริ่ม fly-in
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _flyInController.forward();
    });
  }

  @override
  void didUpdateWidget(covariant RadialQuestionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different question reuses this widget → restore that question's draft.
    if (oldWidget.questionText != widget.questionText ||
        oldWidget.config != widget.config) {
      setState(() {
        _selectedIndex = widget.initialSelectedIndex;
        _isConfirming = false;
      });
    }
  }

  bool get _supportsOrientationOverride {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
  }

  void _allowDeviceRotation() {
    if (!_supportsOrientationOverride) return;
    _orientationOverrideActive = true;
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
  }

  void _restorePortraitOrientation() {
    if (!_orientationOverrideActive) return;
    _orientationOverrideActive = false;
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]),
    );
  }

  void _close() {
    _restorePortraitOrientation();
    widget.onClose?.call();
  }

  @override
  void dispose() {
    _restorePortraitOrientation();
    _flyInController.dispose();
    _pulseController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  /// จำนวนตัวเลือกทั้งหมด
  int get _optionCount => widget.config.effectiveOptions.length;

  /// สีของตัวเลือก index
  Color _optionColor(int index) {
    return widget.config.type == ClosedEndedType.quantitative
        ? QuantitativeQuestionOptions.colorForIndex(index, _optionCount)
        : QualitativeQuestionOptions.colorForIndex(index);
  }

  void _onOptionTap(int index) {
    if (_isConfirming) return;

    HapticFeedback.mediumImpact();
    if (_selectedIndex != index) {
      setState(() => _selectedIndex = index);
      widget.onDraftChanged?.call(index);
      _glowController.forward(from: 0);
    }

    // แสดง Confirm Dialog
    _showConfirmDialog(index);
  }

  Future<void> _showConfirmDialog(int index) async {
    final label = widget.config.effectiveOptions[index];
    setState(() => _isConfirming = true);

    final confirmed = await ClosedEndedConfirmationDialog.show(
      context,
      questionText: widget.questionText,
      selectedLabel: label,
      selectedIndex: index,
      optionColor: _optionColor(index),
      isQuantitative: widget.config.type == ClosedEndedType.quantitative,
      onConfirm: widget.onConfirmAnswer == null
          ? () async {
              widget.onAnswerSelected?.call(index, label);
              return true;
            }
          : () async {
              final result = await widget.onConfirmAnswer!(index, label);
              if (result) {
                widget.onAnswerSelected?.call(index, label);
              }
              return result;
            },
    );

    if (!mounted) return;
    if (confirmed == true) {
      _restorePortraitOrientation();
      widget.onClose?.call();
    } else {
      setState(() {
        _selectedIndex = null;
        _isConfirming = false;
      });
      widget.onDraftChanged?.call(null);
      _glowController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final options = widget.config.effectiveOptions;

    return Material(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, _) => Stack(
          children: [
            // ── Background: บรรยากาศทไวไลท์/ภูเขาและทะเลสาบตามแบบภาพตัวอย่าง (Step 1) ──
            Positioned.fill(
              child: GestureDetector(
                onTap: _close,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. ไล่เฉดสีลึก ฟ้าเข้ม-ม่วง-คราม (Mountain & Lake Sunset Tone)
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFF0A1128), // Deep twilight navy
                            Color(0xFF161B3A), // Twilight mountain purple
                            Color(0xFF261D3B), // Horizon dusk magenta
                            Color(0xFF18233C), // Reflective lake deep blue
                            Color(0xFF090E1F), // Dark base
                          ],
                          stops: [0.0, 0.25, 0.55, 0.80, 1.0],
                        ),
                      ),
                    ),

                    // 2. แสงเรืองบรรยากาศ (Ambient Sunset Lake Glows) เพื่อให้กระจกมีแสงสะท้อนจริง
                    Positioned(
                      top: media.size.height * 0.18,
                      right: -media.size.width * 0.15,
                      child: Container(
                        width: media.size.width * 0.75,
                        height: media.size.width * 0.75,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFF38BDF8).withValues(alpha: 0.16),
                              const Color(0xFF818CF8).withValues(alpha: 0.08),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: media.size.height * 0.22,
                      left: -media.size.width * 0.20,
                      child: Container(
                        width: media.size.width * 0.85,
                        height: media.size.width * 0.85,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFFE27D60).withValues(alpha: 0.18),
                              const Color(0xFFC084FC).withValues(alpha: 0.08),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 3. ฟิลเตอร์ Gaussian Blur บางๆ ทั่วทั้งพื้นหลังให้เนียนตา
                    BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.15),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Positioned.fill(
              child: AdaptiveClosedEndedLayout(
                questionText: widget.questionText,
                options: options,
                radialTopInset: media.padding.top + 64,
                radialBottomInset: media.padding.bottom + 16,
                builder: (context, constraints, mode) {
                  final isQuantitative =
                      widget.config.type == ClosedEndedType.quantitative;
                  if (mode == ClosedEndedLayoutMode.radial) {
                    return Stack(
                      children: [
                        Positioned.fill(
                          top: media.padding.top + 64,
                          bottom: media.padding.bottom + 16,
                          child: LayoutBuilder(
                            builder: (context, radialConstraints) {
                              final radialSide = math.min(
                                radialConstraints.maxWidth,
                                radialConstraints.maxHeight,
                              );
                              final orbitRadius = radialSide * 0.32;
                              final centerRadius = radialSide * 0.14;

                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  // ── เส้นเชื่อมต่อโปร่งแสง (Translucent Spokes) จาก Card กลางไปแต่ละตัวเลือก ──
                                  _buildConnectingLines(
                                    orbitRadius: orbitRadius,
                                    centerRadius: centerRadius,
                                    size: radialSide,
                                  ),

                                  // ── Radial question layout (Center card + Orbit ring + Options) ──
                                  RadialQuestionLayout(
                                    question: ClosedEndedQuestionPrompt.circular(
                                      questionText: widget.questionText,
                                      key: const ValueKey(
                                        'closed-ended-question-center',
                                      ),
                                      size: radialSide * 0.28,
                                      pulseAnimation: _pulseController,
                                    ),
                                    optionCount: _optionCount,
                                    optionSizeFactor:
                                        isQuantitative ? 0.14 : 0.24,
                                    optionWidthBuilder: isQuantitative
                                        ? null
                                        : (context, index, side) {
                                            final maxWidth = math
                                                .max(
                                                  64.0,
                                                  (side / 2) -
                                                      (side * 0.14) -
                                                      24,
                                                )
                                                .toDouble();
                                            return _qualitativeOptionWidth(
                                              context,
                                              options[index],
                                              maxWidth,
                                              minWidth:
                                                  math.min(64.0, maxWidth),
                                            );
                                          },
                                    startAngle: isQuantitative
                                        ? -math.pi / 2
                                        : -math.pi / 2 - math.pi / _optionCount,
                                    entranceAnimation: _flyInController,
                                    orbitRing: _buildOrbitRing(orbitRadius),
                                    optionBuilder: (context, index, size) =>
                                        _buildOptionButton(
                                          index: index,
                                          size: size,
                                        ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  }

                  final contentWidth = math
                      .min(constraints.maxWidth - 32, 640.0)
                      .clamp(0.0, 640.0)
                      .toDouble();
                  final optionWidgets = List.generate(_optionCount, (index) {
                    final label = options[index];
                    final optionSize = isQuantitative
                        ? ((contentWidth - 36) / 4)
                            .clamp(48.0, 72.0)
                            .toDouble()
                        : _qualitativeOptionWidth(
                            context,
                            label,
                            contentWidth,
                          );
                    return _buildOptionButton(
                      index: index,
                      size: optionSize,
                      compact: true,
                    );
                  });
                  final optionGroup = isQuantitative
                      ? QuantitativeQuestionOptions(options: optionWidgets)
                      : QualitativeQuestionOptions(options: optionWidgets);

                  return SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 64, 16, 16),
                      child: SingleChildScrollView(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClosedEndedQuestionPrompt.compact(
                                  questionText: widget.questionText,
                                  width: contentWidth,
                                ),
                                const SizedBox(height: 20),
                                optionGroup,
                                const SizedBox(height: 16),
                                _buildHintText(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Back button (top-left) ──
            Positioned(
              top: media.padding.top + 12,
              left: 16,
              child: GlassIconButton(
                icon: Icons.close_rounded,
                onTap: _close,
                semanticsLabel: 'ปิดคำถาม',
              ),
            ),

            // ── Expert info (top-center) ──
            if (widget.expertName != null)
              Positioned(
                top: media.padding.top + 16,
                left: 0,
                right: 0,
                child: Center(
                  child: GlassBadge(
                    text: widget.expertName!,
                    avatarUrl: widget.expertAvatarUrl,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// ── 1. เส้นเชื่อมต่อโปร่งแสง (Translucent Spokes) จาก Card กลางไปแต่ละตัวเลือก ──
  Widget _buildConnectingLines({
    required double orbitRadius,
    required double centerRadius,
    required double size,
  }) {
    final isQuantitative = widget.config.type == ClosedEndedType.quantitative;
    final startAngle = isQuantitative
        ? -math.pi / 2
        : -math.pi / 2 - math.pi / _optionCount;

    return AnimatedBuilder(
      animation: _flyInController,
      builder: (context, child) {
        return CustomPaint(
          size: Size(size, size),
          painter: _RadialConnectingLinesPainter(
            optionCount: _optionCount,
            centerRadius: centerRadius,
            orbitRadius: orbitRadius,
            startAngle: startAngle,
            selectedIndex: _selectedIndex,
            optionColor: _optionColor,
            animationValue: _flyInController.value,
          ),
        );
      },
    );
  }

  /// ── 2. Decorative orbit ring ──
  Widget _buildOrbitRing(double radius) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulseScale = 1.0 + (_pulseController.value * 0.015);
        return Transform.scale(
          scale: pulseScale,
          child: Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.04),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _qualitativeOptionWidth(
    BuildContext context,
    String label,
    double maxWidth, {
    double minWidth = 112,
  }) {
    if (maxWidth <= 0) return maxWidth;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontFamily: 'SukhumvitSet',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = (painter.width + 32)
        .clamp(math.min(minWidth, maxWidth), maxWidth)
        .toDouble();
    painter.dispose();
    return width;
  }

  /// ── Single option button (orbiting) ──
  Widget _buildOptionButton({
    required int index,
    required double size,
    bool compact = false,
  }) {
    final label = widget.config.effectiveOptions[index];
    final color = _optionColor(index);
    final isSelected = _selectedIndex == index;
    final isQuantitative = widget.config.type == ClosedEndedType.quantitative;

    return ClosedEndedOptionTile(
      key: ValueKey('closed-ended-option-$index'),
      index: index,
      label: label,
      isSelected: isSelected,
      onTap: () => _onOptionTap(index),
      child: isQuantitative
          ? QuantitativeAnswerOption(
              label: label,
              color: color,
              size: size,
              isSelected: isSelected,
              glowAnimation: _glowController,
            )
          : QualitativeAnswerOption(
              label: label,
              color: color,
              width: size,
              minHeight: compact ? 52 : math.max(44.0, size * 0.55),
              isSelected: isSelected,
              compact: compact,
              glowAnimation: _glowController,
            ),
    );
  }

  /// ── Hint text at bottom ──
  Widget _buildHintText() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
              ),
            ],
          ),
          child: Text(
            widget.config.type == ClosedEndedType.quantitative
                ? 'เลือกระดับที่ตรงกับอาการของคุณ'
                : 'แตะคำตอบที่ตรงกับคุณมากที่สุด',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'SukhumvitSet',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS — รูปทรงเส้นโปร่งใสและสีตามภาพตัวอย่าง
// ═══════════════════════════════════════════════════════════════════════════════

/// Painter วาดเส้นเชื่อมต่อโปร่งแสง (Radial Spokes) จากศูนย์กลางไปยังแต่ละตัวเลือก
class _RadialConnectingLinesPainter extends CustomPainter {
  final int optionCount;
  final double centerRadius;
  final double orbitRadius;
  final double startAngle;
  final int? selectedIndex;
  final Color Function(int) optionColor;
  final double animationValue;

  _RadialConnectingLinesPainter({
    required this.optionCount,
    required this.centerRadius,
    required this.orbitRadius,
    required this.startAngle,
    this.selectedIndex,
    required this.optionColor,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (optionCount <= 0 || animationValue <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);

    for (int i = 0; i < optionCount; i++) {
      final angle = startAngle + (2 * math.pi * i / optionCount);
      final isSelected = selectedIndex == i;
      final color = optionColor(i);

      // เริ่มจากขอบ Card กลางไปยังปุ่มตัวเลือก
      final startOffset = Offset(
        center.dx + (centerRadius * 0.95) * math.cos(angle),
        center.dy + (centerRadius * 0.95) * math.sin(angle),
      );
      final targetEnd = Offset(
        center.dx + (orbitRadius * 0.86) * math.cos(angle),
        center.dy + (orbitRadius * 0.86) * math.sin(angle),
      );

      final currentEnd = Offset.lerp(
        startOffset,
        targetEnd,
        animationValue.clamp(0.0, 1.0),
      )!;

      // เรืองแสงนุ่มๆ ด้านหลังเส้นที่เลือก
      if (isSelected) {
        final glowPaint = Paint()
          ..color = color.withValues(alpha: 0.45)
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawLine(startOffset, currentEnd, glowPaint);
      }

      // เส้นกระจกโปร่งแสง (Translucent Glass Line สอดคล้องภาพตัวอย่าง)
      final linePaint = Paint()
        ..color = isSelected
            ? color.withValues(alpha: 0.90)
            : Colors.white.withValues(alpha: 0.22)
        ..strokeWidth = isSelected ? 2.2 : 1.2
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(startOffset, currentEnd, linePaint);

      // จุดเชื่อมต่อกลมโปร่งแสงเล็กๆ (Connecting Node)
      final nodePaint = Paint()
        ..color = isSelected
            ? color.withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(startOffset, isSelected ? 3.0 : 2.0, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadialConnectingLinesPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.optionCount != optionCount ||
        oldDelegate.startAngle != startAngle;
  }
}
