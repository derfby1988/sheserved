import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Phase 6.14 — Radial Question View (Closed-ended Question, Patient Side)
//
// Glass Morphism UI สำหรับแสดงคำถามปลายปิดฝั่งผู้ป่วย
// คำถามอยู่ตรงกลาง + ตัวเลือกคำตอบกระจายล้อมรอบแบบ Radial/Circular
//
// หลักการ Glass Morphism ที่ใช้ (สอดคล้อง glass_card.dart, glassmorphism_button.dart):
//   1. BackdropFilter + ImageFilter.blur — เบลอพื้นหลัง (sigma 10-20)
//   2. Semi-transparent fill — สีขาว 15-30% opacity
//   3. Gradient overlay — inner shine ด้านบนสว่าง
//   4. Subtle border — ขอบขาว 30-50% opacity
//   5. Box shadow — เงาอ่อนๆ ให้มีมิติ
//   6. Border radius — มุมโค้งมน 16-24
// ─────────────────────────────────────────────────────────────────────────────

/// ประเภทคำถามปลายปิด
enum ClosedEndedType { quantitative, qualitative }

/// Config ข้อมูลคำถามปลายปิด (จาก JSONB `closed_ended_config`)
class ClosedEndedConfig {
  final ClosedEndedType type;
  final int answerCount;
  final int? scaleLevels; // 3, 5, 10 (เฉพาะ quantitative)
  final List<String>? options; // ตัวเลือกข้อความ (เฉพาะ qualitative)
  final String? selectedOption;
  final int? selectedIndex;
  final DateTime? selectedAt;

  const ClosedEndedConfig({
    required this.type,
    required this.answerCount,
    this.scaleLevels,
    this.options,
    this.selectedOption,
    this.selectedIndex,
    this.selectedAt,
  });

