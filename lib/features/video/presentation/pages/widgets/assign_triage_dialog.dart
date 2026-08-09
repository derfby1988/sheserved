import 'package:flutter/material.dart';
import '../../../models/triage_models.dart';
import '../../../data/repositories/victim_repository.dart';

class AssignTriageDialog extends StatefulWidget {
  final String victimId;
  final TriageLevel currentLevel;
  final bool canTriageBlack;
  final VictimRepository repository;

  const AssignTriageDialog({
    super.key,
    required this.victimId,
    required this.currentLevel,
    required this.canTriageBlack,
    required this.repository,
  });

  static Future<void> show(
    BuildContext context, {
    required String victimId,
    required TriageLevel currentLevel,
    required bool canTriageBlack,
    required VictimRepository repository,
  }) {
    return showDialog(
      context: context,
      builder: (context) => AssignTriageDialog(
        victimId: victimId,
        currentLevel: currentLevel,
        canTriageBlack: canTriageBlack,
        repository: repository,
      ),
    );
  }

  @override
  State<AssignTriageDialog> createState() => _AssignTriageDialogState();
}

class _AssignTriageDialogState extends State<AssignTriageDialog> {
  TriageLevel? _selected;
  final _noteController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _noteController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDeceased = _selected == TriageLevel.deceased;
    final noteValid = !isDeceased || _noteController.text.length >= 10;
    final confirmValid = !isDeceased || _confirmController.text.trim() == 'ยืนยัน';

    return AlertDialog(
      title: const Text('ระบุสีคัดแยก'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...TriageLevel.values.map((level) {
              final isDisabled = level == TriageLevel.deceased && !widget.canTriageBlack;
              return RadioListTile<TriageLevel>(
                value: level,
                groupValue: _selected,
                onChanged: isDisabled ? null : (v) => setState(() => _selected = v),
                title: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Color(level.colorValue),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: level == TriageLevel.white
                              ? Colors.grey[300]!
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(level.displayName),
                  ],
                ),
                subtitle: isDisabled
                    ? const Text('เฉพาะผู้ให้บริการสุขภาพ (provider)', style: TextStyle(fontSize: 11, color: Colors.red))
                    : null,
              );
            }),
            if (isDeceased) ...[
              const Divider(),
              TextField(
                controller: _noteController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'เหตุผลทางคลินิก (บังคับ ≥ 10 อักขระ)',
                  counterText: '${_noteController.text.length} ตัวอักษร',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmController,
                decoration: const InputDecoration(
                  labelText: 'พิมพ์ "ยืนยัน" เพื่อยืนยัน',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        ElevatedButton(
          onPressed: _selected != null && noteValid && confirmValid && !_saving
              ? _save
              : null,
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
      await widget.repository.assignTriage(
        victimId: widget.victimId,
        level: _selected!,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
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
