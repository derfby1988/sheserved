import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/accounts_receivable.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';

class AccountsReceivablePage extends ConsumerStatefulWidget {
  final String professionId;

  const AccountsReceivablePage({super.key, required this.professionId});

  @override
  ConsumerState<AccountsReceivablePage> createState() => _AccountsReceivablePageState();
}

class _AccountsReceivablePageState extends ConsumerState<AccountsReceivablePage> {
  String? _filterStatus;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseThreeProvider.notifier).loadAccountsReceivable(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseThreeProvider);
    final items = _filterStatus == null
        ? state.accountsReceivable
        : state.accountsReceivable.where((ar) => ar.status == _filterStatus).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ลูกหนี้การค้า / AR'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStatusFilter(),
                const SizedBox(height: 16),
                if (items.isEmpty)
                  const Center(
                    child: Text(
                      'ไม่มีรายการลูกหนี้',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...items.map((ar) => _ArCard(
                        ar: ar,
                        onUpdateStatus: (status) => _showUpdateDialog(ar, status),
                      )),
              ],
            ),
    );
  }

  Widget _buildStatusFilter() {
    final statuses = [
      _StatusFilter(null, 'ทั้งหมด'),
      _StatusFilter('open', 'ค้างชำระ'),
      _StatusFilter('partial', 'ชำระบางส่วน'),
      _StatusFilter('paid', 'ชำระแล้ว'),
      _StatusFilter('overdue', 'เลยกำหนด'),
    ];

    return GlassCard(
      section: GlassSection.card,
      borderRadius: 12,
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: statuses.map((s) {
          final isSelected = _filterStatus == s.value;
          return ChoiceChip(
            label: Text(s.label),
            selected: isSelected,
            onSelected: (_) => setState(() => _filterStatus = s.value),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _showUpdateDialog(AccountsReceivable ar, String newStatus) async {
    final paidController = TextEditingController(
      text: ar.paidAmount > 0 ? ar.paidAmount.toString() : '',
    );

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('อัปเดตสถานะ: ${ar.statusLabel} → ${_statusLabel(newStatus)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ยอดรวม: ${ar.amount.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            TextField(
              controller: paidController,
              decoration: const InputDecoration(labelText: 'จำนวนที่ชำระแล้ว'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final paid = double.tryParse(paidController.text) ?? ar.paidAmount;
    await ref.read(phaseThreeProvider.notifier).updateArStatus(
      ar.id,
      newStatus,
      paidAmount: paid,
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'open': return 'ค้างชำระ';
      case 'partial': return 'ชำระบางส่วน';
      case 'paid': return 'ชำระแล้ว';
      case 'overdue': return 'เลยกำหนด';
      default: return status;
    }
  }
}

class _ArCard extends StatelessWidget {
  final AccountsReceivable ar;
  final Function(String) onUpdateStatus;

  const _ArCard({required this.ar, required this.onUpdateStatus});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(ar.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ar.invoiceNumber ?? 'Invoice #${ar.id.substring(0, 8)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    ar.statusLabel,
                    style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ยอด: ${ar.amount.toStringAsFixed(2)}'),
                Text('คงเหลือ: ${ar.balance.toStringAsFixed(2)}'),
              ],
            ),
            if (ar.dueDate != null)
              Text(
                'กำหนดชำระ: ${ar.dueDate!.day}/${ar.dueDate!.month}/${ar.dueDate!.year}',
                style: TextStyle(
                  fontSize: 12,
                  color: ar.isOverdue ? Colors.red : Colors.grey,
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (ar.status != 'paid' && ar.status != 'written_off')
                  TextButton(
                    onPressed: () => onUpdateStatus('paid'),
                    child: const Text('ชำระแล้ว'),
                  ),
                if (ar.status == 'open')
                  TextButton(
                    onPressed: () => onUpdateStatus('partial'),
                    child: const Text('บางส่วน'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open': return Colors.orange;
      case 'partial': return Colors.blue;
      case 'paid': return Colors.green;
      case 'overdue': return Colors.red;
      case 'written_off': return Colors.grey;
      default: return Colors.grey;
    }
  }
}

class _StatusFilter {
  final String? value;
  final String label;
  _StatusFilter(this.value, this.label);
}
