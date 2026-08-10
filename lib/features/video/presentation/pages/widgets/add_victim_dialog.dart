import 'package:flutter/material.dart';
import '../../../data/repositories/victim_repository.dart';

class AddVictimDialog extends StatefulWidget {
  final String incidentId;
  final VictimRepository repository;

  const AddVictimDialog({
    super.key,
    required this.incidentId,
    required this.repository,
  });

  static Future<void> show(
    BuildContext context,
    String incidentId,
    VictimRepository repository,
  ) {
    return showDialog(
      context: context,
      builder: (context) => AddVictimDialog(
        incidentId: incidentId,
        repository: repository,
      ),
    );
  }

  @override
  State<AddVictimDialog> createState() => _AddVictimDialogState();
}

class _AddVictimDialogState extends State<AddVictimDialog> {
  String _prefix = 'ไม่ระบุ';
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  bool _consent = false;
  bool _saving = false;

  static const List<String> _prefixOptions = [
    'ไม่ระบุ',
    'นาย',
    'นาง',
    'นางสาว',
    'ด.ช.',
    'ด.ญ.',
  ];

  String _buildMaskedPreview() {
    final first = _firstNameController.text.trim();
    if (first.isEmpty) return '$_prefix ...';
    final firstChar = first[0];
    return '$_prefix $firstChar';
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('แจ้งชื่อผู้ป่วย'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _prefix,
              decoration: const InputDecoration(labelText: 'คำนำหน้า'),
              items: _prefixOptions
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) => setState(() => _prefix = v ?? 'ไม่ระบุ'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _firstNameController,
              decoration: const InputDecoration(labelText: 'ชื่อ'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _lastNameController,
              decoration: const InputDecoration(labelText: 'สกุล'),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.visibility_off, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: _firstNameController,
                      builder: (context, value, _) {
                        return Text(
                          'ผู้ชมทั่วไปจะเห็นเป็น "${_buildMaskedPreview()}" เฉพาะทีมอาสาที่เข้าช่วยเหลือเท่านั้นที่เห็นชื่อเต็ม',
                          style: const TextStyle(fontSize: 11, color: Colors.blue),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _consent,
              onChanged: (v) => setState(() => _consent = v ?? false),
              title: const Text(
                'ฉันยืนยันว่าข้อมูลนี้เป็นการแจ้งเพื่อช่วยเหลือผู้ประสบเหตุ และยินยอมให้จิตอาสาที่เข้าร่วมช่วยเหลือเห็นชื่อ',
                style: TextStyle(fontSize: 12),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        ElevatedButton(
          onPressed: _consent && !_saving ? _save : null,
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
              : const Text('บันทึก'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repository.addVictim(
        incidentId: widget.incidentId,
        prefix: _prefix,
        firstName: _firstNameController.text.trim().isEmpty
            ? null
            : _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim().isEmpty
            ? null
            : _lastNameController.text.trim(),
        consent: _consent,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
