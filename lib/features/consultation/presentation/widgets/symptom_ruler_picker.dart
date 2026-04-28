import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';

/// A custom picker that scrolls through a list of text symptoms/sensation strings.
/// Inspired by the numeric RulerPicker but adapted for qualitative medical terms.
class SymptomRulerPicker extends StatefulWidget {
  final List<String> symptoms;
  final String initialSymptom;
  final ValueChanged<String> onChanged;
  final double itemWidth;

  const SymptomRulerPicker({
    Key? key,
    required this.symptoms,
    required this.initialSymptom,
    required this.onChanged,
    this.itemWidth = 45.0,
  }) : super(key: key);

  @override
  State<SymptomRulerPicker> createState() => _SymptomRulerPickerState();
}

class _SymptomRulerPickerState extends State<SymptomRulerPicker> {
  static const int _virtualItemCount = 1000;
  late ScrollController _scrollController;
  int _virtualIndex = 0;
  bool _isDragging = false;

  int get _actualIndex => _virtualIndex % widget.symptoms.length;

  @override
  void initState() {
    super.initState();
    // 1. Find initial symptom index
    int initialActual = widget.symptoms.indexOf(widget.initialSymptom);
    if (initialActual == -1) initialActual = 0;

    // 2. Calculate a starting virtual index near the middle of the large list
    // to allow scrolling both ways indefinitely.
    final int mid = _virtualItemCount ~/ 2;
    // Align to the specific symptom
    _virtualIndex = mid - (mid % widget.symptoms.length) + initialActual;

    final initialOffset = _virtualIndex * widget.itemWidth;
    _scrollController = ScrollController(initialScrollOffset: initialOffset);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final offset = _scrollController.offset;
    final index = (offset / widget.itemWidth).round().clamp(0, _virtualItemCount - 1);

    if (index != _virtualIndex) {
      setState(() {
        _virtualIndex = index;
      });
      widget.onChanged(widget.symptoms[_actualIndex]);
      
      // ── Play Sound & Haptic ────────────────────────
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.selectionClick();
    }
  }

  void _snapToNearest() {
    if (!_scrollController.hasClients) return;
    final targetOffset = _virtualIndex * widget.itemWidth;
    
    // Only animate if there's a significant difference to avoid infinite loops
    if ((_scrollController.offset - targetOffset).abs() > 0.1) {
      Future.microtask(() {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const double containerWidth = 120.0;
    final double sidePadding = (containerWidth - widget.itemWidth) / 2;

    return SizedBox(
      height: 40,
      width: containerWidth,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The scrolling list
          GestureDetector(
            onPanStart: (_) => setState(() => _isDragging = true),
            onPanEnd: (_) => setState(() => _isDragging = false),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollEndNotification) {
                  _snapToNearest();
                }
                return false;
              },
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: sidePadding),
                itemCount: _virtualItemCount,
                itemBuilder: (context, index) {
                  final actualIdx = index % widget.symptoms.length;
                  final isCurrent = index == _virtualIndex;
                  return Container(
                    width: widget.itemWidth,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 150),
                      style: TextStyle(
                        fontFamily: 'SukhumvitSet',
                        fontSize: isCurrent ? 12 : 10,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: isCurrent 
                          ? AppColors.primary 
                          : Colors.grey.withOpacity(0.5),
                        letterSpacing: 0,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(widget.symptoms[actualIdx]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          
          // Selection Indicator Overlay (Subtle line or bracket)
          IgnorePointer(
            child: Container(
              width: widget.itemWidth + 2,
              height: 24,
              decoration: BoxDecoration(
                border: Border.symmetric(
                  vertical: BorderSide(
                    color: AppColors.primary.withOpacity(0.15),
                    width: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
