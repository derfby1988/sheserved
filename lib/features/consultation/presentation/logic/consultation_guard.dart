import 'package:flutter/material.dart';
import '../../../../services/service_locator.dart';
import '../../../auth/data/models/user_model.dart';

class ConsultationGuard {
  /// Entry point to start consultation
  static Future<void> startConsultation(BuildContext context) async {
    final user = ServiceLocator.instance.currentUser;
    final userRepo = ServiceLocator.instance.userRepository;

    if (user == null) {
      // 1. Not logged in -> Go to Login page
      // Normally we pass a redirect route, assuming '/package-healthcare' is the target.
      // Need to adjust route names according to the app's routing.
      Navigator.pushNamed(context, '/login', arguments: {
        'redirect': '/package-healthcare'
      });
      return;
    }

    // 2. Logged in, check profile type
    final localUser = await userRepo.getUserById(user.id);
    if (localUser != null && localUser.userType != UserType.consumer) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ฟีเจอร์นี้สำหรับผู้ใช้งานทั่วไปเท่านั้น')),
      );
      return;
    }

    // 3. User is consumer. Check health info.
    final profile = await userRepo.getConsumerProfile(user.id);
    if (profile == null || profile.healthInfo == null || profile.healthInfo!.isEmpty) {
      // No health info, redirect to Health Data Entry
      // Update the route according to the actual app routing
      Navigator.pushNamed(context, '/health-data-setup', arguments: {
        'redirect': '/package-healthcare'
      });
      return;
    }

    // 4. Everything is ready, go to Package Selection Page
    Navigator.pushNamed(context, '/package-healthcare');
  }
}
