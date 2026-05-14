import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/service_locator.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../admin/data/repositories/profession_repository.dart';

class ConsultationGuard {
  /// Entry point to start consultation
  static Future<void> startConsultation(BuildContext context) async {
    final user = ServiceLocator.instance.currentUser;
    final userRepo = ServiceLocator.instance.userRepository;
    final professionRepo = ProfessionRepository(Supabase.instance.client);

    if (user == null) {
      // 1. Not logged in -> Go to Login page
      Navigator.pushNamed(
        context,
        '/login',
        arguments: {'redirect': '/package-healthcare'},
      );
      return;
    }

    // Show loading indicator if it takes time
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final localUser = await userRepo.getUserById(user.id);

      bool isProvider = false;

      // 2. ตรวจสอบอาชีพและหมวดหมู่ (UserCategory) ว่าเป็นผู้ให้บริการปรึกษาหรือไม่
      if (localUser != null && localUser.professionId != null) {
        final profession = await professionRepo.getProfessionById(
          localUser.professionId!,
        );
        if (profession != null && profession.category.isConsultationProvider) {
          isProvider = true;
        }
      }

      // Close loading dialog
      if (context.mounted) {
        Navigator.pop(context);
      }

      if (isProvider) {
        // 3. เป็นผู้ให้บริการ -> นำทางไปหน้า Dashboard
        if (context.mounted) {
          Navigator.pushNamed(context, '/health-program-requests');
        }
        return;
      }

      // 4. ไม่ใช่ผู้ให้บริการ (ทรีตเป็น Consumer) -> ตรวจสอบ Health Info
      final profile = await userRepo.getConsumerProfile(user.id);
      if (profile == null ||
          profile.healthInfo == null ||
          profile.healthInfo!.isEmpty) {
        // No health info, redirect to Health Data Entry
        if (context.mounted) {
          Navigator.pushNamed(
            context,
            '/health-data-entry',
            arguments: {'redirect': '/package-healthcare'},
          );
        }
        return;
      }

      // 5. ข้อมูลครบถ้วน -> ไปหน้า Package Selection
      if (context.mounted) {
        Navigator.pushNamed(context, '/package-healthcare');
      }
    } catch (e) {
      // Close loading dialog on error
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    }
  }
}
