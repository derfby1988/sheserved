import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../widgets/glass_card.dart';
import '../../../../shared/widgets/thai_buddhist_date_picker.dart';

/// Clinic POS Page (Mode C) — ขายบริการคลินิก
class ClinicPosPage extends ConsumerStatefulWidget {
  final String professionId;

  const ClinicPosPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<ClinicPosPage> createState() => _ClinicPosPageState();
}

class _ClinicPosPageState extends ConsumerState<ClinicPosPage> {
  String? _selectedServiceId;
  final _patientNameController = TextEditingController();
  DateTime? _appointmentDate;

  final List<Map<String, dynamic>> _services = [
    {'id': '1', 'name': 'ตรวจรักษาทั่วไป', 'price': 500.0},
    {'id': '2', 'name': 'ฉีดวัคซีน', 'price': 1200.0},
    {'id': '3', 'name': 'ตรวจเลือด', 'price': 800.0},
    {'id': '4', 'name': 'ตรวจสุขภาพประจำปี', 'price': 3500.0},
    {'id': '5', 'name': 'ตรวจคัดกรองมะเร็ง', 'price': 2500.0},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ขายบริการคลินิก / Clinic POS'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Patient Info
          GlassCard(
            section: GlassSection.card,
            borderRadius: 16,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ข้อมูลผู้ป่วย',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _patientNameController,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อผู้ป่วย',
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                ThaiBuddhistDatePickerField(
                  value: _appointmentDate,
                  label: 'วันนัด',
                  hint: 'เลือกวันนัด',
                  onDateSelected: (date) => setState(() => _appointmentDate = date),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Service Selection
          GlassCard(
            section: GlassSection.card,
            borderRadius: 16,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'เลือกบริการ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ..._services.map((s) => RadioListTile<String>(
                      title: Row(
                        children: [
                          Expanded(child: Text(s['name'] as String)),
                          Text(
                            '฿${(s['price'] as double).toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      value: s['id'] as String,
                      groupValue: _selectedServiceId,
                      onChanged: (v) => setState(() => _selectedServiceId = v),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Summary
          GlassCard(
            section: GlassSection.card,
            borderRadius: 16,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('ค่าบริการ', style: TextStyle(fontSize: 16)),
                    Text(
                      '฿${_selectedPrice.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedServiceId == null ? null : () => _bookService(),
                    child: const Text('จองบริการ'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double get _selectedPrice {
    if (_selectedServiceId == null) return 0;
    final service = _services.firstWhere(
      (s) => s['id'] == _selectedServiceId,
      orElse: () => {'price': 0.0},
    );
    return service['price'] as double;
  }

  Future<void> _bookService() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('จองบริการสำเร็จ')),
    );
  }
}
