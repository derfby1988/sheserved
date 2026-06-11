import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_four_provider.dart';
import '../widgets/glass_card.dart';

class OpdVisitPage extends ConsumerStatefulWidget {
  final String professionId;

  const OpdVisitPage({Key? key, required this.professionId}) : super(key: key);

  @override
  ConsumerState<OpdVisitPage> createState() => _OpdVisitPageState();
}

class _OpdVisitPageState extends ConsumerState<OpdVisitPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseFourProvider.notifier).loadOpdVisits(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseFourProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตรวจผู้ป่วยนอก / OPD'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : state.opdVisits.isEmpty
                  ? const Center(child: Text('ยังไม่มีรายการตรวจ', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.opdVisits.length,
                      itemBuilder: (context, index) {
                        final visit = state.opdVisits[index];
                        return _OpdVisitCard(visit: visit);
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddVisitDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddVisitDialog(BuildContext context) {
    final complaintController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิ่มรายการตรวจ OPD'),
        content: TextField(
          controller: complaintController,
          decoration: const InputDecoration(labelText: 'อาการหลัก'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () async {
              final notifier = ref.read(phaseFourProvider.notifier);
              await notifier.createOpdVisit({
                'profession_id': widget.professionId,
                'patient_id': '341cbf8b-3020-4a6c-81de-9d9cb0b7b1f4', // TODO: select patient
                'chief_complaint': complaintController.text,
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}

class _OpdVisitCard extends StatelessWidget {
  final dynamic visit;

  const _OpdVisitCard({required this.visit});

  @override
  Widget build(BuildContext context) {
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
                color: visit.statusColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Center(
                child: Text(
                  '${visit.queueNumber ?? '-'}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: visit.statusColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(visit.visitNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (visit.chiefComplaint != null)
                    Text(visit.chiefComplaint!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    visit.visitDate.toString().substring(0, 10),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: visit.statusColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                visit.statusLabel,
                style: TextStyle(fontSize: 12, color: visit.statusColor, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
