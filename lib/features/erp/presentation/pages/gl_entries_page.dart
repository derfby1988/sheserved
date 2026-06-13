import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/gl_entry.dart';
import '../../data/models/chart_of_account.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';

class GlEntriesPage extends ConsumerStatefulWidget {
  final String professionId;

  const GlEntriesPage({super.key, required this.professionId});

  @override
  ConsumerState<GlEntriesPage> createState() => _GlEntriesPageState();
}

class _GlEntriesPageState extends ConsumerState<GlEntriesPage> {
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _selectedAccountId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final notifier = ref.read(phaseThreeProvider.notifier);
      notifier.loadGlEntries(widget.professionId);
      notifier.loadChartOfAccounts(widget.professionId);
    });
  }

  List<GlEntry> get _filteredEntries {
    final state = ref.read(phaseThreeProvider);
    return state.glEntries.where((e) {
      if (_fromDate != null && e.entryDate.isBefore(_fromDate!)) return false;
      if (_toDate != null && e.entryDate.isAfter(_toDate!)) return false;
      if (_selectedAccountId != null && e.accountId != _selectedAccountId) return false;
      return true;
    }).toList();
  }

  String _accountName(String accountId, List<ChartOfAccount> accounts) {
    final account = accounts.firstWhere(
      (a) => a.id == accountId,
      orElse: () => ChartOfAccount(
        id: '', professionId: '', accountCode: '', accountName: 'ไม่ทราบ', accountType: '',
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
      ),
    );
    return '${account.accountCode} ${account.accountName}';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseThreeProvider);
    final entries = _filteredEntries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('บัญชีแยกประเภท / GL Entries'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildFilters(state),
                const SizedBox(height: 16),
                if (entries.isEmpty)
                  const Center(
                    child: Text(
                      'ไม่มีรายการบัญชี',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...entries.map((entry) => _GlEntryCard(
                        entry: entry,
                        accountName: _accountName(entry.accountId, state.chartOfAccounts),
                      )),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(state.chartOfAccounts),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildFilters(PhaseThreeState state) {
    return GlassCard(
      section: GlassSection.card,
      borderRadius: 12,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _DateFilterChip(
                  label: 'จาก',
                  date: _fromDate,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _fromDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setState(() => _fromDate = picked);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DateFilterChip(
                  label: 'ถึง',
                  date: _toDate,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _toDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setState(() => _toDate = picked);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (state.chartOfAccounts.isNotEmpty)
            DropdownButtonFormField<String?>(
              decoration: const InputDecoration(labelText: 'บัญชี'),
              initialValue: _selectedAccountId,
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: null, child: Text('ทั้งหมด')),
                ...state.chartOfAccounts.map((a) => DropdownMenuItem(
                  value: a.id,
                  child: Text('${a.accountCode} ${a.accountName}'),
                )),
              ],
              onChanged: (v) => setState(() => _selectedAccountId = v),
            ),
          if (_fromDate != null || _toDate != null || _selectedAccountId != null)
            TextButton(
              onPressed: () => setState(() {
                _fromDate = null;
                _toDate = null;
                _selectedAccountId = null;
              }),
              child: const Text('ล้างตัวกรอง'),
            ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(List<ChartOfAccount> accounts) async {
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาสร้างผังบัญชีก่อน')),
      );
      return;
    }

    String selectedAccountId = accounts.first.id;
    DateTime entryDate = DateTime.now();
    bool isDebit = true;
    final amountController = TextEditingController();
    final descController = TextEditingController();
    final refController = TextEditingController();

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('บันทึกรายการบัญชี'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'บัญชี'),
                  initialValue: selectedAccountId,
                  isExpanded: true,
                  items: accounts.map((a) => DropdownMenuItem(
                    value: a.id,
                    child: Text('${a.accountCode} ${a.accountName}'),
                  )).toList(),
                  onChanged: (v) => setState(() => selectedAccountId = v!),
                ),
                ListTile(
                  title: const Text('วันที่'),
                  subtitle: Text('${entryDate.day}/${entryDate.month}/${entryDate.year}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: entryDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setState(() => entryDate = picked);
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Debit'),
                        selected: isDebit,
                        onSelected: (_) => setState(() => isDebit = true),
                      ),
                    ),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Credit'),
                        selected: !isDebit,
                        onSelected: (_) => setState(() => isDebit = false),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: 'จำนวนเงิน'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'รายละเอียด'),
                ),
                TextField(
                  controller: refController,
                  decoration: const InputDecoration(labelText: 'เลขที่อ้างอิง'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text.trim()) ?? 0;
                if (amount <= 0) return;
                Navigator.of(ctx).pop({
                  'profession_id': widget.professionId,
                  'account_id': selectedAccountId,
                  'entry_date': entryDate.toIso8601String(),
                  'debit_amount': isDebit ? amount : 0,
                  'credit_amount': isDebit ? 0 : amount,
                  'description': descController.text.trim().isEmpty ? null : descController.text.trim(),
                  'reference_no': refController.text.trim().isEmpty ? null : refController.text.trim(),
                });
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    await ref.read(phaseThreeProvider.notifier).createGlEntry(result);
  }
}

class _DateFilterChip extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _DateFilterChip({required this.label, this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: ', style: const TextStyle(fontSize: 12)),
            Text(
              date != null ? '${date!.day}/${date!.month}/${date!.year}' : 'ทั้งหมด',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

class _GlEntryCard extends StatelessWidget {
  final GlEntry entry;
  final String accountName;

  const _GlEntryCard({required this.entry, required this.accountName});

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
              height: 48,
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
                    accountName,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    '${entry.entryDate.day}/${entry.entryDate.month}/${entry.entryDate.year} | Ref: ${entry.referenceNo ?? '-'}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
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
