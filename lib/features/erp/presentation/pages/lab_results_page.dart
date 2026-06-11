import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_four_provider.dart';
import '../widgets/glass_card.dart';

class LabResultsPage extends ConsumerStatefulWidget {
  final String professionId;

  const LabResultsPage({Key? key, required this.professionId}) : super(key: key);

  @override
  ConsumerState<LabResultsPage> createState() => _LabResultsPageState();
}

class _LabResultsPageState extends ConsumerState<LabResultsPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseFourProvider.notifier).loadLabResults(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseFourProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ผลแล็บ / Lab Results'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : state.labResults.isEmpty
                  ? const Center(child: Text('ยังไม่มีผลแล็บ', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.labResults.length,
                      itemBuilder: (context, index) {
                        final result = state.labResults[index];
                        return _LabResultCard(result: result);
                      },
                    ),
    );
  }
}

class _LabResultCard extends StatelessWidget {
  final Map<String, dynamic> result;

  const _LabResultCard({required this.result});

  Color _statusColor(String? status) {
    switch (status) {
      case 'pending': return Colors.grey;
      case 'processing': return Colors.blue;
      case 'completed': return Colors.green;
      case 'verified': return Colors.purple;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'pending': return 'รอผล';
      case 'processing': return 'กำลังดำเนินการ';
      case 'completed': return 'เสร็จสิ้น';
      case 'verified': return 'ยืนยันแล้ว';
      case 'cancelled': return 'ยกเลิก';
      default: return status ?? '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = result['status'] as String? ?? 'pending';
    final isCritical = result['is_critical'] as bool? ?? false;
    final isAbnormal = result['is_abnormal'] as bool? ?? false;
    final labTests = result['lab_tests'] as Map<String, dynamic>?;
    final testName = (labTests?['test_name'] as String?) ?? '-';
    final resultValue = result['result_value'] as String? ?? '-';
    final unit = result['unit'] as String? ?? '';
    final numericValue = result['numeric_value'] as num?;
    final createdAt = result['created_at'] as String? ?? '';

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
                    color: _statusColor(status).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(fontSize: 11, color: _statusColor(status), fontWeight: FontWeight.w600),
                  ),
                ),
                if (isCritical) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'CRITICAL',
                      style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                if (isAbnormal && !isCritical) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Abnormal',
                      style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  createdAt.isNotEmpty ? createdAt.substring(0, 10) : '-',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(testName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  numericValue != null ? '${numericValue.toStringAsFixed(2)} $unit' : '$resultValue $unit',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isCritical ? Colors.red : (isAbnormal ? Colors.orange : null),
                  ),
                ),
              ],
            ),
            if (result['reference_range'] != null)
              Text('Ref: ${result['reference_range']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (result['notes'] != null)
              Text('${result['notes']}', style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
