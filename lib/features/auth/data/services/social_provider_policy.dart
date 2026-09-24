import 'package:flutter/foundation.dart';

import '../../presentation/widgets/social_login_button.dart' show SocialProvider;

/// W3.3 — Social provider availability policy (ตัดสินใจแล้ว 2026-09-24).
///
/// บน web **เฉพาะ Google** ที่เปิดใช้ — provider อื่นยังคง render ในตำแหน่ง
/// เดิมแต่ disabled ตาม UI invariant §4.1 (ห้ามถอด child ออกจาก Row)
///
/// เหตุผล + ค่าใช้จ่ายต่อ provider (ดูเพิ่มใน flutter_web_enablement_plan W3):
/// - **Google**: backend verify ผ่าน server-side JWKS แล้ว (13.2); Web OAuth
///   client ID ใช้ตัวเดียวกับ `GOOGLE_CLIENT_ID` — ฟรี
/// - **Facebook / LINE / TikTok**: backend `social/:provider` = 501
///   fail-closed (deferred ใน 13.2 — ยังไม่มี credentials ที่อนุมัติ)
///   developer account ของทั้งสามฟรี แต่ต้องสร้าง app + config ก่อนเปิด flag
/// - **Apple**: ต้อง paid Apple Developer ($99/ปี) สำหรับ entitlement +
///   Services ID — blocked จนกว่าจะมี paid account (blocker เดิมจาก 13.2)
/// - **Passkeys (Corbado)**: ไม่ใช่ SocialProvider — bundle ใน index.html เป็น
///   capability เท่านั้น; Corbado คิดตาม MAU เมื่อเปิดใช้จริง → ต้องมี
///   decision + budget approval ก่อน (ดู comment ใน web/index.html)
///
/// วิธีเปิด provider เพิ่มในอนาคต: backend รองรับ `social/:provider` →
/// flip flag ใน [webEnabled] → verify ด้วย Gate W3 ใน §4.4
class SocialProviderPolicy {
  SocialProviderPolicy._();

  /// Provider ที่เปิดใช้บน web — เพิ่ม provider ตรงนี้เมื่อ backend support
  /// และ cost/credential decision ถูกอนุมัติแล้วเท่านั้น
  static const Set<SocialProvider> webEnabled = {SocialProvider.google};

  /// Provider ที่เปิดใช้บน mobile (iOS/Android) — คง behavior เดิมทั้งหมด
  static const Set<SocialProvider> mobileEnabled = {
    SocialProvider.google,
    SocialProvider.facebook,
    SocialProvider.apple,
    SocialProvider.line,
    SocialProvider.tiktok,
  };

  /// ปุ่มควรกดได้หรือไม่บน platform ปัจจุบัน — web กรองด้วย [webEnabled]
  static bool isEnabled(SocialProvider provider) =>
      kIsWeb ? webEnabled.contains(provider) : mobileEnabled.contains(provider);

  /// Tooltip/ข้อความเมื่อปุ่มถูก disable บน web
  static String disabledReason(SocialProvider provider) =>
      'ยังไม่รองรับการลงชื่อเข้าใช้ด้วย ${_label(provider)} บนเว็บ';

  static String _label(SocialProvider provider) => switch (provider) {
    SocialProvider.google => 'Google',
    SocialProvider.facebook => 'Facebook',
    SocialProvider.apple => 'Apple',
    SocialProvider.line => 'Line',
    SocialProvider.tiktok => 'TikTok',
  };
}
