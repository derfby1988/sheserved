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
// Public shell/composition for the patient answer UI. It owns only transient
// presentation state (entrance/glow animations, confirmation dialog, and the
// scoped mobile orientation override). It never queries the database and
// never persists answers — confirm intents are delegated to the owner via
// [onConfirmAnswer], and draft selection is reported through
// [onDraftChanged] so the owner can keep drafts keyed by question id.
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
          ? null
          : () => widget.onConfirmAnswer!(index, label),
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
            // ── Background blur overlay ──
            Positioned.fill(
              child: GestureDetector(
                onTap: _close,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF0D1B2A).withValues(alpha: 0.65),
                            const Color(0xFF1B2838).withValues(alpha: 0.75),
                            const Color(0xFF0D1B2A).withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                              return RadialQuestionLayout(
                                question: ClosedEndedQuestionPrompt.circular(
                                  questionText: widget.questionText,
                                  key: const ValueKey(
                                    'closed-ended-question-center',
                                  ),
                                  size: radialSide * 0.28,
                                  pulseAnimation: _pulseController,
                                ),
                                optionCount: _optionCount,
                                optionSizeFactor: isQuantitative ? 0.14 : 0.24,
                                optionWidthBuilder: isQuantitative
                                    ? null
                                    : (context, index, side) {
                                        final maxWidth = math.min(
                                          112.0,
                                          side * 0.28,
                                        );
                                        return _qualitativeOptionWidth(
                                          context,
                                          options[index],
                                          maxWidth,
                                          minWidth: math.min(64.0, maxWidth),
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
                        ? ((contentWidth - 36) / 4).clamp(48.0, 72.0).toDouble()
                        : _qualitativeOptionWidth(context, label, contentWidth);
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

  /// ── Decorative orbit ring ──
  Widget _buildOrbitRing(double radius) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, _) {
        final pulseScale = 1.0 + (_pulseController.value * 0.015);
        return Transform.scale(
          scale: pulseScale,
          child: Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.05),
                width: 0.8,
              ),
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
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
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
              color: Colors.white.withValues(alpha: 0.7),
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}
