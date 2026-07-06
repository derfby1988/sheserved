import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/settlement_ledger.dart';
import '../../data/models/payout_batch.dart';
import '../../data/models/payout_batch_line.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_two_provider.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';

class SettlementPayoutPage extends ConsumerStatefulWidget {
  final String professionId;

  const SettlementPayoutPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<SettlementPayoutPage> createState() =>
      _SettlementPayoutPageState();
}

class _SettlementPayoutPageState extends ConsumerState<SettlementPayoutPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _summary;
  bool _isLoadingSummary = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(() {
      _loadData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    ref
        .read(phaseThreeProvider.notifier)
        .loadSettlementLedgers(widget.professionId);
    ref
        .read(phaseTwoProvider.notifier)
        .loadPayoutBatches(widget.professionId);
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _isLoadingSummary = true);
    try {
      final repo = ref.read(phaseTwoRepositoryProvider);
      final s = await repo.getSettlementSummary(widget.professionId);
      if (mounted) setState(() => _summary = s);
    } catch (_) {}
    if (mounted) setState(() => _isLoadingSummary = false);
  }

  @override
  Widget build(BuildContext context) {
    final phase3State = ref.watch(phaseThreeProvider);
    final phase2State = ref.watch(phaseTwoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('การเงิน / Settlement & Payout'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'สรุปยอด (Ledger)'),
            Tab(text: 'รอบจ่าย (Payout)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _SettlementLedgerTab(
            professionId: widget.professionId,
            ledgers: phase3State.settlementLedgers,
            summary: _summary,
            isLoadingSummary: _isLoadingSummary,
            isLoading: phase3State.isLoading,
            errorMessage: phase3State.errorMessage,
            onRefresh: _loadData,
          ),
          _PayoutBatchTab(
            professionId: widget.professionId,
            batches: phase2State.payoutBatches,
            isLoading: phase2State.isLoading,
            errorMessage: phase2State.errorMessage,
            onCreateBatch: () => _createPayoutBatch(),
            onRefresh: _loadData,
          ),
        ],
      ),
    );
  }

  Future<void> _createPayoutBatch() async {
    final repo = ref.read(phaseTwoRepositoryProvider);
    final id = await repo.createPayoutBatch(widget.professionId);
    if (id != null) {
      _loadData();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('สร้างรอบจ่ายไม่สำเร็จ')),
        );
      }
    }
  }
}

// ========================
// Settlement Ledger Tab
// ========================
class _SettlementLedgerTab extends StatelessWidget {
  final String professionId;
  final List<SettlementLedger> ledgers;
  final Map<String, dynamic>? summary;
  final bool isLoadingSummary;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRefresh;

