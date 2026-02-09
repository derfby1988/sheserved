import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RulerPicker extends StatefulWidget {
  final String label;
  final String unit;
  final double minValue;
  final double maxValue;
  final double initialValue;
  final double step;
  final ValueChanged<double> onChanged;

  const RulerPicker({
    Key? key,
    required this.label,
    required this.unit,
    this.minValue = 0,
    this.maxValue = 250,
    this.initialValue = 160,
    this.step = 1,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<RulerPicker> createState() => _RulerPickerState();
}

class _RulerPickerState extends State<RulerPicker> with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _glowController;
  final double _itemWidth = 12.0;
  double _currentValue = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue;
    final initialOffset = (widget.initialValue - widget.minValue) * _itemWidth;
    _scrollController = ScrollController(initialScrollOffset: initialOffset);
    _scrollController.addListener(_onScroll);
    
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final value = widget.minValue + (offset / _itemWidth);
    final clampedValue = value.clamp(widget.minValue, widget.maxValue);
    
    if ((clampedValue - _currentValue).abs() >= widget.step) {
      HapticFeedback.selectionClick();
    }
    
    setState(() {
      _currentValue = clampedValue;
    });
    widget.onChanged(double.parse(clampedValue.toStringAsFixed(1)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Title & Value Display
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        
        // Value with Animation
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 100),
          tween: Tween(begin: _currentValue, end: _currentValue),
          builder: (context, value, child) {
            return RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '${value.round()} ',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: _isDragging 
                          ? const Color(0xFF679E83)
                          : const Color(0xFF679E83),
                    ),
                  ),
                  TextSpan(
                    text: widget.unit,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),

        // Ruler Container
        Container(
          height: 110,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF679E83).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Background Gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF679E83),
                        const Color(0xFF558B72),
                      ],
                    ),
                  ),
                ),
                
                // Ruler ScrollView
                GestureDetector(
                  onPanStart: (_) => setState(() => _isDragging = true),
                  onPanEnd: (_) => setState(() => _isDragging = false),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollEndNotification) {
                        _snapToNearestValue();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                        horizontal: MediaQuery.of(context).size.width / 2,
                      ),
                      itemCount: (widget.maxValue - widget.minValue).toInt() + 1,
                      itemBuilder: (context, index) {
                        final value = widget.minValue + index;
                        final isMajor = value % 5 == 0;
                        final isSuperMajor = value % 10 == 0;
                        final isCurrentValue = (value - _currentValue).abs() < 0.5;

                        return SizedBox(
                          width: _itemWidth,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Tick Mark
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: isCurrentValue ? 3 : (isMajor ? 2 : 1),
                                height: isCurrentValue 
                                    ? 45 
                                    : (isSuperMajor ? 35 : (isMajor ? 22 : 14)),
                                decoration: BoxDecoration(
                                  color: isCurrentValue
                                      ? Colors.white
                                      : Colors.white.withOpacity(isMajor ? 0.8 : 0.5),
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: isCurrentValue
                                      ? [
                                          BoxShadow(
                                            color: Colors.white.withOpacity(0.5),
                                            blurRadius: 4,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Number Labels
                              if (isSuperMajor)
                                Text(
                                  '${value.toInt()}',
                                  style: TextStyle(
                                    color: isCurrentValue
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.8),
                                    fontSize: isCurrentValue ? 14 : 12,
                                    fontWeight: isCurrentValue 
                                        ? FontWeight.bold 
                                        : FontWeight.w500,
                                  ),
                                )
                              else
                                const SizedBox(height: 17),
                              const SizedBox(height: 8),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Center Indicator (Animated Triangle)
                Align(
                  alignment: Alignment.topCenter,
                  child: AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, child) {
                      return Container(
                        width: 24,
                        height: 14,
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(
                                0.3 + (_glowController.value * 0.3),
                              ),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: CustomPaint(
                          painter: TrianglePainter(
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                
                // Side Gradient Overlays
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          const Color(0xFF679E83),
                          const Color(0xFF679E83).withOpacity(0),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          const Color(0xFF558B72),
                          const Color(0xFF558B72).withOpacity(0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _snapToNearestValue() {
    final targetValue = _currentValue.round().toDouble();
    final targetOffset = (targetValue - widget.minValue) * _itemWidth;
    
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }
  
  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _glowController.dispose();
    super.dispose();
  }
}

class TrianglePainter extends CustomPainter {
  final Color color;
  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();

    // Draw shadow
    canvas.drawPath(path.shift(const Offset(0, 2)), shadowPaint);
    // Draw triangle
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
