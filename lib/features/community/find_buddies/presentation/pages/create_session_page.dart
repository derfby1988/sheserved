import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../../services/auth_service.dart';
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
  int _capacity = 5;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _repo = FitnessBuddiesRepository(Supabase.instance.client);
  }

  DateTime _roundUpToNearest(DateTime value, {int roundMinutes = 30}) {
    final roundedDown = DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute - (value.minute % roundMinutes),
    );
    return roundedDown.add(Duration(minutes: roundMinutes));
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year + 543} $hour:$minute น.';
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;

    final proposedStart = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final earliest = _roundUpToNearest(
      DateTime.now().add(const Duration(minutes: 15)),
    );
    final actualStart = proposedStart.isBefore(earliest)
        ? earliest
        : proposedStart;
    final previousStart = _startsAt;
    final previousEnd = _endsAt;
    var actualEnd = actualStart.add(const Duration(hours: 1));
    if (previousStart != null && previousEnd != null) {
      var normalizedPreviousEnd = previousEnd;
      if (!normalizedPreviousEnd.isAfter(previousStart)) {
        normalizedPreviousEnd = normalizedPreviousEnd.add(
          const Duration(days: 1),
        );
      }
      actualEnd = normalizedPreviousEnd.add(
        actualStart.difference(previousStart),
      );
      if (!actualEnd.isAfter(actualStart)) {
        actualEnd = actualStart.add(const Duration(hours: 1));
      }
    }

    if (!mounted) return;
    setState(() {
      _startsAt = actualStart;
      _endsAt = actualEnd;
    });
  }

  Future<void> _pickEnd() async {
    final base = _startsAt ?? DateTime.now();
    final baseDate = DateTime(base.year, base.month, base.day);
    final date = await showDatePicker(
      context: context,
      initialDate: baseDate,
      firstDate: baseDate,
      lastDate: baseDate.add(const Duration(days: 365)),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base.add(const Duration(hours: 1))),
    );
    if (time == null) return;

    var actualEnd = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final start = _startsAt;
    if (start != null && !actualEnd.isAfter(start)) {
      actualEnd = start.add(const Duration(hours: 1));
    }
    if (!mounted) return;
    setState(() => _endsAt = actualEnd);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final selectedStart = _startsAt;
    final selectedEnd = _endsAt;
    if (selectedStart == null || selectedEnd == null) return;
    final actorUserId = AuthService.instance.currentUser?.id;
    if (actorUserId == null) return;

    var startsAt = selectedStart;
    var endsAt = selectedEnd;
    final earliest = _roundUpToNearest(
      DateTime.now().add(const Duration(minutes: 15)),
    );
    if (startsAt.isBefore(earliest)) {
      final delta = earliest.difference(startsAt);
      startsAt = earliest;
      endsAt = endsAt.add(delta);
    }
    if (!endsAt.isAfter(startsAt)) {
      endsAt = startsAt.add(const Duration(hours: 1));
    }
    if (startsAt != selectedStart || endsAt != selectedEnd) {
      setState(() {
        _startsAt = startsAt;
        _endsAt = endsAt;
      });
    }

    setState(() => _submitting = true);
    try {
      await _repo.createSession(
        groupId: widget.groupId,
        actorUserId: actorUserId,
        capacity: _capacity,
        startsAt: startsAt,
        endsAt: endsAt,
        placeName: _placeCtrl.text.trim().isEmpty
            ? null
            : _placeCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('เพิ่มรอบนัดสำเร็จ')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('เพิ่มรอบนัดไม่สำเร็จ: $e')));
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
                title: Text(
                  _startsAt == null
                      ? 'เลือกเวลาเริ่ม'
                      : 'เริ่ม: ${_formatDateTime(_startsAt!)}',
                ),
                trailing: const Icon(Icons.schedule),
                onTap: _pickStart,
              ),
              ListTile(
                title: Text(
                  _endsAt == null
                      ? 'เลือกเวลาสิ้นสุด'
                      : 'สิ้นสุด: ${_formatDateTime(_endsAt!)}',
                ),
                trailing: const Icon(Icons.schedule),
                onTap: _pickEnd,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('จำนวนผู้เข้าร่วมสูงสุดในรอบนี้'),
                  Text('$_capacity คน'),
                ],
              ),
              Slider(
                value: _capacity.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                label: '$_capacity',
                onChanged: (value) => setState(() => _capacity = value.toInt()),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _placeCtrl,
                decoration: const InputDecoration(
                  labelText: 'ชื่อสถานที่ (ไม่บังคับ)',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'โน้ต (ไม่บังคับ)',
                ),
                maxLines: 3,
                maxLength: 500,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _submitting || _startsAt == null || _endsAt == null
                    ? null
                    : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('บันทึก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
