import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_four_provider.dart';
import '../widgets/glass_card.dart';

class EmrListPage extends ConsumerStatefulWidget {
  final String professionId;

  const EmrListPage({Key? key, required this.professionId}) : super(key: key);

  @override
  ConsumerState<EmrListPage> createState() => _EmrListPageState();
}

class _EmrListPageState extends ConsumerState<EmrListPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseFourProvider.notifier).loadEmrRecords(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseFourProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติผู้ป่วย / EMR'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : state.emrRecords.isEmpty
                  ? const Center(child: Text('ยังไม่มีประวัติผู้ป่วย', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.emrRecords.length,
                      itemBuilder: (context, index) {
                        final record = state.emrRecords[index];
                        return _EmrCard(record: record);
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEmrDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddEmrDialog(BuildContext context) {
    final hnController = TextEditingController();
    final complaintController = TextEditingController();
    final diagnosisController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิ่มประวัติผู้ป่วย'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: hnController, decoration: const InputDecoration(labelText: 'เลข HN')),
              TextField(controller: complaintController, decoration: const InputDecoration(labelText: 'อาการหลัก')),
              TextField(controller: diagnosisController, decoration: const InputDecoration(labelText: 'การวินิจฉัย')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () async {
              final user = ref.read(phaseFourProvider.notifier);
              // Note: would need actual patient_id from patient selection
              Navigator.pop(context);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}

class _EmrCard extends StatelessWidget {
  final dynamic record;

  const _EmrCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    record.recordNumber,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  record.recordType,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (record.chiefComplaint != null)
              Text('อาการ: ${record.chiefComplaint}', maxLines: 2, overflow: TextOverflow.ellipsis),
            if (record.icd10Code != null)
              Text('ICD-10: ${record.icd10Code} ${record.icd10Name ?? ''}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              record.createdAt.toString().substring(0, 10),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
