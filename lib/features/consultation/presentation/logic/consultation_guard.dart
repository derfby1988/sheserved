import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/service_locator.dart';
import '../../../admin/data/repositories/profession_repository.dart';
import '../../data/models/consultation_request_model.dart';

class ConsultationGuard {
  static bool _isNavigating = false; // Guard: ป้องกัน double-tap ระหว่างตรวจสอบ
  static bool _isNavigatingPatient =
      false; // Guard: ป้องกัน double-tap สำหรับ patient flow

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

      // 5. มีคำปรึกษาที่เปิดอยู่แล้ว -> เปิดห้องแชทเดิม ไม่ต้องซื้อใหม่
      final activeConsultation = await findActiveConsultation(user.id);
      if (activeConsultation != null) {
        if (context.mounted) {
          Navigator.pushNamed(
            context,
            '/chart-board',
            arguments: {'request': activeConsultation},
          );
        }
        _isNavigating = false;
        return;
      }

      // 6. ข้อมูลครบถ้วน -> ไปหน้า Package Selection
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

  /// Latest consultation that is still open for the patient (pending = waiting
  /// for an expert, in_progress = chat running). Re-entering the consultation
  /// entry point should reopen that room instead of starting a new purchase,
  /// which otherwise re-asks the pain level and creates duplicate requests.
  static Future<ConsultationRequestModel?> findActiveConsultation(
    String userId,
  ) async {
    try {
      final repo = ServiceLocator.instance.consultationRepository;
      final requests = await repo.getUserRequests(userId);
      for (final request in requests) {
        if (request.status == 'pending' || request.status == 'in_progress') {
          return request;
        }
      }
    } catch (e) {
      debugPrint('ConsultationGuard: active consultation lookup failed: $e');
    }
    return null;
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

      // 3. มีคำปรึกษาที่เปิดอยู่แล้ว -> เปิดห้องแชทเดิม ไม่ต้องซื้อใหม่
      final activeConsultation = await findActiveConsultation(user.id);
      if (activeConsultation != null) {
        if (context.mounted) {
          Navigator.pushNamed(
            context,
            '/chart-board',
            arguments: {'request': activeConsultation},
          );
        }
        _isNavigatingPatient = false;
        return;
      }

      // 4. ข้อมูลครบถ้วน -> ไปหน้า Package Selection
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
