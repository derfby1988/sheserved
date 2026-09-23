import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

class SportsHubPageIndicator extends StatefulWidget {
  final int currentPage;
  final ValueChanged<int> onPageSelected;

  const SportsHubPageIndicator({
    super.key,
    required this.currentPage,
    required this.onPageSelected,
  });

  @override
  State<SportsHubPageIndicator> createState() => _SportsHubPageIndicatorState();
}

class _SportsHubPageIndicatorState extends State<SportsHubPageIndicator> {
  static const _destinations = [
    _SportsHubDestination(
      shortTitle: 'สนาม',
      title: 'จองสนามกีฬา',
      icon: Icons.sports_tennis_rounded,
    ),
    _SportsHubDestination(
      shortTitle: 'เพื่อน',
      title: 'หาเพื่อนออกกำลังกาย',
      icon: Icons.groups_rounded,
    ),
    _SportsHubDestination(
      shortTitle: 'โค้ช',
      title: 'หาโค้ช/เทรนเนอร์',
      icon: Icons.school_rounded,
    ),
  ];

  static const _controlHeight = 58.0;
  static const _rulerInset = 20.0;
  static const _thumbWidth = 14.0;

  double? _dragPosition;

  int get _currentPage => widget.currentPage.clamp(0, _destinations.length - 1);

  int _pageForPosition(double position, double width) {
    final firstCenter = _rulerInset + _thumbWidth / 2;
    final lastCenter = width - _rulerInset - _thumbWidth / 2;
    final range = lastCenter - firstCenter;
    if (range <= 0) return _currentPage;
    final progress = ((position - firstCenter) / range)
        .clamp(0.0, 1.0)
        .toDouble();
    return (progress * (_destinations.length - 1)).round();
  }

  double _thumbLeftForPage(int page, double width) {
    final firstLeft = _rulerInset;
    final lastLeft = math
        .max(firstLeft, width - _rulerInset - _thumbWidth)
        .toDouble();
    return firstLeft +
        (lastLeft - firstLeft) * page / (_destinations.length - 1);
  }

  void _finishDrag(double width) {
    final position = _dragPosition;
    setState(() => _dragPosition = null);
    if (position != null) {
      widget.onPageSelected(_pageForPosition(position, width));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPage = _currentPage;
    final currentDestination = _destinations[currentPage];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final thumbLeft = _dragPosition == null
            ? _thumbLeftForPage(currentPage, width)
            : (_dragPosition! - _thumbWidth / 2)
                  .clamp(
                    _rulerInset,
                    math.max(_rulerInset, width - _rulerInset - _thumbWidth),
                  )
                  .toDouble();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              container: true,
              explicitChildNodes: true,
              slider: true,
              label: 'แถบเลื่อนเปลี่ยนหน้า',
              value: currentDestination.title,
              increasedValue:
                  _destinations[(currentPage + 1)
                          .clamp(0, _destinations.length - 1)
                          .toInt()]
                      .title,
              decreasedValue:
                  _destinations[(currentPage - 1)
                          .clamp(0, _destinations.length - 1)
                          .toInt()]
                      .title,
              onIncrease: currentPage < _destinations.length - 1
                  ? () => widget.onPageSelected(currentPage + 1)
                  : null,
              onDecrease: currentPage > 0
                  ? () => widget.onPageSelected(currentPage - 1)
                  : null,
              child: Tooltip(
                message: 'ลากเพื่อเปลี่ยนหน้า',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    setState(() => _dragPosition = details.localPosition.dx);
                  },
                  onHorizontalDragEnd: (_) => _finishDrag(width),
                  onHorizontalDragCancel: () {
                    if (mounted) setState(() => _dragPosition = null);
                  },
                  onTapUp: (details) {
                    if (details.localPosition.dy >= 45) {
                      widget.onPageSelected(
                        _pageForPosition(details.localPosition.dx, width),
                      );
                    }
                  },
                  child: Container(
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
                          child: SizedBox(
                            width: double.infinity,
                            height: _controlHeight,
                            child: Stack(
                              fit: StackFit.expand,
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
                                            Colors.white.withValues(
                                              alpha: 0.42,
                                            ),
                                            Colors.white.withValues(alpha: 0),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  left: 1,
                                  right: 1,
                                  child: SizedBox(
                                    height: 44,
                                    child: Row(
                                      children: [
                                        _buildArrow(
                                          visible: currentPage > 0,
                                          previous: true,
                                          currentPage: currentPage,
                                        ),
                                        for (
                                          var index = 0;
                                          index < _destinations.length;
                                          index++
                                        )
                                          _buildPageButton(index, currentPage),
                                        _buildArrow(
                                          visible:
                                              currentPage <
                                              _destinations.length - 1,
                                          previous: false,
                                          currentPage: currentPage,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: _rulerInset,
                                  right: _rulerInset,
                                  bottom: 5,
                                  child: IgnorePointer(
                                    child: SizedBox(
                                      height: 4,
                                      child: Stack(
                                        alignment: Alignment.centerLeft,
                                        children: [
                                          Positioned.fill(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: AppColors.textPrimary
                                                    .withValues(alpha: 0.10),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                            ),
                                          ),
                                          for (
                                            var index = 0;
                                            index < _destinations.length;
                                            index++
                                          )
                                            Positioned(
                                              left:
                                                  _thumbLeftForPage(
                                                    index,
                                                    width,
                                                  ) -
                                                  _rulerInset +
                                                  _thumbWidth / 2 -
                                                  2,
                                              top: 0,
                                              child: Container(
                                                width: 4,
                                                height: 4,
                                                decoration: BoxDecoration(
                                                  color: AppColors.textPrimary
                                                      .withValues(alpha: 0.24),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ),
                                          AnimatedPositioned(
                                            duration: _dragPosition == null
                                                ? const Duration(
                                                    milliseconds: 160,
                                                  )
                                                : Duration.zero,
                                            curve: Curves.easeOutCubic,
                                            left: thumbLeft - _rulerInset,
                                            top: -1,
                                            child: Container(
                                              width: _thumbWidth,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.88,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.95),
                                                  width: 0.8,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.12,
                                                        ),
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
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Semantics(
              liveRegion: true,
              label: 'หน้าปัจจุบัน: ${currentDestination.title}',
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
                    key: ValueKey<int>(currentPage),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      currentDestination.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildArrow({
    required bool visible,
    required bool previous,
    required int currentPage,
  }) {
    if (!visible) return const SizedBox(width: 44, height: 44);
    final destination = _destinations[currentPage + (previous ? -1 : 1)];
    return SizedBox(
      width: 44,
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
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 1,
                    vertical: 2,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    gradient: isActive
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.38),
                              Colors.white.withValues(alpha: 0.20),
                            ],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isActive
                          ? Colors.white.withValues(alpha: 0.82)
                          : Colors.transparent,
                      width: 0.8,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : const [],
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            destination.icon,
                            size: 18,
                            color: isActive
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            destination.shortTitle,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              color: isActive
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: isActive
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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
