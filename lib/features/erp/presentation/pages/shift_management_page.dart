import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/shift.dart';
import '../../data/models/employee.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';

class ShiftManagementPage extends ConsumerStatefulWidget {
  final String professionId;

  const ShiftManagementPage({super.key, required this.professionId});

  @override
  ConsumerState<ShiftManagementPage> createState() => _ShiftManagementPageState();
}

class _ShiftManagementPageState extends ConsumerState<ShiftManagementPage> {
  DateTime _selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseThreeProvider.notifier).loadEmployees(widget.professionId);
      _loadShifts();
    });
  }

  void _loadShifts() {
    final from = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final to = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    ref.read(phaseThreeProvider.notifier).loadShifts(
      widget.professionId,
      fromDate: from,
      toDate: to,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseThreeProvider);
    final shifts = state.shifts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตารางเวร / Shifts'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildMonthSelector(),
                const SizedBox(height: 16),
                if (shifts.isEmpty)
                  const Center(
                    child: Text(
                      'ไม่มีตารางเวรในเดือนนี้',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...shifts.map((shift) => _ShiftCard(
                        shift: shift,
                        employees: state.employees,
                        onEdit: () => _showShiftDialog(shift: shift),
                      )),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showShiftDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMonthSelector() {
    return GlassCard(
      section: GlassSection.card,
      borderRadius: 12,
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() => _selectedMonth = DateTime(
                _selectedMonth.year,
                _selectedMonth.month - 1,
              ));
              _loadShifts();
            },
          ),
          Text(
            '${_selectedMonth.month}/${_selectedMonth.year}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() => _selectedMonth = DateTime(
                _selectedMonth.year,
                _selectedMonth.month + 1,
              ));
              _loadShifts();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showShiftDialog({Shift? shift}) async {
    final isEdit = shift != null;
    final state = ref.read(phaseThreeProvider);
    final employees = state.employees;

    String? selectedEmployeeId = shift?.employeeId ?? (employees.isNotEmpty ? employees.first.id : null);
    DateTime shiftDate = shift?.shiftDate ?? DateTime.now();
    TimeOfDay startTime = shift != null
        ? TimeOfDay.fromDateTime(shift.startTime)
        : const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay? endTime = shift != null && shift.endTime != null
        ? TimeOfDay.fromDateTime(shift.endTime!)
        : const TimeOfDay(hour: 18, minute: 0);
    String shiftType = shift?.shiftType ?? 'regular';
    String shiftStatus = shift?.status ?? 'scheduled';
    final notesController = TextEditingController(text: shift?.notes ?? '');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'แก้ไขเวร' : 'เพิ่มเวร'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (employees.isNotEmpty)
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'พนักงาน'),
                  initialValue: selectedEmployeeId,
                  items: employees.map((e) => DropdownMenuItem(
                    value: e.id,
                    child: Text(e.fullName),
                  )).toList(),
                  onChanged: (v) => selectedEmployeeId = v,
                ),
              const SizedBox(height: 12),
              ListTile(
                title: const Text('วันที่'),
                subtitle: Text('${shiftDate.day}/${shiftDate.month}/${shiftDate.year}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: shiftDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) shiftDate = picked;
                },
              ),
              ListTile(
                title: const Text('เวลาเริ่ม'),
                subtitle: Text(startTime.format(ctx)),
                trailing: const Icon(Icons.access_time),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: startTime,
                  );
                  if (picked != null) startTime = picked;
                },
              ),
              ListTile(
                title: const Text('เวลาสิ้นสุด'),
                subtitle: Text(endTime?.format(ctx) ?? '-'),
                trailing: const Icon(Icons.access_time_filled),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: endTime ?? const TimeOfDay(hour: 18, minute: 0),
                  );
                  if (picked != null) endTime = picked;
                },
              ),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'ประเภทเวร'),
                initialValue: shiftType,
                items: const [
                  DropdownMenuItem(value: 'regular', child: Text('ปกติ')),
                  DropdownMenuItem(value: 'overtime', child: Text('ล่วงเวลา')),
                  DropdownMenuItem(value: 'holiday', child: Text('วันหยุด')),
                  DropdownMenuItem(value: 'on_call', child: Text('เวร')),
                ],
                onChanged: (v) => shiftType = v ?? 'regular',
              ),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'สถานะ'),
                initialValue: shiftStatus,
                items: const [
                  DropdownMenuItem(value: 'scheduled', child: Text('กำหนดแล้ว')),
                  DropdownMenuItem(value: 'checked_in', child: Text('เข้างาน')),
                  DropdownMenuItem(value: 'checked_out', child: Text('ออกงาน')),
                  DropdownMenuItem(value: 'absent', child: Text('ขาด')),
                  DropdownMenuItem(value: 'approved', child: Text('อนุมัติ')),
                ],
                onChanged: (v) => shiftStatus = v ?? 'scheduled',
              ),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'หมายเหตุ'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              if (selectedEmployeeId == null) return;
              final start = DateTime(
                shiftDate.year, shiftDate.month, shiftDate.day,
                startTime.hour, startTime.minute,
              );
              final end = endTime != null
                  ? DateTime(
                      shiftDate.year, shiftDate.month, shiftDate.day,
                      endTime!.hour, endTime!.minute,
                    )
                  : null;
              Navigator.of(ctx).pop({
                'employee_id': selectedEmployeeId,
                'shift_date': shiftDate.toIso8601String(),
                'start_time': start.toIso8601String(),
                if (end != null) 'end_time': end.toIso8601String(),
                'shift_type': shiftType,
                'status': shiftStatus,
                'notes': notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                'profession_id': widget.professionId,
              });
            },
            child: Text(isEdit ? 'บันทึก' : 'สร้าง'),
          ),
        ],
      ),
    );

    if (result == null) return;

    final notifier = ref.read(phaseThreeProvider.notifier);
    if (isEdit) {
      await notifier.updateShift(shift.id, result);
    } else {
      await notifier.createShift(result);
    }
  }
}

class _ShiftCard extends StatelessWidget {
  final Shift shift;
  final List<Employee> employees;
  final VoidCallback onEdit;

  const _ShiftCard({
    required this.shift,
    required this.employees,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final emp = employees.firstWhere(
      (e) => e.id == shift.employeeId,
      orElse: () => Employee(
        id: '', professionId: '', fullName: 'ไม่ทราบ', employeeCode: '',
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
      ),
    );

    final typeColors = {
      'regular': Colors.blue,
      'overtime': Colors.orange,
      'holiday': Colors.purple,
      'on_call': Colors.teal,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: typeColors[shift.shiftType] ?? Colors.grey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    emp.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${shift.shiftDate.day}/${shift.shiftDate.month}/${shift.shiftDate.year} '
                    '(${shift.shiftTypeLabel})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '${_formatTime(shift.startTime)} - ${shift.endTime != null ? _formatTime(shift.endTime!) : '-'}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (shift.hoursWorked != null)
                    Text(
                      '${shift.hoursWorked!.toStringAsFixed(1)} ชม.',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(shift.status).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                shift.statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: _statusColor(shift.status),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'scheduled': return Colors.blue;
      case 'checked_in': return Colors.green;
      case 'checked_out': return Colors.teal;
      case 'absent': return Colors.red;
      case 'approved': return Colors.purple;
      default: return Colors.grey;
    }
  }
}
