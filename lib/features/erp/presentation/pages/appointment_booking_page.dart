import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/services/appointment_slot_calculator_service.dart';
import '../../data/repositories/crm_repository.dart';

/// หน้าจอจองนัดหมายสำหรับผู้ป่วย/ผู้รับบริการ (Patient/Consumer App Booking - Group F Phase 21-23)
class AppointmentBookingPage extends StatefulWidget {
  final SupabaseClient client;
  final CrmRepository crmRepo;
  final AppointmentSlotCalculatorService slotCalculator;
  final String professionId;
  final String patientUserId;

  const AppointmentBookingPage({
    super.key,
    required this.client,
    required this.crmRepo,
    required this.slotCalculator,
    required this.professionId,
    required this.patientUserId,
  });

  @override
  State<AppointmentBookingPage> createState() => _AppointmentBookingPageState();
}

class _AppointmentBookingPageState extends State<AppointmentBookingPage> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  DateTime? _selectedSlot;
  String? _selectedPractitionerId;
  String? _selectedServiceTypeId;
  final _notesController = TextEditingController();

  List<Map<String, dynamic>> _practitioners = [];
  List<Map<String, dynamic>> _serviceTypes = [];
  List<DateTime> _availableSlots = [];
  bool _isLoadingSlots = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadMasterData();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadMasterData() async {
    try {
      final pracRes = await widget.client
          .from('practitioners')
          .select()
          .eq('profession_id', widget.professionId)
          .eq('is_active', true);

      final serviceRes = await widget.client
          .from('appointment_service_types')
          .select()
          .eq('profession_id', widget.professionId)
          .eq('is_active', true);

      if (mounted) {
        setState(() {
          _practitioners = List<Map<String, dynamic>>.from(pracRes);
          _serviceTypes = List<Map<String, dynamic>>.from(serviceRes);

          if (_practitioners.isNotEmpty) {
            _selectedPractitionerId = _practitioners.first['id'] as String;
          }
          if (_serviceTypes.isNotEmpty) {
            _selectedServiceTypeId = _serviceTypes.first['id'] as String;
          }
        });
        _calculateSlots();
      }
    } catch (e) {
      debugPrint('[AppointmentBookingPage] load master data error: $e');
    }
  }

  Future<void> _calculateSlots() async {
    if (_selectedPractitionerId == null) return;

    setState(() {
      _isLoadingSlots = true;
      _selectedSlot = null;
    });

    final slots = await widget.slotCalculator.calculateAvailableSlots(
      professionId: widget.professionId,
      practitionerId: _selectedPractitionerId!,
      targetDate: _selectedDate,
    );

    if (mounted) {
      setState(() {
        _availableSlots = slots;
        _isLoadingSlots = false;
      });
    }
  }

  Future<void> _handleBookAppointment() async {
    if (_selectedSlot == null || _selectedPractitionerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกช่วงเวลาที่ต้องการจอง')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await widget.client.from('clinic_appointments').insert({
        'profession_id': widget.professionId,
        'patient_id': widget.patientUserId,
        'staff_id': widget.selectedPractitionerId,
        'service_type_id': _selectedServiceTypeId,
        'scheduled_at': _selectedSlot!.toIso8601String(),
        'duration_minutes': 30,
        'status': 'pending',
        'booking_channel': 'mobile_app',
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      });

      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ส่งคำขอจองนัดหมายเรียบร้อยแล้ว รอเจ้าหน้าที่ยืนยัน')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('[AppointmentBookingPage] booking error: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการจอง: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('จองนัดหมายบริการ (Patient Booking)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Select Practitioner / Doctor
            Text('เลือกแพทย์ / ผู้ให้บริการ', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedPractitionerId,
              decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
              items: _practitioners.map((p) {
                return DropdownMenuItem<String>(
                  value: p['id'] as String,
                  child: Text(p['display_name'] as String? ?? 'แพทย์/ผู้ให้บริการ'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedPractitionerId = val);
                  _calculateSlots();
                }
              },
            ),
            const SizedBox(height: 16),

            // 2. Select Service Type
            Text('ประเภทบริการ', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedServiceTypeId,
              decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.medical_services)),
              items: _serviceTypes.map((s) {
                return DropdownMenuItem<String>(
                  value: s['id'] as String,
                  child: Text('${s['type_name']} (฿${s['default_price'] ?? 0})'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedServiceTypeId = val);
                }
              },
            ),
            const SizedBox(height: 16),

            // 3. Select Booking Date
            Text('วันที่ต้องการนัดหมาย', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                );
                if (picked != null) {
                  setState(() => _selectedDate = picked);
                  _calculateSlots();
                }
              },
              icon: const Icon(Icons.calendar_today),
              label: Text('${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'),
            ),
            const SizedBox(height: 16),

            // 4. Time Slot Grid
            Text('ช่วงเวลาที่ว่าง', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _isLoadingSlots
                ? const Center(child: CircularProgressIndicator())
                : _availableSlots.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('ไม่มีช่วงเวลาว่างในวันที่เลือก กรุณาเปลี่ยนวันที่หรือผู้ให้บริการ', style: TextStyle(color: Colors.red)),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availableSlots.map((slot) {
                          final isSelected = _selectedSlot == slot;
                          final timeStr = '${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}';
                          return ChoiceChip(
                            label: Text(timeStr),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedSlot = selected ? slot : null;
                              });
                            },
                          );
                        }).toList(),
                      ),
            const SizedBox(height: 16),

            // 5. Notes
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'อาการเบื้องต้น / หมายเหตุ',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.note_alt),
              ),
            ),
            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _handleBookAppointment,
                icon: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_circle),
                label: const Text('ยืนยันส่งคำขอจองนัดหมาย', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
