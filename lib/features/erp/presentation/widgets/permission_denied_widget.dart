import 'package:flutter/material.dart';

/// Reusable widget สำหรับแสดงหน้าจอ "ไม่มีสิทธิ์เข้าถึง"
/// ใช้ภายใน Scaffold ของแต่ละ module page
class PermissionDeniedWidget extends StatelessWidget {
  final String moduleName;
  final String moduleLabel;
  final VoidCallback? onRequestPermission;

  const PermissionDeniedWidget({
    super.key,
    required this.moduleName,
    required this.moduleLabel,
    this.onRequestPermission,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 80,
              color: Colors.grey.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'ขออภัย คุณไม่มีสิทธิ์เข้าถึง$moduleLabel',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Module: $moduleName',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (onRequestPermission != null)
                  OutlinedButton.icon(
                    onPressed: onRequestPermission,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('ขอสิทธิ์'),
                  ),
                ElevatedButton.icon(
                  onPressed: () => _showContactAdminDialog(context),
                  icon: const Icon(Icons.contact_support),
                  label: const Text('ติดต่อผู้ดูแลระบบ'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('ย้อนกลับ'),
            ),
          ],
        ),
      ),
    );
  }

  void _showContactAdminDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ติดต่อผู้ดูแลระบบ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'หากต้องการสิทธิ์เข้าถึง$moduleLabel กรุณาติดต่อผู้ดูแลระบบขององค์กร',
            ),
            const SizedBox(height: 16),
            const ListTile(
              leading: Icon(Icons.email),
              title: Text('อีเมล'),
              subtitle: Text('admin@your-organization.com'),
            ),
            const ListTile(
              leading: Icon(Icons.phone),
              title: Text('โทรศัพท์'),
              subtitle: Text('02-XXX-XXXX'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }
}
