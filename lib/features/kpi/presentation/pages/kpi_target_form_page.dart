import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/kpi_models.dart';
import '../providers/kpi_provider.dart';

class KpiTargetFormPage extends ConsumerStatefulWidget {
  final KpiTarget? editTarget;

  const KpiTargetFormPage({super.key, this.editTarget});

  @override
  ConsumerState<KpiTargetFormPage> createState() => _KpiTargetFormPageState();
}

class _KpiTargetFormPageState extends ConsumerState<KpiTargetFormPage> {
  final _formKey = GlobalKey<FormState>();

  late String _targetType;
  late String _periodType;
  final _targetAmountController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String? _branchId;
  String? _employeeId;

  final List<String> _targetTypes = const [
    'revenue',
    'net_profit',
    'consultations',
    'appointments',
  ];
  final List<String> _periodTypes = const [
    'daily',
    'weekly',
    'monthly',
    'quarterly',
    'yearly',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.editTarget != null) {
      final t = widget.editTarget!;
      _targetType = t.targetType;
      _periodType = t.periodType;
      _targetAmountController.text = t.targetAmount.toString();
      _startDate = t.startDate;
      _endDate = t.endDate;
      _branchId = t.branchId;
      _employeeId = t.employeeId;
    } else {
      _targetType = 'revenue';
      _periodType = 'monthly';
      _startDate = DateTime.now();
      _endDate = DateTime.now().add(const Duration(days: 30));
    }
  }

  @override
  void dispose() {
    _targetAmountController.dispose();
    super.dispose();
  }

  String _targetTypeLabel(String type) {
    switch (type) {
      case 'revenue':
        return 'ยอดขาย';
      case 'net_profit':
        return 'กำไรสุทธิ';
      case 'consultations':
        return 'การปรึกษา';
      case 'appointments':
        return 'นัดหมาย';
      default:
        return type;
    }
  }

  String _periodTypeLabel(String period) {
    switch (period) {
      case 'daily':
        return 'รายวัน';
      case 'weekly':
        return 'รายสัปดาห์';
      case 'monthly':
        return 'รายเดือน';
      case 'quarterly':
        return 'รายไตรมาส';
      case 'yearly':
        return 'รายปี';
      default:
        return period;
    }
  }

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? DateTime.now()) : (_endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = _startDate!.add(const Duration(days: 1));
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกวันที่')),
      );
      return;
    }

    final professionId = ref.read(kpiProvider).selectedProfessionId;
    if (professionId == null || professionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบ Profession ID — กรุณาเลือก Profession ก่อน')),
      );
      return;
    }

    final target = KpiTarget(
      id: widget.editTarget?.id ?? '',
      professionId: professionId,
      branchId: _branchId,
      employeeId: _employeeId,
      targetType: _targetType,
      targetAmount: double.parse(_targetAmountController.text),
      periodType: _periodType,
      startDate: _startDate!,
      endDate: _endDate!,
    );

    final notifier = ref.read(kpiProvider.notifier);
    bool success;
    if (widget.editTarget != null) {
      success = await notifier.updateTarget(
        widget.editTarget!.id,
        target.toMap(),
      );
    } else {
      success = await notifier.createTarget(target);
    }

    if (success && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.editTarget != null
                ? 'อัปเดตเป้าหมายสำเร็จ'
                : 'สร้างเป้าหมายสำเร็จ',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kpiProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.editTarget != null ? 'แก้ไขเป้าหมาย' : 'สร้างเป้าหมายใหม่',
        ),
        elevation: 0,
      ),
      body: state.isLoading && state.kpiTargets.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Target Type
                    _buildSectionTitle('ประเภทเป้าหมาย'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _targetTypes.map((type) {
                        final isSelected = type == _targetType;
                        return ChoiceChip(
                          label: Text(_targetTypeLabel(type)),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _targetType = type),
                          selectedColor: Theme.of(context).colorScheme.primary,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey[700],
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Period Type
                    _buildSectionTitle('ช่วงเวลา'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _periodTypes.map((period) {
                        final isSelected = period == _periodType;
                        return ChoiceChip(
                          label: Text(_periodTypeLabel(period)),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _periodType = period),
                          selectedColor: Theme.of(context).colorScheme.secondary,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey[700],
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Target Amount
                    _buildSectionTitle('จำนวนเป้าหมาย'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _targetAmountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'เช่น 500000',
                        prefixIcon: const Icon(Icons.attach_money),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'กรุณาระบุจำนวนเป้าหมาย';
                        }
                        final numVal = double.tryParse(value);
                        if (numVal == null || numVal <= 0) {
                          return 'จำนวนต้องมากกว่า 0';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Date Range
                    _buildSectionTitle('ช่วงวันที่'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDatePicker(
                            label: 'วันเริ่มต้น',
                            date: _startDate,
                            onTap: () => _pickDate(context, true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.arrow_forward, color: Colors.grey),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDatePicker(
                            label: 'วันสิ้นสุด',
                            date: _endDate,
                            onTap: () => _pickDate(context, false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Submit Button
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: state.isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: state.isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                widget.editTarget != null
                                    ? 'บันทึกการแก้ไข'
                                    : 'สร้างเป้าหมาย',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Existing Targets List (for reference)
                    if (state.kpiTargets.isNotEmpty) ...[
                      _buildSectionTitle('เป้าหมายปัจจุบัน'),
                      const SizedBox(height: 8),
                      ...state.kpiTargets.take(5).map((target) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getTypeColor(target.targetType),
                              child: Text(
                                target.targetType[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(
                              '${_targetTypeLabel(target.targetType)} — ${target.targetAmount.toStringAsFixed(0)}',
                            ),
                            subtitle: Text(
                              '${_periodTypeLabel(target.periodType)} | ${target.startDate.toString().split(' ').first} → ${target.endDate.toString().split(' ').first}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () {
                                    // TODO: Navigate to edit with this target
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                  onPressed: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('ยืนยันการลบ'),
                                        content: const Text('ต้องการลบเป้าหมายนี้ใช่หรือไม่?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text('ยกเลิก'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('ลบ'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed == true) {
                                      await ref
                                          .read(kpiProvider.notifier)
                                          .deleteTarget(target.id);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
    );
  }

  Widget _buildDatePicker({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[50],
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    date != null
                        ? date.toString().split(' ').first
                        : 'เลือกวันที่',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: date != null ? Colors.grey[800] : Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'revenue':
        return const Color(0xFF4CAF50);
      case 'net_profit':
        return const Color(0xFF2196F3);
      case 'consultations':
        return const Color(0xFFFFA726);
      case 'appointments':
        return const Color(0xFF9C27B0);
      default:
        return Colors.grey;
    }
  }
}
