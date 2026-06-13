import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/accounts_payable.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';

class AccountsPayablePage extends ConsumerStatefulWidget {
  final String professionId;

  const AccountsPayablePage({super.key, required this.professionId});

  @override
  ConsumerState<AccountsPayablePage> createState() => _AccountsPayablePageState();
}

class _AccountsPayablePageState extends ConsumerState<AccountsPayablePage> {
  String? _filterStatus;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseThreeProvider.notifier).loadAccountsPayable(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseThreeProvider);
    final items = _filterStatus == null
        ? state.accountsPayable
        : state.accountsPayable.where((ap) => ap.status == _filterStatus).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('เจ้าหนี้การค้า / AP'),
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
                      'ไม่มีรายการเจ้าหนี้',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...items.map((ap) => _ApCard(
                        ap: ap,
                        onUpdateStatus: (status) => _showUpdateDialog(ap, status),
                      )),
              ],
            ),
    );
  }

  Widget _buildStatusFilter() {
    final statuses = [
      _StatusFilter(null, 'ทั้งหมด'),
      _StatusFilter('open', 'ค้างจ่าย'),
      _StatusFilter('partial', 'จ่ายบางส่วน'),
      _StatusFilter('paid', 'จ่ายแล้ว'),
      _StatusFilter('overdue', 'เลยกำหนด'),
      _StatusFilter('written_off', 'ตัดหนี้สูญ'),
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

  Future<void> _showUpdateDialog(AccountsPayable ap, String newStatus) async {
    final paidController = TextEditingController(
      text: ap.paidAmount > 0 ? ap.paidAmount.toString() : '',
    );

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('อัปเดตสถานะ: ${ap.statusLabel} → ${_statusLabel(newStatus)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ยอดรวม: ${ap.amount.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            TextField(
              controller: paidController,
              decoration: const InputDecoration(labelText: 'จำนวนที่จ่ายแล้ว'),
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

    final paid = double.tryParse(paidController.text) ?? ap.paidAmount;
    await ref.read(phaseThreeProvider.notifier).updateApStatus(
      ap.id,
      newStatus,
      paidAmount: paid,
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'open': return 'ค้างจ่าย';
      case 'partial': return 'จ่ายบางส่วน';
      case 'paid': return 'จ่ายแล้ว';
      case 'overdue': return 'เลยกำหนด';
      case 'written_off': return 'ตัดหนี้สูญ';
      default: return status;
    }
  }
}

class _ApCard extends StatelessWidget {
  final AccountsPayable ap;
  final Function(String) onUpdateStatus;

  const _ApCard({required this.ap, required this.onUpdateStatus});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(ap.status);

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
                    ap.invoiceNumber ?? 'Invoice #${ap.id.substring(0, 8)}',
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
                    ap.statusLabel,
                    style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ยอด: ${ap.amount.toStringAsFixed(2)}'),
                Text('คงเหลือ: ${ap.balance.toStringAsFixed(2)}'),
              ],
            ),
            if (ap.dueDate != null)
              Text(
                'กำหนดจ่าย: ${ap.dueDate!.day}/${ap.dueDate!.month}/${ap.dueDate!.year}',
                style: TextStyle(
                  fontSize: 12,
                  color: ap.isOverdue ? Colors.red : Colors.grey,
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (ap.status != 'paid' && ap.status != 'written_off')
                  TextButton(
                    onPressed: () => onUpdateStatus('paid'),
                    child: const Text('จ่ายแล้ว'),
                  ),
                if (ap.status == 'open')
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
