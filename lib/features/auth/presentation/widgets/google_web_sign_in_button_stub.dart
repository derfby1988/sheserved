import 'package:flutter/widgets.dart';

/// Fallback สำหรับ platform ที่ไม่ใช่ web — ปุ่มทางการมีเฉพาะใน impl web
/// (caller gate ด้วย kIsWeb อยู่แล้ว จึงไม่ควรถูก render จริง)
class GoogleWebSignInButton extends StatelessWidget {
  const GoogleWebSignInButton({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