  factory ClosedEndedConfig.fromJson(Map<String, dynamic> json) {
    return ClosedEndedConfig(
      type: json['type'] == 'quantitative'
          ? ClosedEndedType.quantitative
          : ClosedEndedType.qualitative,
      answerCount: json['answer_count'] ?? 2,
      scaleLevels: json['scale_levels'],
      options: (json['options'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      selectedOption: json['selected_option'],
      selectedIndex: json['selected_index'],
      selectedAt: json['selected_at'] != null
          ? DateTime.tryParse(json['selected_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type == ClosedEndedType.quantitative
            ? 'quantitative'
            : 'qualitative',
        'answer_count': answerCount,
        if (scaleLevels != null) 'scale_levels': scaleLevels,
        if (options != null) 'options': options,
        if (selectedOption != null) 'selected_option': selectedOption,
        if (selectedIndex != null) 'selected_index': selectedIndex,
        if (selectedAt != null) 'selected_at': selectedAt!.toIso8601String(),
      };

  /// สร้าง label ตัวเลือกสำหรับ quantitative
  List<String> get effectiveOptions {
    if (type == ClosedEndedType.qualitative) {
      return options ?? [];
    }
    // quantitative → สร้างตัวเลข 1..N
    final n = scaleLevels ?? 3;
    return List.generate(n, (i) => '${i + 1}');
  }

  bool get isAnswered => selectedOption != null;
}

/// ──────────────────────────────────────────────────────────────────────
/// RadialQuestionView — Widget หลักสำหรับแสดง Radial UI ฝั่งผู้ป่วย
/// ──────────────────────────────────────────────────────────────────────
class RadialQuestionView extends StatefulWidget {
  /// ข้อความคำถาม
  final String questionText;

  /// Config คำถามปลายปิด
  final ClosedEndedConfig config;

  /// Callback เมื่อเลือกคำตอบ (index, label)
  final void Function(int index, String label)? onAnswerSelected;

  /// Callback เมื่อกดปิด/ย้อนกลับ
  final VoidCallback? onClose;

  /// รูปโปรไฟล์ Expert (URL)
  final String? expertAvatarUrl;

  /// ชื่อ Expert
  final String? expertName;

  const RadialQuestionView({
    super.key,
    required this.questionText,
    required this.config,
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

  // สี gradient สำหรับ quantitative (เขียว → เหลือง → แดง)
  static const _quantitativeColors = [
    Color(0xFF4CAF50), // เขียว (ระดับต่ำ)
    Color(0xFF8BC34A),
    Color(0xFFCDDC39),
    Color(0xFFFFEB3B), // เหลือง (กลาง)
    Color(0xFFFFC107),
    Color(0xFFFF9800),
    Color(0xFFFF5722),
    Color(0xFFF44336), // แดง (ระดับสูง)
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
  ];

  // สี teal shades สำหรับ qualitative
  static const _qualitativeColors = [
    Color(0xFF00897B),
    Color(0xFF00796B),
    Color(0xFF00695C),
    Color(0xFF00BFA5),
    Color(0xFF1DE9B6),
    Color(0xFF64FFDA),
    Color(0xFF26A69A),
    Color(0xFF4DB6AC),
    Color(0xFF80CBC4),
    Color(0xFFB2DFDB),
  ];

  @override
  void initState() {
    super.initState();

    // Fly-in animation (500ms total, staggered)
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

    // เริ่ม fly-in
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _flyInController.forward();
    });
  }

  @override
  void dispose() {
    _flyInController.dispose();
    _pulseController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  /// จำนวนตัวเลือกทั้งหมด
  int get _optionCount => widget.config.effectiveOptions.length;

  /// สีของตัวเลือก index
  Color _optionColor(int index) {
    if (widget.config.type == ClosedEndedType.quantitative) {
      final ratio = _optionCount > 1 ? index / (_optionCount - 1) : 0.0;
      final colorIndex =
          (ratio * (_quantitativeColors.length - 1)).round().clamp(0, _quantitativeColors.length - 1);
      return _quantitativeColors[colorIndex];
    }
    return _qualitativeColors[index % _qualitativeColors.length];
  }

  /// คำนวณตำแหน่งของแต่ละตัวเลือกรอบวงกลม
  Offset _optionPosition(int index, double radius) {
    // เริ่มจากด้านบน (-π/2) และกระจายรอบวง
    final angle = -math.pi / 2 + (2 * math.pi * index / _optionCount);
    return Offset(
      radius * math.cos(angle),
      radius * math.sin(angle),
    );
  }

  void _onOptionTap(int index) {
    if (_isConfirming || _selectedIndex != null) return;

    HapticFeedback.mediumImpact();
    setState(() => _selectedIndex = index);
    _glowController.forward();

    // แสดง Confirm Dialog
    _showConfirmDialog(index);
  }

  void _showConfirmDialog(int index) {
    final label = widget.config.effectiveOptions[index];
    setState(() => _isConfirming = true);

    showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: _GlassConfirmCard(
            questionText: widget.questionText,
            selectedLabel: label,
            selectedIndex: index,
            optionColor: _optionColor(index),
            isQuantitative:
                widget.config.type == ClosedEndedType.quantitative,
            onConfirm: () {
              Navigator.of(ctx).pop(true);
            },
            onCancel: () {
              Navigator.of(ctx).pop(false);
            },
          ),
        ),
      ),
    ).then((confirmed) {
      if (!mounted) return;
      if (confirmed == true) {
        widget.onAnswerSelected?.call(index, label);
      } else {
        setState(() {
          _selectedIndex = null;
          _isConfirming = false;
        });
        _glowController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final shortSide = math.min(screenSize.width, screenSize.height);

    // คำนวณรัศมีวงกลม (ยืดหยุ่นตาม screen size)
    final centerRadius = shortSide * 0.14; // ขนาดศูนย์กลาง
    final orbitRadius = shortSide * 0.32; // รัศมีวงโคจร
    final optionSize = widget.config.type == ClosedEndedType.quantitative
        ? shortSide * 0.12  // ปุ่มตัวเลข (กลม)
        : shortSide * 0.18; // card ข้อความ (ใหญ่กว่า)

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // ── Background blur overlay ──
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onClose,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF0D1B2A).withOpacity(0.65),
                          const Color(0xFF1B2838).withOpacity(0.75),
                          const Color(0xFF0D1B2A).withOpacity(0.85),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Back button (top-left) ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: _GlassIconButton(
              icon: Icons.close_rounded,
              onTap: widget.onClose,
            ),
          ),

          // ── Expert info (top-center) ──
          if (widget.expertName != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 0,
              right: 0,
              child: Center(
                child: _GlassBadge(
                  text: widget.expertName!,
                  avatarUrl: widget.expertAvatarUrl,
                ),
              ),
            ),

          // ── Center question circle + orbiting options ──
          Center(
            child: SizedBox(
              width: (orbitRadius + optionSize) * 2,
              height: (orbitRadius + optionSize) * 2,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // ── Orbit ring (decorative) ──
                  _buildOrbitRing(orbitRadius),

                  // ── Center question card ──
                  _buildCenterQuestion(centerRadius),

                  // ── Orbiting option buttons ──
                  ...List.generate(_optionCount, (i) {
                    final pos = _optionPosition(i, orbitRadius);
                    return _buildOptionButton(
                      index: i,
                      offset: pos,
                      size: optionSize,
                    );
                  }),
                ],
              ),
            ),
          ),

          // ── Hint text (bottom) ──
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 32,
            right: 32,
            child: _buildHintText(),
          ),
        ],
      ),
    );
  }

  /// ── Decorative orbit ring ──
  Widget _buildOrbitRing(double radius) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        final pulseScale = 1.0 + (_pulseController.value * 0.015);
        return Transform.scale(
          scale: pulseScale,
          child: Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.05),
                width: 0.8,
              ),
            ),
          ),
        );
      },
    );
  }

  /// ── Center question glass card ──
  Widget _buildCenterQuestion(double radius) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        final scale = 1.0 + (_pulseController.value * 0.03);
        return Transform.scale(
          scale: scale,
          child: _GlassCircleCard(
            size: radius * 2,
            glassOpacity: 0.10,
            blurSigma: 24,
            borderOpacity: 0.18,
            innerShineOpacity: 0.10,
            shadowColor: const Color(0xFF00BCD4).withOpacity(0.08),
            shadowBlur: 40,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.quiz_rounded,
                    size: 22,
                    color: Colors.white.withOpacity(0.7),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.questionText,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'SukhumvitSet',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// ── Single option button (orbiting) ──
  Widget _buildOptionButton({
    required int index,
    required Offset offset,
    required double size,
  }) {
    final label = widget.config.effectiveOptions[index];
    final color = _optionColor(index);
    final isSelected = _selectedIndex == index;
    final isQuantitative =
        widget.config.type == ClosedEndedType.quantitative;

    // Stagger delay: 100ms per option
    final staggerInterval = _optionCount > 1
        ? Interval(
            (index * 0.08).clamp(0.0, 0.6),
            ((index * 0.08) + 0.4).clamp(0.0, 1.0),
            curve: Curves.elasticOut,
          )
        : const Interval(0.0, 1.0, curve: Curves.elasticOut);

    return AnimatedBuilder(
      animation: _flyInController,
      builder: (_, child) {
        final t = staggerInterval.transform(_flyInController.value);
        // Fly in from edge towards final position
        final flyScale = t;
        final flyOffset = Offset(
          offset.dx * (1 + (1 - t) * 1.5),
          offset.dy * (1 + (1 - t) * 1.5),
        );

        return Transform.translate(
          offset: Offset.lerp(flyOffset, offset, t)!,
          child: Transform.scale(
            scale: flyScale,
            child: Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: child,
            ),
          ),
        );
      },
      child: GestureDetector(
        onTap: () => _onOptionTap(index),
        child: AnimatedBuilder(
          animation: _glowController,
          builder: (_, __) {
            final glowScale = isSelected
                ? 1.0 + (_glowController.value * 0.15)
                : 1.0;
            final glowOpacity = isSelected
                ? 0.25 + (_glowController.value * 0.3)
                : 0.0;

            return Transform.scale(
              scale: glowScale,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Glow behind selected option
                  if (isSelected)
                    Container(
                      width: size + 16,
                      height: size + 16,
                      decoration: BoxDecoration(
                        shape: isQuantitative
                            ? BoxShape.circle
                            : BoxShape.rectangle,
                        borderRadius: isQuantitative
                            ? null
                            : BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(glowOpacity),
                            blurRadius: 24,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                    ),

                  // Glass option card
                  isQuantitative
                      ? _GlassCircleCard(
                          size: size,
                          glassOpacity: isSelected ? 0.18 : 0.08,
                          blurSigma: 22,
                          borderColor: color.withOpacity(0.25),
                          borderOpacity: 0.20,
                          innerShineOpacity: 0.10,
                          tintColor: color.withOpacity(0.06),
                          shadowColor: color.withOpacity(0.08),
                          shadowBlur: 20,
                          child: Center(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontFamily: 'SukhumvitSet',
                                fontSize: size * 0.32,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: color.withOpacity(0.6),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : _GlassRoundedCard(
                          width: size,
                          minHeight: size * 0.55,
                          glassOpacity: isSelected ? 0.16 : 0.07,
                          blurSigma: 22,
                          borderColor: color.withOpacity(0.18),
                          borderOpacity: 0.18,
                          innerShineOpacity: 0.08,
                          tintColor: color.withOpacity(0.05),
                          shadowColor: color.withOpacity(0.06),
                          shadowBlur: 18,
                          borderRadius: 18,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'SukhumvitSet',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                ],
              ),
            );
          },
        ),
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
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 1,
            ),
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
              color: Colors.white.withOpacity(0.7),
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GLASS MORPHISM PRIMITIVE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

/// ── Glass Circle Card ──
/// การ์ดกระจกทรงกลม พร้อม inner shine + gradient overlay
class _GlassCircleCard extends StatelessWidget {
  final double size;
  final double glassOpacity;
  final double blurSigma;
  final double borderOpacity;
  final double innerShineOpacity;
  final Color? borderColor;
  final Color? tintColor;
  final Color? shadowColor;
  final double? shadowBlur;
  final Widget child;

  const _GlassCircleCard({
    required this.size,
    required this.child,
    this.glassOpacity = 0.10,
    this.blurSigma = 22,
    this.borderOpacity = 0.18,
    this.innerShineOpacity = 0.10,
    this.borderColor,
    this.tintColor,
    this.shadowColor,
    this.shadowBlur,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          if (shadowColor != null)
            BoxShadow(
              color: shadowColor!,
              blurRadius: shadowBlur ?? 16,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Stack(
            children: [
              // Layer 1: Glass base gradient
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(glassOpacity * 0.6),
                      Colors.white.withOpacity(glassOpacity),
                      Colors.white.withOpacity(glassOpacity * 0.8),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  border: Border.all(
                    color: borderColor ??
                        Colors.white.withOpacity(borderOpacity),
                    width: 0.8,
                  ),
                ),
              ),

              // Layer 2: Inner shine (ด้านบนสว่างกว่า — เลียนแบบแสงสะท้อน)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: size * 0.18,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(innerShineOpacity),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Layer 3: Tint overlay (สีอ่อนๆ)
              if (tintColor != null)
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment.topLeft,
                      radius: 1.2,
                      colors: [
                        tintColor!,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),

              // Layer 4: Content
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// ── Glass Rounded Card ──
/// การ์ดกระจกมุมโค้ง สำหรับตัวเลือกเชิงคุณภาพ
class _GlassRoundedCard extends StatelessWidget {
  final double width;
  final double? minHeight;
  final double glassOpacity;
  final double blurSigma;
  final double borderOpacity;
  final double innerShineOpacity;
  final double borderRadius;
  final Color? borderColor;
  final Color? tintColor;
  final Color? shadowColor;
  final double? shadowBlur;
  final Widget child;

  const _GlassRoundedCard({
    required this.width,
    required this.child,
    this.minHeight,
    this.glassOpacity = 0.10,
    this.blurSigma = 22,
    this.borderOpacity = 0.18,
    this.innerShineOpacity = 0.10,
    this.borderRadius = 18,
    this.borderColor,
    this.tintColor,
    this.shadowColor,
    this.shadowBlur,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: BoxConstraints(minHeight: minHeight ?? 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          if (shadowColor != null)
            BoxShadow(
              color: shadowColor!,
              blurRadius: shadowBlur ?? 16,
              spreadRadius: 1,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Stack(
            children: [
              // Layer 1: Glass base
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(glassOpacity * 0.55),
                      Colors.white.withOpacity(glassOpacity),
                      Colors.white.withOpacity(glassOpacity * 0.85),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  border: Border.all(
                    color: borderColor ??
                        Colors.white.withOpacity(borderOpacity),
                    width: 0.8,
                  ),
                ),
              ),

              // Layer 2: Inner shine
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: (minHeight ?? 60) * 0.18,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(borderRadius),
                      topRight: Radius.circular(borderRadius),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(innerShineOpacity),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Layer 3: Tint
              if (tintColor != null)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(borderRadius),
                      gradient: RadialGradient(
                        center: Alignment.topLeft,
                        radius: 1.15,
                        colors: [
                          tintColor!,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

              // Layer 4: Content
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// ── Glass Icon Button (Close/Back) ──
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _GlassIconButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withOpacity(0.15),
                width: 0.8,
              ),
            ),
            child: Icon(icon, color: Colors.white.withOpacity(0.8), size: 22),
          ),
        ),
      ),
    );
  }
}

/// ── Glass Badge (Expert Info) ──
class _GlassBadge extends StatelessWidget {
  final String text;
  final String? avatarUrl;

  const _GlassBadge({required this.text, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.12),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white.withOpacity(0.2),
                backgroundImage:
                    avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                child: avatarUrl == null
                    ? Icon(
                        Icons.person,
                        size: 16,
                        color: Colors.white.withOpacity(0.6),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  fontFamily: 'SukhumvitSet',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ── Glass Confirm Card (Dialog ยืนยันคำตอบ) ──
class _GlassConfirmCard extends StatelessWidget {
  final String questionText;
  final String selectedLabel;
  final int selectedIndex;
  final Color optionColor;
  final bool isQuantitative;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _GlassConfirmCard({
    required this.questionText,
    required this.selectedLabel,
    required this.selectedIndex,
    required this.optionColor,
    required this.isQuantitative,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            // ── Glass Morphism: gradient base ──
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.10),
                Colors.white.withOpacity(0.07),
                Colors.white.withOpacity(0.04),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
            // ── Subtle border ──
            border: Border.all(
              color: Colors.white.withOpacity(0.18),
              width: 0.8,
            ),
            // ── Shadow ──
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 30,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: optionColor.withOpacity(0.10),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Stack(
            children: [
              // ── Inner shine (top) ──
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 60,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // ── Content ──
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 36,
                    color: optionColor.withOpacity(0.9),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'ยืนยันคำตอบ',
                    style: TextStyle(
                      fontFamily: 'SukhumvitSet',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Selected answer chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: optionColor.withOpacity(0.20),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: optionColor.withOpacity(0.40),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isQuantitative)
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: optionColor.withOpacity(0.3),
                            ),
                            child: Center(
                              child: Text(
                                selectedLabel,
                                style: const TextStyle(
                                  fontFamily: 'SukhumvitSet',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        if (isQuantitative) const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            isQuantitative
                                ? 'ระดับ $selectedLabel'
                                : selectedLabel,
                            style: const TextStyle(
                              fontFamily: 'SukhumvitSet',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Question excerpt
                  Text(
                    questionText,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'SukhumvitSet',
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.55),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: _GlassActionButton(
                          label: 'เปลี่ยน',
                          onTap: onCancel,
                          isFilled: false,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _GlassActionButton(
                          label: 'ยืนยัน',
                          onTap: onConfirm,
                          isFilled: true,
                          fillColor: optionColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ── Glass Action Button (Confirm/Cancel) ──
class _GlassActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isFilled;
  final Color? fillColor;

  const _GlassActionButton({
    required this.label,
    this.onTap,
    this.isFilled = false,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isFilled
                  ? (fillColor ?? Colors.white).withOpacity(0.30)
                  : Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isFilled
                    ? (fillColor ?? Colors.white).withOpacity(0.50)
                    : Colors.white.withOpacity(0.20),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'SukhumvitSet',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withOpacity(isFilled ? 1.0 : 0.7),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
