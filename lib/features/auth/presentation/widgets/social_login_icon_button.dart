import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/social_login_button.dart';

/// Social Login Icon Button Widget
/// แสดงปุ่ม Social Login แบบ icon-only สำหรับแสดงในแถวเดียวกัน
class SocialLoginIconButton extends StatelessWidget {
  final SocialProvider provider;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double size;

  const SocialLoginIconButton({
    super.key,
    required this.provider,
    this.onPressed,
    this.isLoading = false,
    this.size = 56.0, // ขนาด default
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _getBackgroundColor().withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(size / 2),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: size * 0.4,
                    height: size * 0.4,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getIconColor(),
                      ),
                    ),
                  )
                : _buildIcon(),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    final iconSize = size * 0.5; // Icon size = 50% of button size
    
    switch (provider) {
      case SocialProvider.google:
        return Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              'G',
              style: TextStyle(
                color: _getBackgroundColor(),
                fontSize: iconSize * 0.6,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      case SocialProvider.facebook:
        return Icon(
          Icons.facebook,
          color: _getIconColor(),
          size: iconSize,
        );
      case SocialProvider.apple:
        return Icon(
          Icons.apple,
          color: _getIconColor(),
          size: iconSize,
        );
      case SocialProvider.line:
        return Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              'L',
              style: TextStyle(
                color: _getBackgroundColor(),
                fontSize: iconSize * 0.6,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      case SocialProvider.tiktok:
        return CustomPaint(
          size: Size(iconSize, iconSize),
          painter: _TikTokIconPainter(),
        );
    }
  }

  Color _getBackgroundColor() {
    switch (provider) {
      case SocialProvider.google:
        return Colors.white;
      case SocialProvider.facebook:
        return const Color(0xFF1877F2);
      case SocialProvider.apple:
        return const Color(0xFF000000);
      case SocialProvider.line:
        return const Color(0xFF00C300);
      case SocialProvider.tiktok:
        return const Color(0xFF000000);
    }
  }

  Color _getIconColor() {
    switch (provider) {
      case SocialProvider.google:
        return const Color(0xFF757575);
      case SocialProvider.facebook:
      case SocialProvider.apple:
      case SocialProvider.line:
      case SocialProvider.tiktok:
        return Colors.white;
    }
  }
}

/// Custom Painter for TikTok Logo (Icon version)
class _TikTokIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..strokeWidth = 2.0;

    // TikTok Logo - สร้างเป็นรูปตัว "T" สองตัวที่เชื่อมกัน
    final leftTPath = Path()
      ..moveTo(size.width * 0.2, size.height * 0.15)
      ..lineTo(size.width * 0.2, size.height * 0.85)
      ..lineTo(size.width * 0.35, size.height * 0.85)
      ..lineTo(size.width * 0.35, size.height * 0.15)
      ..lineTo(size.width * 0.275, size.height * 0.15)
      ..lineTo(size.width * 0.275, size.height * 0.75)
      ..lineTo(size.width * 0.2, size.height * 0.75)
      ..close();

    final rightTPath = Path()
      ..moveTo(size.width * 0.65, size.height * 0.15)
      ..lineTo(size.width * 0.8, size.height * 0.15)
      ..lineTo(size.width * 0.8, size.height * 0.25)
      ..lineTo(size.width * 0.725, size.height * 0.25)
      ..lineTo(size.width * 0.725, size.height * 0.85)
      ..lineTo(size.width * 0.65, size.height * 0.85)
      ..close();

    final curvePath = Path()
      ..moveTo(size.width * 0.35, size.height * 0.5)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.3,
        size.width * 0.65,
        size.height * 0.5,
      );

    canvas.drawPath(leftTPath, paint);
    canvas.drawPath(rightTPath, paint);
    
    final curvePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = 2.5;
    canvas.drawPath(curvePath, curvePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
