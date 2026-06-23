import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

/// AuthGuardWidget — ป้องกันการเข้าถึง route ที่ต้องการ authentication / authorization
///
/// ใช้ wrap หน้าที่ต้องการ login หรือ role ระดับต่าง ๆ
///
/// ```dart
/// '/admin/professions': (context) => AuthGuardWidget(
///   requiredRole: 'admin',
///   child: const ProfessionAdminPage(),
/// ),
/// ```
class AuthGuardWidget extends StatelessWidget {
  final Widget child;

  /// Role ที่ต้องการ (optional) — 'admin' | 'provider' | 'consumer'
  final String? requiredRole;

  /// Route ที่จะ redirect กลับมาหลัง login (ถ้าไม่ระบุ ใช้ route ปัจจุบัน)
  final String? redirectRoute;

  const AuthGuardWidget({
    Key? key,
    required this.child,
    this.requiredRole,
    this.redirectRoute,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final currentRoute = redirectRoute ?? ModalRoute.of(context)?.settings.name ?? '/';

    // 1. ไม่ได้ Login → redirect ไปหน้า login พร้อม redirect argument
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.pushReplacementNamed(
            context,
            '/login',
            arguments: {'redirect': currentRoute},
          );
        }
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 2. ตรวจสอบ role
    if (requiredRole != null) {
      final bool hasRequiredRole;
      switch (requiredRole) {
        case 'admin':
          hasRequiredRole = user.isAdmin;
          break;
        case 'provider':
          hasRequiredRole = user.isProvider;
          break;
        case 'consumer':
          hasRequiredRole = !user.isProvider && !user.isAdmin;
          break;
        default:
          hasRequiredRole = user.hasRole(requiredRole!);
      }

      if (!hasRequiredRole) {
        return _ForbiddenPage(requiredRole: requiredRole!);
      }
    }

    // 3. ผ่านทุกเงื่อนไข → render child
    return child;
  }
}

/// หน้าแสดงเมื่อ user ไม่มีสิทธิ์ (403 Forbidden)
class _ForbiddenPage extends StatelessWidget {
  final String requiredRole;

  const _ForbiddenPage({required this.requiredRole});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'ไม่มีสิทธิ์เข้าถึง',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'คุณต้องมีสิทธิ์ "$requiredRole" เพื่อเข้าถึงหน้านี้',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
                child: const Text('กลับหน้าหลัก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
