import 'package:flutter/material.dart';
import '../../data/repositories/crm_repository.dart';
import '../../data/services/appointment_slot_calculator_service.dart';

/// หน้าจอ Appointment Calendar & Queue Management สำหรับพนักงาน/แพทย์ (Group E - Phase 15-20)
class AppointmentCalendarPage extends StatefulWidget {
  final CrmRepository crmRepo;
  final AppointmentSlotCalculatorService slotCalculator;
  final String professionId;

  const AppointmentCalendarPage({
    super.key,
    required this.crmRepo,
    required this.slotCalculator,
    required this.professionId,
  });

  @override
  State<AppointmentCalendarPage> createState() => _AppointmentCalendarPageState();
}

class _AppointmentCalendarPageState extends State<AppointmentCalendarPage> {
  DateTime _selectedDate = DateTime.now();
  String _selectedStatusFilter = 'all';
  bool _isLoading = true;
  List<Map<String, dynamic>> _appointments = [];

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    setState(() => _isLoading = true);
    try {
      final appts = await widget.crmRepo.getAppointments(
        widget.professionId,
        status: _selectedStatusFilter == 'all' ? null : _selectedStatusFilter,
      );

      if (mounted) {
        setState(() {
          _appointments = appts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[AppointmentCalendarPage] error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'confirmed':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'no_show':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'confirmed':
        return 'ยืนยันแล้ว';
      case 'in_progress':
        return 'กำลังตรวจ/รับบริการ';
      case 'completed':
        return 'เสร็จสิ้น';
      case 'cancelled':
        return 'ยกเลิก';
      case 'no_show':
        return 'ไม่มาตามนัด';
      default:
        return 'รอยืนยัน';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('นัดหมาย & คิวผู้ป่วย (Appointment Queue)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAppointments,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Header: Status Filter & Date Selector
          Container(
            padding: const EdgeInsets.all(12.0),
            color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedStatusFilter,
                    decoration: const InputDecoration(
                      labelText: 'กรองตามสถานะ',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('ทั้งหมด')),
                      DropdownMenuItem(value: 'pending', child: Text('รอยืนยัน')),
                      DropdownMenuItem(value: 'confirmed', child: Text('ยืนยันแล้ว')),
                      DropdownMenuItem(value: 'in_progress', child: Text('กำลังรับบริการ')),
                      DropdownMenuItem(value: 'completed', child: Text('เสร็จสิ้น')),
                      DropdownMenuItem(value: 'cancelled', child: Text('ยกเลิก')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedStatusFilter = val);
                        _loadAppointments();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                      _loadAppointments();
                    }
                  },
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text('${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'),
                ),
              ],
            ),
          ),

          // Appointment List / Queue Cards
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _appointments.isEmpty
                    ? const Center(child: Text('ไม่พบรายการนัดหมาย'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _appointments.length,
                        itemBuilder: (context, index) {
                          final appt = _appointments[index];
                          final status = appt['status'] as String? ?? 'pending';
                          final scheduledAtStr = appt['scheduled_at'] as String?;
                          final duration = appt['duration_minutes'] as int? ?? 30;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getStatusColor(status).withOpacity(0.2),
                                child: Icon(Icons.alarm, color: _getStatusColor(status)),
                              ),
                              title: Text(
                                'นัดหมาย #${appt['appointment_no'] ?? appt['id'].toString().substring(0, 8)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text('เวลา: ${scheduledAtStr != null ? scheduledAtStr.split('T')[1].substring(0, 5) : 'ไม่ระบุ'} (${duration} นาที)'),
                                  Text('ช่องทาง: ${appt['booking_channel'] ?? 'walk_in'}'),
                                ],
                              ),
                              trailing: Chip(
                                backgroundColor: _getStatusColor(status).withOpacity(0.15),
                                label: Text(
                                  _getStatusLabel(status),
                                  style: TextStyle(
                                    color: _getStatusColor(status),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