  const _SettlementLedgerTab({
    required this.professionId,
    required this.ledgers,
    required this.summary,
    required this.isLoadingSummary,
    required this.isLoading,
    required this.errorMessage,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && ledgers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null && ledgers.isEmpty) {
      return Center(child: Text('Error: $errorMessage'));
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (summary != null) _SummaryCard(summary: summary!),
          if (summary == null && isLoadingSummary)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 12),
          if (ledgers.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text(
                  'ยังไม่มีสรุปยอด',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ...ledgers.map((l) => _LedgerCard(ledger: l)),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic> summary;

  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final totalGross =
        (summary['total_gross'] as num?)?.toDouble() ?? 0;
    final totalFee =
        (summary['total_fee'] as num?)?.toDouble() ?? 0;
    final totalNet =
        (summary['total_net'] as num?)?.toDouble() ?? 0;
    final totalPlatformFee =
        (summary['total_platform_fee'] as num?)?.toDouble() ?? 0;
    final totalMerchantPayout =
        (summary['total_merchant_payout'] as num?)?.toDouble() ?? 0;
    final pendingCount =
        (summary['pending_count'] as num?)?.toInt() ?? 0;

    return GlassCard(
      section: GlassSection.card,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ภาพรวมการเงิน',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _SummaryRow(label: 'ยอดรวม (Gross)', value: totalGross),
          _SummaryRow(label: 'ค่าธรรมเนียมรวม', value: totalFee),
          _SummaryRow(label: 'ค่าธรรมเนียมแพลตฟอร์ม', value: totalPlatformFee),
          _SummaryRow(
              label: 'ยอดจ่าย Merchant', value: totalMerchantPayout),
          const Divider(height: 20),
          _SummaryRow(
              label: 'ยอดสุทธิ (Net)',
              value: totalNet,
              isBold: true),
          if (pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'รอจ่าย: $pendingCount รายการ',
                      style: const TextStyle(
                          color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final bool isBold;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? Colors.black87 : Colors.black54,
            ),
          ),
          Text(
            '฿${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: isBold ? Colors.green : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerCard extends StatelessWidget {
  final SettlementLedger ledger;

  const _LedgerCard({required this.ledger});

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'processing':
        return Colors.blue;
      case 'failed':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'open':
        return 'เปิด';
      case 'processing':
        return 'กำลังดำเนินการ';
      case 'paid':
        return 'จ่ายแล้ว';
      case 'failed':
        return 'ล้มเหลว';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    'รอบที่ ${ledger.periodStart.day}/${ledger.periodStart.month}/${ledger.periodStart.year} - ${ledger.periodEnd.day}/${ledger.periodEnd.month}/${ledger.periodEnd.year}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(ledger.status).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusLabel(ledger.status),
                    style: TextStyle(
                      color: _statusColor(ledger.status),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _LedgerRow(label: 'ยอดรวม', value: ledger.totalGross),
            _LedgerRow(label: 'ค่าธรรมเนียม', value: ledger.totalFee),
            _LedgerRow(
                label: 'ยอดสุทธิ', value: ledger.totalNet, isBold: true),
            if (ledger.paidAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'จ่ายเมื่อ: ${ledger.paidAt!.day}/${ledger.paidAt!.month}/${ledger.paidAt!.year}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            if (ledger.payoutReference != null)
              Text(
                'อ้างอิง: ${ledger.payoutReference}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  final String label;
  final double value;
  final bool isBold;

  const _LedgerRow({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.black54,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '฿${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: isBold ? Colors.green : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

// ========================
// Payout Batch Tab
// ========================
class _PayoutBatchTab extends ConsumerStatefulWidget {
  final String professionId;
  final List<PayoutBatch> batches;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onCreateBatch;
  final VoidCallback onRefresh;

  const _PayoutBatchTab({
    required this.professionId,
    required this.batches,
    required this.isLoading,
    required this.errorMessage,
    required this.onCreateBatch,
    required this.onRefresh,
  });

  @override
  ConsumerState<_PayoutBatchTab> createState() => _PayoutBatchTabState();
}

class _PayoutBatchTabState extends ConsumerState<_PayoutBatchTab> {
  String? _expandedBatchId;

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading && widget.batches.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.errorMessage != null && widget.batches.isEmpty) {
      return Center(child: Text('Error: ${widget.errorMessage}'));
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async => widget.onRefresh(),
          child: widget.batches.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 200),
                    Center(
                      child: Text(
                        'ยังไม่มีรอบจ่าย',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: widget.batches.length,
                  itemBuilder: (context, index) {
                    final batch = widget.batches[index];
                    return _PayoutBatchCard(
                      batch: batch,
                      isExpanded: _expandedBatchId == batch.id,
                      onTap: () {
                        setState(() {
                          _expandedBatchId =
                              _expandedBatchId == batch.id ? null : batch.id;
                        });
                        if (_expandedBatchId == batch.id) {
                          ref
                              .read(phaseTwoProvider.notifier)
                              .loadPayoutBatchLines(batch.id);
                        }
                      },
                    );
                  },
                ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: widget.onCreateBatch,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

class _PayoutBatchCard extends ConsumerWidget {
  final PayoutBatch batch;
  final bool isExpanded;
  final VoidCallback onTap;

  const _PayoutBatchCard({
    required this.batch,
    required this.isExpanded,
    required this.onTap,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'processing':
        return Colors.blue;
      case 'failed':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'รอดำเนินการ';
      case 'processing':
        return 'กำลังดำเนินการ';
      case 'completed':
        return 'เสร็จสิ้น';
      case 'failed':
        return 'ล้มเหลว';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase2State = ref.watch(phaseTwoProvider);
    final lines = phase2State.payoutBatchLines[batch.id] ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.all(14),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'รอบจ่าย ${batch.batchDate.day}/${batch.batchDate.month}/${batch.batchDate.year}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(batch.status).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusLabel(batch.status),
                      style: TextStyle(
                        color: _statusColor(batch.status),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('ยอดรวม',
                      style:
                          TextStyle(color: Colors.black54, fontSize: 13)),
                  Text(
                    '฿${batch.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.green),
                  ),
                ],
              ),
              if (isExpanded) ...[
                const Divider(height: 20),
                if (lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
                  ...lines.map((l) => _PayoutLineItem(line: l)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PayoutLineItem extends StatelessWidget {
  final PayoutBatchLine line;

  const _PayoutLineItem({required this.line});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              line.merchantAccountId ?? line.allocationId,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '฿${line.amount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: line.status == 'completed'
                  ? Colors.green.withOpacity(0.2)
                  : line.status == 'failed'
                      ? Colors.red.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              line.status == 'completed'
                  ? 'สำเร็จ'
                  : line.status == 'failed'
                      ? 'ล้มเหลว'
                      : 'รอ',
              style: TextStyle(
                fontSize: 10,
                color: line.status == 'completed'
                    ? Colors.green
                    : line.status == 'failed'
                        ? Colors.red
                        : Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
