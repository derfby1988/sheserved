import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic_inset.dart';

/// ตัวสลับหน้า + ruler ของ Sports Hub
///
/// - ปุ่มหน้า 3 ปุ่มอยู่แถวบน (ผิวแก้วขาวใสเมื่อถูกเลือก)
/// - ลูกศรซ้าย/ขวาย้ายมาอยู่บรรทัดเดียวกับ ruler ด้านล่าง
/// - ruler เลียนแบบรางของ slider "คะแนนขั้นต่ำ" ใน `coach_filter_sheet.dart`
///   (รางจม [NeumorphicInsetPainter]) แต่คงหัวหมุดแก้วขาวของเดิมไว้
///   (ขยายให้กว้างขึ้นตามแนวนอนเป็น 32px)
/// - หัวหมุด/ป้ายขยับตาม [page] ที่ส่งมาจาก `PageView` แบบเรียลไทม์
///   (ไม่ต้องรออนิเมชันเปลี่ยนหน้าจบ) และ snap ทีละหน้าตลอดการลาก ruler
/// - หลังเปลี่ยนหน้าแล้วเข้าที่ (แตะ/ลูกศร/ปัด/ลาก ruler) ปุ่มที่ถูกเลือกจะ
///   "เขย่า" (เอียงซ้าย-ขวา) เบา ๆ ก่อนหยุด
class SportsHubPageIndicator extends StatefulWidget {
  /// ตำแหน่งหน้าปัจจุบันแบบต่อเนื่อง (เช่น 1.35) จาก `PageView`
  ///
  /// ส่งค่าต่อเนื่องเพื่อให้หัวหมุด/ปุ่มที่เลือกขยับตามการปัดหรืออนิเมชัน
  /// ของ `PageView` แบบทันที ไม่หน่วงรอ `onPageChanged`
  final double page;

  /// เลือกหน้าด้วยการแตะปุ่ม/ลูกศร (ให้ parent เล่นอนิเมชัน)
  final ValueChanged<int> onPageSelected;

  /// Key ของ Transform ที่ใช้เขย่าปุ่ม (เปิดให้ test อ้างอิงได้)
  static const shakeKey = Key('sportsHubButtonShake');

  /// ลาก ruler — เรียกทุกครั้งที่ snap ไปหน้าใหม่ระหว่างลาก
  /// (ให้ parent กระโดดไปหน้านั้นทันที) ถ้าไม่ส่ง จะ commit ตอนปล่อยนิ้ว
  /// ผ่าน [onPageSelected] แทน
  final ValueChanged<int>? onPageScrubbed;

  const SportsHubPageIndicator({
    super.key,
    required this.page,
    required this.onPageSelected,
    this.onPageScrubbed,
  });

  @override
  State<SportsHubPageIndicator> createState() => _SportsHubPageIndicatorState();
}

class _SportsHubPageIndicatorState extends State<SportsHubPageIndicator> {
  static const _destinations = [
    _SportsHubDestination(
      shortTitle: 'สนาม',
      title: 'จองสนามเล่นกีฬา',
      icon: Icons.sports_tennis_rounded,
    ),
    _SportsHubDestination(
      shortTitle: 'ก๊วน',
      title: 'หาเพื่อนออกกำลังกาย',
      icon: Icons.groups_rounded,
    ),
    _SportsHubDestination(
      shortTitle: 'โค้ช',
      title: 'หาโค้ช/เทรนเนอร์',
      icon: Icons.school_rounded,
    ),
  ];

  static const _buttonRowHeight = 44.0;
  static const _arrowWidth = 44.0;

  /// ความสูงร่องรางจม — สูงกว่าเส้นเดิม (4px) เล็กน้อยตามที่ตกลงกัน
  static const _grooveHeight = 8.0;
  static const _thumbWidth = 32.0;
  static const _thumbHeight = 12.0;
  static const _tickSize = 3.0;

  /// อนิเมชัน "เขย่าปุ่ม" (เอียงซ้าย-ขวา) หลังเปลี่ยนหน้าแล้วเข้าที่
  static const _shakeDuration = Duration(milliseconds: 420);
  static const _shakeMaxAngle = 0.08; // เรเดียน (~4.6°)
  static const _shakeOscillations = 3;

