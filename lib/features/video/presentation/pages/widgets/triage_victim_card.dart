import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../../models/triage_models.dart';
import '../../../data/repositories/victim_repository.dart';
import 'assign_triage_dialog.dart';

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
        child: ListTile(
          leading: _buildTriageBadge(),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  victim.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: victim.isMasked ? Colors.grey[600] : Colors.black87,
                  ),
                ),
              ),
              if (victim.verifyStatus == VictimVerifyStatus.disputed)
                const Icon(Icons.warning, color: Colors.orange, size: 18),
            ],
          ),
          subtitle: _buildSubtitle(),
          trailing: permissions.canTriage
              ? IconButton(
                  icon: const Icon(Icons.color_lens),
                  onPressed: () => _showAssignTriageDialog(context),
                  tooltip: 'ระบุสีคัดแยก',
                )
              : null,
          onTap: victim.canEdit ? () => _showEditDialog(context) : null,
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

  Future<void> _showAssignTriageDialog(BuildContext context) async {
    await AssignTriageDialog.show(
      context,
      victimId: victim.id,
      currentLevel: victim.triageLevel,
      canTriageBlack: permissions.canTriageBlack,
      repository: repository,
    );
    onChanged();
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
