import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/refund_request.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_five_provider.dart';
import '../widgets/glass_card.dart';

class RefundListPage extends ConsumerStatefulWidget {
  final String professionId;

  const RefundListPage({super.key, required this.professionId});

  @override
  ConsumerState<RefundListPage> createState() => _RefundListPageState();
}

class _RefundListPageState extends ConsumerState<RefundListPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseFiveProvider.notifier).loadRefundRequests(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseFiveProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('คืนเงิน / Refunds'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : state.refundRequests.isEmpty
                  ? const Center(child: Text('ยังไม่มีรายการคืนเงิน', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.refundRequests.length,
                      itemBuilder: (context, index) {
                        final refund = state.refundRequests[index];
                        return _RefundCard(refund: refund);
                      },
                    ),
    );
  }
}

class _RefundCard extends StatelessWidget {
  final RefundRequest refund;

  const _RefundCard({required this.refund});

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      case 'completed': return Colors.blue;
      case 'cancelled': return Colors.grey;
      default: return Colors.grey;
    }
  }

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
                color: _statusColor(refund.status).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.undo, color: _statusColor(refund.status)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(refund.orderNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(refund.reason, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    refund.requestedAt?.toString().substring(0, 10) ?? '-',
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
                    color: _statusColor(refund.status).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    refund.statusLabel,
                    style: TextStyle(fontSize: 11, color: _statusColor(refund.status), fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                Text('฿${refund.amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
