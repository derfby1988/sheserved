import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GenderSwitch extends StatefulWidget {
  final String selectedGender;
  final ValueChanged<String> onChanged;

  const GenderSwitch({
    Key? key,
    required this.selectedGender,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<GenderSwitch> createState() => _GenderSwitchState();
}

class _GenderSwitchState extends State<GenderSwitch> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'เพศ',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 16),
        
        // Capsule Toggle
        Container(
          width: 200,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
                // inset: true, // Inner shadow simulation (not supported natively, using outer for now)
              ),
            ],
          ),
          child: Stack(
            children: [
              // Animated Thumb (Background of selected item)
              AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: widget.selectedGender == 'female' 
                    ? Alignment.centerLeft 
                    : Alignment.centerRight,
                child: Container(
                  width: 100, // Half of parent width
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF87B17F), Color(0xFF007FAD)],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Icons Row (Foreground)
              Row(
                children: [
                  // Female Option
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onChanged('female');
                      },
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: widget.selectedGender == 'female' 
                                ? Colors.black 
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          child: Icon(
                            Icons.female,
                            size: 32,
                            color: widget.selectedGender == 'female' 
                                ? Colors.black 
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // Male Option
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onChanged('male');
                      },
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: widget.selectedGender == 'male' 
                                ? Colors.black 
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          child: Icon(
                            Icons.male,
                            size: 32,
                            color: widget.selectedGender == 'male' 
                                ? Colors.black 
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
