import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/service_locator.dart';
import '../../../admin/data/repositories/profession_repository.dart';

class ConsultationGuard {
  static bool _isNavigating = false; // Guard: ป้องกัน double-tap ระหว่างตรวจสอบ
  static bool _isNavigatingPatient = false; // Guard: ป้องกัน double-tap สำหรับ patient flow

  /// Entry point to start consultation — navigate ทันทีโดยไม่แสดง loading dialog
  static Future<void> startConsultation(BuildContext context) async {
    if (_isNavigating) return; // ป้องกันกดซ้ำขณะกำลังตรวจสอบ
    _isNavigating = true;

    final user = ServiceLocator.instance.currentUser;
    final userRepo = ServiceLocator.instance.userRepository;
    final professionRepo = ProfessionRepository(Supabase.instance.client);

    if (user == null) {
      // 1. Not logged in -> Go to Login page
      if (context.mounted) {
        Navigator.pushNamed(
          context,
          '/login',
          arguments: {'redirect': '/package-healthcare'},
        );
      }
      _isNavigating = false;
      return;
    }

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

      if (isProvider) {
        // 3. เป็นผู้ให้บริการ -> นำทางไปหน้า Dashboard
        if (context.mounted) {
          Navigator.pushNamed(context, '/health-program-requests');
        }
        _isNavigating = false;
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
        _isNavigating = false;
        return;
      }

      // 5. ข้อมูลครบถ้วน -> ไปหน้า Package Selection
      if (context.mounted) {
        Navigator.pushNamed(context, '/package-healthcare');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    } finally {
      _isNavigating = false;
    }
  }

  /// Entry point for patient consultation — skip provider check, always treat as consumer
  static Future<void> startConsultationForPatient(BuildContext context) async {
    if (_isNavigatingPatient) return; // ป้องกันกดซ้ำขณะกำลังตรวจสอบ
    _isNavigatingPatient = true;

    final user = ServiceLocator.instance.currentUser;
    final userRepo = ServiceLocator.instance.userRepository;

    if (user == null) {
      // 1. Not logged in -> Go to Login page
      if (context.mounted) {
        Navigator.pushNamed(
          context,
          '/login',
          arguments: {
            'redirect': '/package-healthcare',
            'args': {'skipProviderCheck': true},
          },
        );
      }
      _isNavigatingPatient = false;
      return;
    }

    try {
      // 2. ตรวจสอบ Health Info (skip provider check)
      final profile = await userRepo.getConsumerProfile(user.id);
      if (profile == null ||
          profile.healthInfo == null ||
          profile.healthInfo!.isEmpty) {
        // No health info, redirect to Health Data Entry
        if (context.mounted) {
          Navigator.pushNamed(
            context,
            '/health-data-entry',
            arguments: {
              'redirect': '/package-healthcare',
              'args': {'skipProviderCheck': true},
            },
          );
        }
        _isNavigatingPatient = false;
        return;
      }

      // 3. ข้อมูลครบถ้วน -> ไปหน้า Package Selection
      if (context.mounted) {
        Navigator.pushNamed(
          context,
          '/package-healthcare',
          arguments: {'skipProviderCheck': true},
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    } finally {
      _isNavigatingPatient = false;
    }
  }
}
