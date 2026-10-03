import 'package:flutter/widgets.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart';

/// ปุ่ม Google Sign-In ทางการ (GIS `renderButton`) สำหรับ Flutter web
///
/// `GoogleSignIn.signIn()` ถูก deprecated บน web — popup flow คืนเฉพาะ
/// access token (idToken = null เสมอ) ทำให้ backend verify ไม่ได้
/// ปุ่มนี้ใช้ credential flow ของ GIS ที่คืน ID token (JWT) จริง ส่งเข้า
/// `GoogleSignInPlatform.userDataEvents` ให้ [SocialAuthService] นำไป verify
class GoogleWebSignInButton extends StatefulWidget {
  const GoogleWebSignInButton({super.key, this.size = 40});

  /// เส้นผ่านศูนย์กลางของปุ่ม icon (GIS icon button ~40px เมื่อ size=large)
  final double size;

  @override
  State<GoogleWebSignInButton> createState() => _GoogleWebSignInButtonState();
}

class _GoogleWebSignInButtonState extends State<GoogleWebSignInButton> {
  static Future<void>? _initFuture;

  /// init plugin หนึ่งครั้งจาก meta `google-signin-client_id` ใน index.html —
  /// `renderButton` assert ต้องมี init ก่อน และ scopes ต้องตรง mobile path
  ///
  /// `GoogleSignIn()` constructor eager-init บน web อยู่แล้ว จึงอาจชนกับ call
  /// นี้ (completer complete ซ้ำ → StateError) — ไม่ถือว่าเป็น failure เพราะ
  /// `renderButton` รอ `initialized` ของ plugin เองต่ออยู่ดี
  static Future<void> _ensureInitialized() {
    return _initFuture ??= GoogleSignInPlatform.instance
        .initWithParams(
          const SignInInitParameters(scopes: <String>['email', 'profile']),
        )
        .catchError((Object e) {
          debugPrint('GoogleWebSignInButton: init raced/skipped ($e)');
        });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ensureInitialized(),
      builder: (context, snapshot) {
        final plugin = GoogleSignInPlatform.instance;
        if (snapshot.connectionState != ConnectionState.done ||
            plugin is! GoogleSignInPlugin) {
          return const SizedBox.shrink();
        }
        // renderButton throw StateError ถ้า init ไม่เคยเริ่มเลย (ไม่ควรเกิด
        // เพราะเรียก initWithParams ไปแล้ว) — กันไว้เพื่อไม่ให้หน้า login พัง
        try {
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: plugin.renderButton(
              configuration: GSIButtonConfiguration(
                type: GSIButtonType.icon,
                theme: GSIButtonTheme.outline,
                size: GSIButtonSize.large,
                shape: GSIButtonShape.pill,
              ),
            ),
          );
        } catch (e) {
          debugPrint('GoogleWebSignInButton render error: $e');
          return const SizedBox.shrink();
        }
      },
    );
  }
}
