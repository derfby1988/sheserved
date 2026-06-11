import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_four_provider.dart';
import '../widgets/glass_card.dart';

class PatientCohortPage extends ConsumerStatefulWidget {
  final String professionId;

  const PatientCohortPage({Key? key, required this.professionId}) : super(key: key);

  @override
  ConsumerState<PatientCohortPage> createState() => _PatientCohortPageState();
}

class _PatientCohortPageState extends ConsumerState<PatientCohortPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseFourProvider.notifier).loadCohorts(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseFourProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('กลุ่มผู้ป่วย / Cohorts'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : state.cohorts.isEmpty
                  ? const Center(child: Text('ยังไม่มีกลุ่มผู้ป่วย', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.cohorts.length,
                      itemBuilder: (context, index) {
                        final cohort = state.cohorts[index];
                        return _CohortCard(cohort: cohort);
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddCohortDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddCohortDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิ่มกลุ่มผู้ป่วย'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'ชื่อกลุ่ม')),
              TextField(controller: descController, decoration: const InputDecoration(labelText: 'รายละเอียด')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}

class _CohortCard extends StatelessWidget {
  final Map<String, dynamic> cohort;

  const _CohortCard({required this.cohort});

  Color _typeColor(String? type) {
    switch (type) {
      case 'age_group': return Colors.blue;
      case 'condition': return Colors.green;
      case 'visit_frequency': return Colors.orange;
      default: return Colors.purple;
    }
  }

  String _typeLabel(String? type) {
    switch (type) {
      case 'age_group': return 'กลุ่มอายุ';
      case 'condition': return 'ตามโรค';
      case 'visit_frequency': return 'ความถี่';
      default: return 'กำหนดเอง';
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = cohort['cohort_name'] as String? ?? '-';
    final type = cohort['cohort_type'] as String? ?? 'custom';
    final desc = cohort['description'] as String? ?? '';
    final memberCount = cohort['member_count'] as int? ?? 0;
    final isAutoSync = cohort['is_auto_sync'] as bool? ?? false;
    final createdAt = cohort['created_at'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _typeColor(type).withOpacity(0.2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Center(
                child: Text(
                  '$memberCount',
                  style: TextStyle(fontWeight: FontWeight.bold, color: _typeColor(type)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _typeColor(type).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _typeLabel(type),
                          style: TextStyle(fontSize: 10, color: _typeColor(type), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (desc.isNotEmpty)
                    Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (isAutoSync)
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sync, size: 12, color: Colors.grey),
                            SizedBox(width: 2),
                            Text('Auto-sync', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      const Spacer(),
                      Text(
                        createdAt.isNotEmpty ? createdAt.substring(0, 10) : '-',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
