import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';

class CreateSessionPage extends StatefulWidget {
  final String groupId;
  const CreateSessionPage({super.key, required this.groupId});

  @override
  State<CreateSessionPage> createState() => _CreateSessionPageState();
}

class _CreateSessionPageState extends State<CreateSessionPage> {
  late final FitnessBuddiesRepository _repo;
  final _formKey = GlobalKey<FormState>();
  DateTime? _startsAt;
  DateTime? _endsAt;
  final _placeCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _repo = FitnessBuddiesRepository(Supabase.instance.client);
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (date == null) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() => _startsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickEnd() async {
    final base = _startsAt ?? DateTime.now();
    final date = await showDatePicker(context: context, initialDate: base, firstDate: base, lastDate: base.add(const Duration(days: 365)));
    if (date == null) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base.add(const Duration(hours: 1))));
    if (time == null) return;
    setState(() => _endsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await _repo.createSession(
        groupId: widget.groupId,
        startsAt: _startsAt!,
        endsAt: _endsAt!,
        placeName: _placeCtrl.text.trim().isEmpty ? null : _placeCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เพิ่มรอบนัดสำเร็จ')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เพิ่มรอบนัดไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เพิ่มรอบนัด')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                title: Text(_startsAt == null ? 'เลือกเวลาเริ่ม' : 'เริ่ม: ${_startsAt!.toLocal()}'),
                trailing: const Icon(Icons.schedule),
                onTap: _pickStart,
              ),
              ListTile(
                title: Text(_endsAt == null ? 'เลือกเวลาสิ้นสุด' : 'สิ้นสุด: ${_endsAt!.toLocal()}'),
                trailing: const Icon(Icons.schedule),
                onTap: _pickEnd,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _placeCtrl,
                decoration: const InputDecoration(labelText: 'ชื่อสถานที่ (ไม่บังคับ)'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(labelText: 'โน้ต (ไม่บังคับ)'),
                maxLines: 3,
                maxLength: 500,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _submitting || _startsAt == null || _endsAt == null ? null : _submit,
                icon: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                label: const Text('บันทึก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
