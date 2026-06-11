import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_four_provider.dart';
import '../widgets/glass_card.dart';

class PrescriptionPage extends ConsumerStatefulWidget {
  final String professionId;

  const PrescriptionPage({Key? key, required this.professionId}) : super(key: key);

  @override
  ConsumerState<PrescriptionPage> createState() => _PrescriptionPageState();
}

class _PrescriptionPageState extends ConsumerState<PrescriptionPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseFourProvider.notifier).loadPrescriptions(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseFourProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ใบสั่งยา / Prescriptions'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : state.prescriptions.isEmpty
                  ? const Center(child: Text('ยังไม่มีใบสั่งยา', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.prescriptions.length,
                      itemBuilder: (context, index) {
                        final rx = state.prescriptions[index];
                        return _PrescriptionCard(rx: rx);
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddPrescriptionDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddPrescriptionDialog(BuildContext context) {
    final numberController = TextEditingController();
    final instructionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิ่มใบสั่งยา'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: numberController, decoration: const InputDecoration(labelText: 'เลขใบสั่งยา')),
              TextField(controller: instructionController, decoration: const InputDecoration(labelText: 'คำแนะนำ')),
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

class _PrescriptionCard extends StatelessWidget {
  final Map<String, dynamic> rx;

  const _PrescriptionCard({required this.rx});

  Color _statusColor(String? status) {
    switch (status) {
      case 'draft': return Colors.grey;
      case 'confirmed': return Colors.blue;
      case 'dispensed': return Colors.green;
      case 'partially_dispensed': return Colors.orange;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'draft': return 'ร่าง';
      case 'confirmed': return 'ยืนยันแล้ว';
      case 'dispensed': return 'จ่ายยาครบ';
      case 'partially_dispensed': return 'จ่ายยาบางส่วน';
      case 'cancelled': return 'ยกเลิก';
      default: return status ?? '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = rx['status'] as String? ?? 'draft';
    final total = (rx['total_amount'] as num?)?.toDouble() ?? 0.0;
    final createdAt = rx['created_at'] as String? ?? '';

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
                color: _statusColor(status).withOpacity(0.2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.medication, color: _statusColor(status)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rx['prescription_number'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (rx['instructions'] != null)
                    Text(rx['instructions'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  Text(
                    createdAt.isNotEmpty ? createdAt.substring(0, 10) : '-',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(fontSize: 11, color: _statusColor(status), fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                Text('฿${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