  /// หน้าที่ snap อยู่ระหว่างลาก ruler (null = ไม่ได้ลาก → ใช้ [page] แทน)
  int? _dragPage;

  /// หน้าล่าสุดที่ "เข้าที่" แล้ว — ยิงเขย่าหนึ่งครั้งต่อการเปลี่ยนหน้า
  late int _settledPage;

  /// ปุ่มที่กำลังเขย่าอยู่ + ตัวนับไว้รีสตาร์ทอนิเมชันเมื่อเขย่าซ้ำปุ่มเดิม
  int? _shakePage;
  int _shakeTick = 0;

  @override
  void initState() {
    super.initState();
    _settledPage = widget.page.round();
  }

  @override
  void didUpdateWidget(SportsHubPageIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.page == oldWidget.page) return;
    // ระหว่างลาก ruler ยังไม่เขย่า — ค่อยเขย่าตอนปล่อยนิ้ว (ดู _handleDragEnd)
    if (_dragPage != null) return;
    final rounded = widget.page.round();
    // เขย่าเฉพาะตอน PageView เข้าที่บนหน้าจริง ๆ ไม่ใช่ค้างอยู่ระหว่างทาง
    if ((widget.page - rounded).abs() > 0.01) return;
    // เรียกตรงนี้ได้เลยเพราะ element นี้กำลังจะ rebuild อยู่แล้ว
    _registerShake(rounded);
  }

  /// เริ่มอนิเมชันเขย่าปุ่มถ้าเป็นการเปลี่ยนไปหน้าใหม่จริง (คืนว่าเริ่มไหม)
  bool _registerShake(int page) {
    if (page == _settledPage) return false;
    _settledPage = page;
    _shakePage = page;
    _shakeTick++;
    return true;
  }

  /// มุมเอียงของการเขย่า — ไซน์ [_shakeOscillations] ลูกพร้อมแดมป์ ให้กลับมา
  /// นิ่งพอดีที่ t = 1
  double _shakeAngleAt(double t) =>
      math.sin(t * math.pi * _shakeOscillations) * (1 - t) * _shakeMaxAngle;

  int get _lastIndex => _destinations.length - 1;

  /// ตำแหน่งหน้าที่ใช้ขับหัวหมุด/ปุ่มที่เลือก — ระหว่างลากใช้ค่าที่ snap แล้ว
  double get _effectivePage {
    final page = _dragPage?.toDouble() ?? widget.page;
    return page.clamp(0, _lastIndex).toDouble();
  }

  int get _activePage =>
      _effectivePage.round().clamp(0, _lastIndex).toInt();

  /// ระยะจากขอบรางถึงจุดที่หัวหมุดเดินได้ — เท่ารัศมีหัวหมุด (concentric กับ
  /// ปลายรางมน) เหมือน `_NeumorphicSliderTrackShape._edgeInset`
  double get _thumbInset => _thumbWidth / 2;

  double _thumbCenterForPage(double page, double width) {
    final first = _thumbInset;
    final last = math.max(first, width - _thumbInset).toDouble();
    if (_lastIndex <= 0) return first;
    return first + (last - first) * page / _lastIndex;
  }

  int _pageForPosition(double position, double width) {
    final first = _thumbInset;
    final last = math.max(first, width - _thumbInset).toDouble();
    final range = last - first;
    if (range <= 0) return _activePage;
    final progress = ((position - first) / range).clamp(0.0, 1.0).toDouble();
    return (progress * _lastIndex).round();
  }

  void _handleDragUpdate(double dx, double width) {
    final page = _pageForPosition(dx, width);
    if (page == _dragPage) return;
    setState(() => _dragPage = page);
    widget.onPageScrubbed?.call(page);
  }

  void _handleDragEnd() {
    final page = _dragPage;
    setState(() {
      _dragPage = null;
      // ปล่อยนิ้วแล้วเข้าที่ — เขย่าปุ่มที่เพิ่งถูกเลือกถ้ามีการเปลี่ยนหน้า
      if (page != null) _registerShake(page);
    });
    // ถ้า parent ไม่ได้ scrub สด ๆ ก็ commit ตอนปล่อยนิ้วแทน
    if (page != null && widget.onPageScrubbed == null) {
      widget.onPageSelected(page);
    }
  }

  void _cancelDrag() {
    if (mounted) setState(() => _dragPage = null);
  }

  @override
  Widget build(BuildContext context) {
    final activePage = _activePage;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBar(activePage),
        // เว้นระยะเหนือข้อความชื่อหน้าให้หายใจขึ้น
        const SizedBox(height: 8),
        _buildCaption(activePage),
      ],
    );
  }

  Widget _buildBar(int activePage) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.24),
                  Colors.white.withValues(alpha: 0.10),
                  Colors.white.withValues(alpha: 0.18),
                ],
                stops: const [0, 0.5, 1],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.56),
                width: 0.9,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 14,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.42),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: _buttonRowHeight,
                      child: Row(
                        children: [
                          for (
                            var index = 0;
                            index < _destinations.length;
                            index++
                          )
                            _buildPageButton(index, activePage),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: _buttonRowHeight,
                      child: Row(
                        children: [
                          _buildArrow(
                            visible: activePage > 0,
                            previous: true,
                            currentPage: activePage,
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) =>
                                  _buildRuler(constraints.maxWidth),
                            ),
                          ),
                          _buildArrow(
                            visible: activePage < _lastIndex,
                            previous: false,
                            currentPage: activePage,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ruler — รางจม + จุดบอกตำแหน่งหน้า + หัวหมุดแก้วขาว
  Widget _buildRuler(double width) {
    final center = _thumbCenterForPage(_effectivePage, width);

    return Semantics(
      container: true,
      slider: true,
      label: 'แถบเลื่อนเปลี่ยนหน้า',
      value: _destinations[_activePage].title,
      increasedValue:
          _destinations[(_activePage + 1).clamp(0, _lastIndex).toInt()].title,
      decreasedValue:
          _destinations[(_activePage - 1).clamp(0, _lastIndex).toInt()].title,
      onIncrease: _activePage < _lastIndex
          ? () => widget.onPageSelected(_activePage + 1)
          : null,
      onDecrease: _activePage > 0
          ? () => widget.onPageSelected(_activePage - 1)
          : null,
      child: Tooltip(
        message: 'ลากเพื่อเปลี่ยนหน้า',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) =>
              _handleDragUpdate(details.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _handleDragEnd(),
          onHorizontalDragCancel: _cancelDrag,
          onTapUp: (details) => widget.onPageSelected(
            _pageForPosition(details.localPosition.dx, width),
          ),
          child: SizedBox(
            height: _buttonRowHeight,
            child: Center(
              child: SizedBox(
                width: double.infinity,
                height: _grooveHeight,
                child: Stack(
                  // ปล่อยให้หัวหมุดที่สูงกว่าร่องล้นออกได้ (ไม่โดนตัดเหมือนเดิม)
                  clipBehavior: Clip.none,
                  children: [
                    // รางจม — painter ตัวเดียวกับ NeumorphicInsetBox/slider
                    Positioned.fill(
                      child: CustomPaint(
                        painter: NeumorphicInsetPainter(
                          borderRadius: _grooveHeight / 2,
                          distance: 1.6,
                          blur: 3,
                        ),
                      ),
                    ),
                    // จุดบอกตำแหน่งหน้า
                    for (
                      var index = 0;
                      index < _destinations.length;
                      index++
                    )
                      Positioned(
                        left:
                            _thumbCenterForPage(index.toDouble(), width) -
                            _tickSize / 2,
                        top: (_grooveHeight - _tickSize) / 2,
                        child: Container(
                          width: _tickSize,
                          height: _tickSize,
                          decoration: BoxDecoration(
                            color: AppColors.textPrimary.withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    // หัวหมุดแก้วขาว (สูตรเดิม) — สูงกว่าร่องเล็กน้อยให้ดูนูน
                    Positioned(
                      left: center - _thumbWidth / 2,
                      top: (_grooveHeight - _thumbHeight) / 2,
                      child: Container(
                        width: _thumbWidth,
                        height: _thumbHeight,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(_thumbHeight / 2),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.95),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.14),
                              blurRadius: 5,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCaption(int activePage) {
    final destination = _destinations[activePage];
    return Semantics(
      liveRegion: true,
      label: 'หน้าปัจจุบัน: ${destination.title}',
      child: ExcludeSemantics(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Padding(
            key: ValueKey<int>(activePage),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              destination.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                // เผื่อช่องว่างบรรทัดเล็กน้อยให้ข้อความยาวที่ตกบรรทัดที่สอง
                height: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArrow({
    required bool visible,
    required bool previous,
    required int currentPage,
  }) {
    if (!visible) return const SizedBox(width: _arrowWidth, height: 44);
    final destination = _destinations[currentPage + (previous ? -1 : 1)];
    return SizedBox(
      width: _arrowWidth,
      height: 44,
      child: IconButton(
        tooltip: 'ไปหน้า${destination.shortTitle}: ${destination.title}',
        onPressed: () =>
            widget.onPageSelected(currentPage + (previous ? -1 : 1)),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(
          previous ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
          color: AppColors.textSecondary.withValues(alpha: 0.82),
          size: 22,
        ),
      ),
    );
  }

  Widget _buildPageButton(int index, int currentPage) {
    final destination = _destinations[index];
    final isActive = index == currentPage;

    Widget slot = SizedBox(
      width: double.infinity,
      height: _buttonRowHeight,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: isActive ? 1 : 0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Stack(
            fit: StackFit.expand,
            // ปล่อยให้ rim glow/เงาของผิวปุ่มล้นออกจากช่องปุ่มได้
            // (แถบด้านนอกมี ClipRRect ของตัวเองอยู่แล้ว)
            clipBehavior: Clip.none,
            children: [
              if (t > 0.001)
                Opacity(opacity: t, child: _buildActiveSurface()),
              Center(child: _buildButtonContent(destination, t)),
            ],
          ),
        ),
      ),
    );

    // เขย่าปุ่ม (เอียงซ้าย-ขวา) หลังเปลี่ยนหน้าแล้วเข้าที่ — key ผูกกับ
    // _shakeTick เพื่อให้เขย่าซ้ำปุ่มเดิมได้
    if (index == _shakePage) {
      slot = TweenAnimationBuilder<double>(
        key: ValueKey<int>(_shakeTick),
        tween: Tween<double>(begin: 0, end: 1),
        duration: _shakeDuration,
        curve: Curves.linear,
        builder: (context, t, child) => Transform.rotate(
          key: SportsHubPageIndicator.shakeKey,
          angle: _shakeAngleAt(t),
          child: child,
        ),
        child: slot,
      );
    }

    return Expanded(
      child: Tooltip(
        message: destination.title,
        child: Semantics(
          button: true,
          selected: isActive,
          label: isActive
              ? '${destination.title}, หน้าปัจจุบัน'
              : destination.title,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => widget.onPageSelected(index),
              borderRadius: BorderRadius.circular(15),
              child: slot,
            ),
          ),
        ),
      ),
    );
  }

  /// ผิวปุ่มที่ถูกเลือก — [LitGlassTile] แก้วขาวใสพร้อมแสงขาวตามขอบครบทุก
  /// ชั้น (สูตรแสงเดียวกับปุ่มเมนูหลักของ section ใน `tlz_drawer.dart` ที่จูน
  /// มาบนแถบพื้นสว่าง)
  Widget _buildActiveSurface() {
    return const LitGlassTile(
      accentColor: AppColors.primary,
      child: SizedBox.expand(),
    );
  }

  /// เนื้อปุ่ม (ไอคอน + ชื่อย่อ) — สีและน้ำหนักตัวอักษรไล่ตาม [t] ของอนิเมชัน
  /// เพื่อให้ปุ่มที่ถูกเลือกเป็นตัวอักษรเข้มบนแก้วขาวใสโดยไม่กระตุก
  Widget _buildButtonContent(_SportsHubDestination destination, double t) {
    final color = Color.lerp(AppColors.textSecondary, AppColors.textPrimary, t)!;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(destination.icon, size: 18, color: color),
          const SizedBox(width: 2),
          Text(
            destination.shortTitle,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.lerp(FontWeight.w600, FontWeight.w700, t),
            ),
          ),
        ],
      ),
    );
  }
}

class _SportsHubDestination {
  final String shortTitle;
  final String title;
  final IconData icon;

  const _SportsHubDestination({
    required this.shortTitle,
    required this.title,
    required this.icon,
  });
}
