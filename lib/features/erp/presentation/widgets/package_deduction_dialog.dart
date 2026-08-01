import 'package:flutter/material.dart';
import '../../data/models/customer_package.dart';
import '../../data/repositories/crm_repository.dart';

/// Dialog สำหรับตัด Session คอร์สแพ็กเกจล่วงหน้า (Group C - Phase 10)
class PackageDeductionDialog extends StatefulWidget {
  final CrmRepository crmRepo;
  final CustomerPackage package;
  final String? appointmentId;

  const PackageDeductionDialog({
    super.key,
    required this.crmRepo,
    required this.package,
    this.appointmentId,
  });

  @override
  State<PackageDeductionDialog> createState() => _PackageDeductionDialogState();
}

class _PackageDeductionDialogState extends State<PackageDeductionDialog> {
  final _sessionsController = TextEditingController(text: '1');
  final _notesController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _sessionsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleDeduct() async {
    final sessions = int.tryParse(_sessionsController.text.trim()) ?? 1;
    if (sessions <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาระบุจำนวนเซสชันให้ถูกต้อง')),
      );
      return;
    }

    if (sessions > widget.package.remainingSessions) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('จำนวนเซสชันคงเหลือไม่เพียงพอ (เหลือ ${widget.package.remainingSessions} ครั้ง)')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final success = await widget.crmRepo.deductPackageSession(
      widget.package.id,
      sessionsToDeduct: sessions,
      appointmentId: widget.appointmentId,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ตัดเซสชันแพ็กเกจ ${widget.package.packageName} เรียบร้อยแล้ว')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดในการตัดเซสชัน')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pkg = widget.package;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.card_membership, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('ตัดเซสชันคอร์สแพ็กเกจ'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pkg.packageName,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('เซสชันทั้งหมด: ${pkg.totalSessions} ครั้ง'),
                  Text('ใช้ไปแล้ว: ${pkg.usedSessions} ครั้ง'),
                  Text(
                    'คงเหลือ: ${pkg.remainingSessions} ครั้ง',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: pkg.remainingSessions > 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sessionsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'จำนวนเซสชันที่ต้องการตัด (ครั้ง)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.exposure_minus_1),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'บันทึกเพิ่มเติม (ตัวเลือก)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.note),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _handleDeduct,
          icon: _isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: const Text('ยืนยันตัดเซสชัน'),
        ),
      ],
    );
  }
}
