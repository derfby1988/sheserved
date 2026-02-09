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

class _GenderSwitchState extends State<GenderSwitch> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onTap(String gender) {
    HapticFeedback.lightImpact();
    _animationController.forward().then((_) {
      _animationController.reverse();
    });
    widget.onChanged(gender);
  }

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
        
        // Gender Options Row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Female Option
            _buildGenderOption(
              gender: 'female',
              icon: Icons.female,
              label: 'หญิง',
              gradientColors: [
                const Color(0xFFF8A8D0),
                const Color(0xFFE88BC4),
              ],
            ),
            
            const SizedBox(width: 24),
            
            // Male Option
            _buildGenderOption(
              gender: 'male',
              icon: Icons.male,
              label: 'ชาย',
              gradientColors: [
                const Color(0xFF8EC5FC),
                const Color(0xFF6BA8E5),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGenderOption({
    required String gender,
    required IconData icon,
    required String label,
    required List<Color> gradientColors,
  }) {
    final isSelected = widget.selectedGender == gender;
    
    return GestureDetector(
      onTap: () => _onTap(gender),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          final scale = isSelected ? _scaleAnimation.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              width: isSelected ? 80 : 70,
              height: isSelected ? 80 : 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isSelected
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradientColors,
                      )
                    : null,
                color: isSelected ? null : Colors.grey[100],
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: gradientColors[0].withOpacity(0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Center(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: isSelected ? 36 : 30,
                    color: isSelected ? Colors.white : Colors.grey[400],
                  ),
                  child: Icon(
                    icon,
                    size: isSelected ? 36 : 30,
                    color: isSelected ? Colors.white : Colors.grey[400],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? const Color(0xFF679E83) : Colors.grey[400],
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
