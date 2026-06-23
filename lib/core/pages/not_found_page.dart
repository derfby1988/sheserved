import 'package:flutter/material.dart';

/// 404 Page for unknown routes
/// ─────────────────────────────────────────────────────────────
/// Phase 6 — Route Security Implementation Plan
///
/// Displays a friendly 404 message with the attempted route shown
/// for debugging, and a "Go Home" button to redirect the user.
class NotFoundPage extends StatelessWidget {
  final String route;

  const NotFoundPage({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    // Log for security monitoring
    debugPrint('Security: Attempted access to unknown route: $route');

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'ไม่พบหน้านี้',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'เส้นทาง: $route',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
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
