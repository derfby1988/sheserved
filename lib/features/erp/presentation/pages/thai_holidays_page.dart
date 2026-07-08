import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/thai_buddhist_date_picker.dart';
import '../../data/models/thai_holiday.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';

class ThaiHolidaysPage extends ConsumerStatefulWidget {
  const ThaiHolidaysPage({super.key});

  @override
  ConsumerState<ThaiHolidaysPage> createState() => _ThaiHolidaysPageState();
}

class _ThaiHolidaysPageState extends ConsumerState<ThaiHolidaysPage> {
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseThreeProvider.notifier).loadThaiHolidays(year: _selectedYear);
    });
  }

  void _reload() {
    ref.read(phaseThreeProvider.notifier).loadThaiHolidays(year: _selectedYear);
  }

  Future<void> _addHoliday() async {
    final dateCtrl = TextEditingController();
    final nameThCtrl = TextEditingController();
    final nameEnCtrl = TextEditingController();
    String type = 'public';
    DateTime? pickedDate;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('เพิ่มวันหยุด'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ThaiBuddhistDatePickerField(
                  value: pickedDate,
                  label: 'วันที่หยุด',
                  hint: 'เลือกวันที่หยุด',
                  onDateSelected: (date) {
                    setState(() => pickedDate = date);
                  },
                ),
                TextField(
                  controller: nameThCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อ (ไทย)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameEnCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อ (อังกฤษ)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'ประเภท'),
                  items: const [
                    DropdownMenuItem(value: 'public', child: Text('วันหยุดราชการ')),
                    DropdownMenuItem(value: 'religious', child: Text('วันหยุดทางศาสนา')),
                    DropdownMenuItem(value: 'substitution', child: Text('วันหยุดชดเชย')),
                    DropdownMenuItem(value: 'special', child: Text('วันหยุดพิเศษ')),
                  ],
                  onChanged: (v) => setState(() => type = v ?? 'public'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () async {
                if (pickedDate == null || nameThCtrl.text.isEmpty) return;
                await ref.read(phaseThreeProvider.notifier).upsertThaiHoliday({
                  'holiday_date': pickedDate!.toIso8601String().split('T')[0],
                  'holiday_name_th': nameThCtrl.text,
                  'holiday_name_en': nameEnCtrl.text.isEmpty ? null : nameEnCtrl.text,
                  'holiday_type': type,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _reload();
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteHoliday(ThaiHoliday holiday) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ลบ "${holiday.holidayNameTh}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(phaseThreeProvider.notifier).deleteThaiHoliday(holiday.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseThreeProvider);
    final holidays = state.thaiHolidays;

    return Scaffold(
      appBar: AppBar(
        title: const Text('วันหยุดนักขัตฤกษ์'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('ปี: ', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _selectedYear,
                  items: List.generate(5, (i) => DateTime.now().year - 2 + i)
                      .map((y) => DropdownMenuItem(value: y, child: Text('${y + 543}')))
                      .toList(),
                  onChanged: (y) {
                    if (y == null) return;
                    setState(() => _selectedYear = y);
                    ref.read(phaseThreeProvider.notifier).loadThaiHolidays(year: y);
                  },
                ),
                const Spacer(),
                Text('${holidays.length} วัน',
                    style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          Expanded(
            child: state.isLoading && holidays.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : holidays.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today, size: 48, color: Colors.grey),
                            const SizedBox(height: 8),
                            const Text('ไม่มีวันหยุดในปีนี้',
                                style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _addHoliday,
                              icon: const Icon(Icons.add),
                              label: const Text('เพิ่มวันหยุด'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: holidays.length,
                        itemBuilder: (context, index) {
                          final h = holidays[index];
                          return _HolidayCard(
                            holiday: h,
                            onDelete: () => _deleteHoliday(h),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addHoliday,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _HolidayCard extends StatelessWidget {
  final ThaiHoliday holiday;
  final VoidCallback onDelete;

  const _HolidayCard({required this.holiday, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isWeekend = holiday.holidayDate.weekday == 6 || holiday.holidayDate.weekday == 7;
    final typeColor = switch (holiday.holidayType) {
      'religious' => Colors.purple,
      'substitution' => Colors.orange,
      'special' => Colors.teal,
      _ => Colors.blue,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 10,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${holiday.holidayDate.day}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: typeColor,
                    ),
                  ),
                  Text(
                    [
                      'ม.ค.',
                      'ก.พ.',
                      'มี.ค.',
                      'เม.ย.',
                      'พ.ค.',
                      'มิ.ย.',
                      'ก.ค.',
                      'ส.ค.',
                      'ก.ย.',
                      'ต.ค.',
                      'พ.ย.',
                      'ธ.ค.'
                    ][holiday.holidayDate.month - 1],
                    style: TextStyle(fontSize: 10, color: typeColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(holiday.holidayNameTh,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  if (holiday.holidayNameEn != null)
                    Text(holiday.holidayNameEn!,
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(holiday.typeLabel,
                            style: TextStyle(fontSize: 10, color: typeColor)),
                      ),
                      if (isWeekend) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('เสาร์-อาทิตย์',
                              style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
