import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AgePicker extends StatefulWidget {
  final int initialAge;
  final int minAge;
  final int maxAge;
  final ValueChanged<int> onChanged;
  final double height;

  const AgePicker({
    Key? key,
    this.initialAge = 25,
    this.minAge = 1,
    this.maxAge = 120,
    required this.onChanged,
    this.height = 180,
  }) : super(key: key);

  @override
  State<AgePicker> createState() => _AgePickerState();
}

class _AgePickerState extends State<AgePicker> {
  late FixedExtentScrollController _controller;
  late int _currentAge;

  @override
  void initState() {
    super.initState();
    _currentAge = widget.initialAge;
    _controller = FixedExtentScrollController(
      initialItem: widget.initialAge - widget.minAge,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'อายุ',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(width: 16),
        
        // Wheel Picker Container
        SizedBox(
          width: 100, // Fixed width for the picker
          height: widget.height,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF679E83).withOpacity(0.8),
                  const Color(0xFF558B72),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF679E83).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Selection Indicator
                Center(
                  child: Container(
                    height: 50,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                
                // Wheel Picker
                ListWheelScrollView.useDelegate(
                  controller: _controller,
                  itemExtent: 50,
                  perspective: 0.003,
                  diameterRatio: 1.5,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (index) {
                    HapticFeedback.selectionClick();
                    final newAge = widget.minAge + index;
                    setState(() {
                      _currentAge = newAge;
                    });
                    widget.onChanged(newAge);
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: widget.maxAge - widget.minAge + 1,
                    builder: (context, index) {
                      final age = widget.minAge + index;
                      final isSelected = age == _currentAge;
                      
                      return Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: isSelected ? 28 : 18,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                            color: isSelected 
                                ? Colors.white 
                                : Colors.white.withOpacity(0.5),
                          ),
                          child: Text('$age'),
                        ),
                      );
                    },
                  ),
                ),
                
                // Top Gradient Fade
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 30,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF679E83),
                          const Color(0xFF679E83).withOpacity(0),
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                  ),
                ),
                
                // Bottom Gradient Fade
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 30,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          const Color(0xFF558B72),
                          const Color(0xFF558B72).withOpacity(0),
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 16),
        const Text(
          'ปี',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ],
    );
  }
}
