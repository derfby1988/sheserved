import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../../models/triage_models.dart';
import '../../../data/repositories/victim_repository.dart';

class TriageVictimCard extends StatelessWidget {
  final IncidentVictim victim;
  final ViewerPermissions permissions;
  final VictimRepository repository;
  final VoidCallback onChanged;

  const TriageVictimCard({
    super.key,
    required this.victim,
    required this.permissions,
    required this.repository,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isUnassessed = victim.triageLevel == TriageLevel.white && victim.triagedAt == null;
    return Slidable(
      key: ValueKey(victim.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.6,
        children: [
          if (permissions.canDispute)
            SlidableAction(
              onPressed: (_) => _showDisputeDialog(context),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              icon: Icons.warning,
              label: 'โต้แย้ง',
            ),
          if (permissions.canDelete)
            SlidableAction(
              onPressed: (_) => _showDeleteDialog(context),
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              icon: Icons.delete,
              label: 'ลบ',
            ),
        ],
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildTriageBadge(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: victim.canEdit ? () => _showEditDialog(context) : null,
                                child: Text(
                                  victim.displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: victim.isMasked ? Colors.grey[600] : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                            if (victim.verifyStatus == VictimVerifyStatus.disputed)
                              const Icon(Icons.warning, color: Colors.orange, size: 18),
                          ],
                        ),
                        const SizedBox(height: 2),
                        _buildSubtitle(),
                      ],
                    ),
                  ),
                ],
              ),
              if (victim.hasHealthData && (permissions.canTriage || permissions.canViewFull)) ...[
                const SizedBox(height: 6),
                _buildHealthDataButton(context),
              ],
              if (permissions.canTriage) ...[
                const SizedBox(height: 8),
                _buildInlineTriageButtons(context, isUnassessed),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTriageBadge() {
    final color = Color(victim.triageLevel.colorValue);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: victim.triageLevel == TriageLevel.white ? Colors.grey[300]! : Colors.transparent,
        ),
      ),
      child: victim.triageLevel == TriageLevel.white && victim.triagedAt == null
          ? const Icon(Icons.question_mark, size: 18, color: Colors.grey)
          : null,
    );
  }

  Widget _buildSubtitle() {
    final parts = <String>[];
    if (victim.triagedAt != null) {
      parts.add(victim.triageLevel.displayName);
    } else {
      parts.add('ยังไม่ประเมิน');
    }
    if (victim.triageNote != null && victim.triageNote!.isNotEmpty) {
      parts.add(victim.triageNote!);
    }
    if (victim.reportedByName != null) {
      parts.add('แจ้งโดย: ${victim.reportedByName}');
    }
    return Text(
      parts.join(' · '),
      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildInlineTriageButtons(BuildContext context, bool isUnassessed) {
    return Row(
      children: [
        if (!isUnassessed)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'เปลี่ยนระดับ:',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ),
        ...TriageLevel.values.where((l) => l != TriageLevel.white).map((level) {
          final isDeceased = level == TriageLevel.deceased;
          final isDisabled = isDeceased && !permissions.canTriageBlack;
          final isCurrent = victim.triageLevel == level;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: isDisabled ? null : () => _onTriageButtonPressed(context, level),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isCurrent ? Color(level.colorValue) : Color(level.colorValue).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isCurrent ? Color(level.colorValue) : Color(level.colorValue).withOpacity(0.4),
                    width: isCurrent ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(level.emoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 3),
                    Text(
                      level.displayName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isCurrent ? Colors.white : Color(level.colorValue),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        if (permissions.canTriageBlack == false && !isUnassessed)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Tooltip(
              message: 'เฉพาะผู้ให้บริการสุขภาพ (provider)',
              child: Icon(Icons.lock, size: 14, color: Colors.grey[400]),
            ),
          ),
      ],
    );
  }

  Widget _buildHealthDataButton(BuildContext context) {
    return InkWell(
      onTap: () => _onHealthDataPressed(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withOpacity(0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.medical_services, size: 14, color: Colors.blue),
            SizedBox(width: 4),
            Text('ดูข้อมูลสุขภาพ', style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _onTriageButtonPressed(BuildContext context, TriageLevel level) async {
    if (level == TriageLevel.deceased) {
      await _showDeceasedDialog(context);
      return;
    }
    if (victim.triageLevel != TriageLevel.white && victim.triagedAt != null && victim.triageLevel != level) {
      final confirmed = await _showChangeWarning(context, level);
      if (confirmed != true) return;
    }
    try {
      await repository.assignTriage(victimId: victim.id, level: level);
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<bool?> _showChangeWarning(BuildContext context, TriageLevel newLevel) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการเปลี่ยนระดับ'),
        content: Text(
          '${victim.displayName} ถูกประเมินเป็น ${victim.triageLevel.emoji} ${victim.triageLevel.displayName}'
          '${victim.triagedByName != null ? ' โดย ${victim.triagedByName}' : ''}'
          '${victim.triagedAt != null ? ' เมื่อ ${_formatTime(victim.triagedAt!)}' : ''}'
          ' — การเปลี่ยนของคุณจะแทนที่ค่าเดิม',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('เปลี่ยน')),
        ],
      ),
    );
  }

  Future<void> _showDeceasedDialog(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _DeceasedConfirmDialog(),
    );
    if (result == null) return;
    try {
      await repository.assignTriage(
        victimId: victim.id,
        level: TriageLevel.deceased,
        note: result['note'] as String,
      );
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _onHealthDataPressed(BuildContext context) async {
    try {
      final result = await repository.unlockHealthData(victim.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ปลดล็อกข้อมูลสุขภาพสำเร็จ')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditVictimDialog(
        victim: victim,
        repository: repository,
      ),
    );
    if (result != null) onChanged();
  }

  Future<void> _showDisputeDialog(BuildContext context) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReasonDialog(
        title: 'โต้แย้งความถูกต้องของชื่อ',
        minLength: 10,
        hintText: 'ระบุเหตุผลที่โต้แย้ง (อย่างน้อย 10 อักขระ)',
      ),
    );
    if (reason == null || reason.length < 10) return;
    try {
      await repository.disputeVictim(victimId: victim.id, reason: reason);
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReasonDialog(
        title: 'ลบรายชื่อ',
        minLength: 10,
        hintText: 'ระบุเหตุผลที่ลบ (อย่างน้อย 10 อักขระ)',
      ),
    );
    if (reason == null || reason.length < 10) return;
    try {
      await repository.deleteVictim(victimId: victim.id, reason: reason);
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }
}

class _EditVictimDialog extends StatefulWidget {
  final IncidentVictim victim;
  final VictimRepository repository;

  const _EditVictimDialog({required this.victim, required this.repository});

  @override
  State<_EditVictimDialog> createState() => _EditVictimDialogState();
}

class _EditVictimDialogState extends State<_EditVictimDialog> {
  late TextEditingController _prefixController;
  late TextEditingController _firstController;
  late TextEditingController _lastController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefixController = TextEditingController(text: widget.victim.prefix ?? 'ไม่ระบุ');
    _firstController = TextEditingController(text: widget.victim.firstName ?? '');
    _lastController = TextEditingController(text: widget.victim.lastName ?? '');
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _firstController.dispose();
    _lastController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('แก้ไขชื่อ'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _prefixController,
            decoration: const InputDecoration(labelText: 'คำนำหน้า'),
          ),
          TextField(
            controller: _firstController,
            decoration: const InputDecoration(labelText: 'ชื่อ'),
          ),
          TextField(
            controller: _lastController,
            decoration: const InputDecoration(labelText: 'สกุล'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const CircularProgressIndicator() : const Text('บันทึก'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repository.editVictimName(
        victimId: widget.victim.id,
        prefix: _prefixController.text.trim(),
        firstName: _firstController.text.trim().isEmpty ? null : _firstController.text.trim(),
        lastName: _lastController.text.trim().isEmpty ? null : _lastController.text.trim(),
      );
      if (mounted) Navigator.pop(context, {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ReasonDialog extends StatefulWidget {
  final String title;
  final int minLength;
  final String hintText;

  const _ReasonDialog({
    required this.title,
    required this.minLength,
    required this.hintText,
  });

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _isValid = _controller.text.trim().length >= widget.minLength;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: widget.hintText,
          helperText: 'อย่างน้อย ${widget.minLength} อักขระ',
          counterText: '${_controller.text.length} ตัวอักษร',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        ElevatedButton(
          onPressed: _isValid ? () => Navigator.pop(context, _controller.text.trim()) : null,
          child: const Text('ยืนยัน'),
        ),
      ],
    );
  }
}

class _DeceasedConfirmDialog extends StatefulWidget {
  const _DeceasedConfirmDialog();

  @override
  State<_DeceasedConfirmDialog> createState() => _DeceasedConfirmDialogState();
}

class _DeceasedConfirmDialogState extends State<_DeceasedConfirmDialog> {
  final _noteController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final noteValid = _noteController.text.length >= 10;
    final confirmValid = _confirmController.text.trim() == 'ยืนยัน';
    return AlertDialog(
      title: const Text('ยืนยันเคสดำ (เสียชีวิต)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'การระบุเคสดำเป็นการตัดสินใจที่สำคัญ '
              'โปรดยืนยันด้วยเหตุผลทางคลินิก',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
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
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        ElevatedButton(
          onPressed: noteValid && confirmValid
              ? () => Navigator.pop(context, {'note': _noteController.text.trim()})
              : null,
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}
