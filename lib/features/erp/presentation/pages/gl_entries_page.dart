import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';

class GlEntriesPage extends ConsumerStatefulWidget {
  final String professionId;

  const GlEntriesPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<GlEntriesPage> createState() => _GlEntriesPageState();
}

class _GlEntriesPageState extends ConsumerState<GlEntriesPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseThreeProvider.notifier).loadGlEntries(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseThreeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('บัญชีแยกประเภท / GL Entries'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : state.glEntries.isEmpty
                  ? const Center(
                      child: Text(
                        'ยังไม่มีรายการบัญชี',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.glEntries.length,
                      itemBuilder: (context, index) {
                        final entry = state.glEntries[index];
                        return _GlEntryCard(entry: entry);
                      },
                    ),
    );
  }
}

class _GlEntryCard extends StatelessWidget {
  final dynamic entry;

  const _GlEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isDebit = entry.isDebit;
    final amount = entry.amount;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 10,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: isDebit ? Colors.green : Colors.red,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.description ?? 'รายการบัญชี',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${entry.entryDate.toString().substring(0, 10)} | Ref: ${entry.referenceNo ?? '-'}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isDebit ? '+฿${amount.toStringAsFixed(2)}' : '-฿${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDebit ? Colors.green : Colors.red,
                  ),
                ),
                Text(
                  isDebit ? 'Debit' : 'Credit',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
