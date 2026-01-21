import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';

/// Social Login Provider Types
enum SocialProvider {
  google,
  facebook,
  apple,
  line,
  tiktok,
}

/// Social Login Button Widget
/// แสดงปุ่มสำหรับ Social Login แต่ละ provider พร้อมสีและ icon ที่เหมาะสม
class SocialLoginButton extends StatelessWidget {
  final SocialProvider provider;
  final VoidCallback? onPressed;
  final bool isLoading;

  const SocialLoginButton({
    super.key,
    required this.provider,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 52, // ลดความสูงจาก 56 เป็น 52 ให้ใกล้เคียง design
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _getBackgroundColor().withOpacity(0.25), // ลด opacity
            blurRadius: 6, // ลด blur
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getTextColor(),
                      ),
                    ),
                  )
                else ...[
                  _buildIcon(),
                  const SizedBox(width: 12),
                  Text(
                    _getButtonText(),
                    style: AppTextStyles.button.copyWith(
                      color: _getTextColor(),
                      fontSize: 15, // ลดขนาดตัวอักษรจาก 16 เป็น 15
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    switch (provider) {
      case SocialProvider.google:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              'G',
              style: TextStyle(
                color: _getBackgroundColor(),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      case SocialProvider.facebook:
        return const Icon(
          Icons.facebook,
          color: Colors.white,
          size: 24,
        );
      case SocialProvider.apple:
        return const Icon(
          Icons.apple,
          color: Colors.white,
          size: 24,
        );
      case SocialProvider.line:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              'L',
              style: TextStyle(
                color: _getBackgroundColor(),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      case SocialProvider.tiktok:
        return _buildTikTokIcon();
    }
  }

  Widget _buildTikTokIcon() {
    // TikTok Icon - สร้างเป็น CustomPaint แบบ TikTok logo
    return CustomPaint(
      size: const Size(24, 24),
      painter: _TikTokIconPainter(),
    );
  }

  Color _getBackgroundColor() {
    switch (provider) {
      case SocialProvider.google:
        return Colors.white; // Google white
      case SocialProvider.facebook:
        return const Color(0xFF1877F2); // Facebook blue
      case SocialProvider.apple:
        return const Color(0xFF000000); // Apple black
      case SocialProvider.line:
        return const Color(0xFF00C300); // Line green
      case SocialProvider.tiktok:
        return const Color(0xFF000000); // TikTok black
    }
  }

  Color _getTextColor() {
    switch (provider) {
      case SocialProvider.google:
        return const Color(0xFF757575); // Google gray text
      case SocialProvider.facebook:
      case SocialProvider.apple:
      case SocialProvider.line:
      case SocialProvider.tiktok:
        return Colors.white;
    }
  }

  String _getButtonText() {
    switch (provider) {
      case SocialProvider.google:
        return 'ลงชื่อเข้าใช้ด้วย Google';
      case SocialProvider.facebook:
        return 'ลงชื่อเข้าใช้ด้วย Facebook';
      case SocialProvider.apple:
        return 'ลงชื่อเข้าใช้ด้วย Apple';
      case SocialProvider.line:
        return 'ลงชื่อเข้าใช้ด้วย Line';
      case SocialProvider.tiktok:
        return 'ลงชื่อเข้าใช้ด้วย TikTok';
    }
  }
}

/// Custom Painter for TikTok Logo
/// สร้าง TikTok logo เป็นรูปตัว "T" สองตัวที่เชื่อมกัน
class _TikTokIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..strokeWidth = 2.0;

    // TikTok Logo - สร้างเป็นรูปตัว "T" สองตัวที่เชื่อมกัน
    // Left "T" (vertical)
    final leftTPath = Path()
      ..moveTo(size.width * 0.2, size.height * 0.15)
      ..lineTo(size.width * 0.2, size.height * 0.85)
      ..lineTo(size.width * 0.35, size.height * 0.85)
      ..lineTo(size.width * 0.35, size.height * 0.15)
      ..lineTo(size.width * 0.275, size.height * 0.15)
      ..lineTo(size.width * 0.275, size.height * 0.75)
      ..lineTo(size.width * 0.2, size.height * 0.75)
      ..close();

    // Right "T" (horizontal, rotated)
    final rightTPath = Path()
      ..moveTo(size.width * 0.65, size.height * 0.15)
      ..lineTo(size.width * 0.8, size.height * 0.15)
      ..lineTo(size.width * 0.8, size.height * 0.25)
      ..lineTo(size.width * 0.725, size.height * 0.25)
      ..lineTo(size.width * 0.725, size.height * 0.85)
      ..lineTo(size.width * 0.65, size.height * 0.85)
      ..close();

    // Curve connecting the two T's
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
    
    // Draw curve with stroke
    final curvePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = 2.5;
    canvas.drawPath(curvePath, curvePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
