import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/chart_of_account.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';

class ChartOfAccountsPage extends ConsumerStatefulWidget {
  final String professionId;

  const ChartOfAccountsPage({super.key, required this.professionId});

  @override
  ConsumerState<ChartOfAccountsPage> createState() => _ChartOfAccountsPageState();
}

class _ChartOfAccountsPageState extends ConsumerState<ChartOfAccountsPage> {
  String? _filterType;
  String _searchQuery = '';
  bool _filterCustomOnly = false;

  static const _typeOrder = ['asset', 'liability', 'equity', 'revenue', 'expense'];

  static const Map<String, String> _typeLabels = {
    'asset': 'สินทรัพย์',
    'liability': 'หนี้สิน',
    'equity': 'ทุน',
    'revenue': 'รายได้',
    'expense': 'ค่าใช้จ่าย',
  };

  static const Map<String, Color> _typeColors = {
    'asset': Colors.green,
    'liability': Colors.red,
    'equity': Colors.blue,
    'revenue': Colors.teal,
    'expense': Colors.orange,
  };

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseThreeProvider.notifier).loadChartOfAccounts(widget.professionId);
    });
  }

  List<ChartOfAccount> get _filteredAccounts {
    final state = ref.read(phaseThreeProvider);
    var accounts = state.chartOfAccounts;

    if (_filterType != null) {
      accounts = accounts.where((a) => a.accountType == _filterType).toList();
    }

    if (_filterCustomOnly) {
      accounts = accounts.where((a) => a.isCustom).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      accounts = accounts.where((a) {
        return a.accountCode.toLowerCase().contains(q) ||
            a.accountName.toLowerCase().contains(q);
      }).toList();
    }

    return accounts;
  }

  Map<String, List<ChartOfAccount>> get _groupedAccounts {
    final accounts = _filteredAccounts;
    final groups = <String, List<ChartOfAccount>>{};

    for (final type in _typeOrder) {
      final items = accounts.where((a) => a.accountType == type).toList();
      if (items.isNotEmpty) groups[type] = items;
    }

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseThreeProvider);
    final groups = _groupedAccounts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ผังบัญชี / Chart of Accounts'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: _buildSearchBar(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: _buildTypeFilter(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _buildCustomFilter(),
                  ),
                ),
                if (groups.isEmpty)
                  const SliverFillRemaining(
                    child: Center(
                      child: Text(
                        'ไม่พบบัญชี',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  for (final entry in groups.entries) ...[
                    SliverToBoxAdapter(
                      child: _SectionHeader(
                        type: entry.key,
                        label: _typeLabels[entry.key] ?? entry.key,
                        color: _typeColors[entry.key] ?? Colors.grey,
                        count: entry.value.length,
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final account = entry.value[index];
                          return _AccountCard(
                            account: account,
                            color: _typeColors[account.accountType] ?? Colors.grey,
                            onEdit: () => _showAccountDialog(account: account),
                            onReset: account.isCustom && account.standardAccountId != null
                                ? () => _handleReset(account)
                                : null,
                            onDelete: account.isCustom && account.standardAccountId == null
                                ? () => _handleDelete(account)
                                : null,
                          );
                        },
                        childCount: entry.value.length,
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 12),
                    ),
                  ],
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAccountDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSearchBar() {
    return GlassCard(
      section: GlassSection.card,
      borderRadius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: const InputDecoration(
          hintText: 'ค้นหารหัสหรือชื่อบัญชี...',
          border: InputBorder.none,
          icon: Icon(Icons.search, size: 20),
        ),
      ),
    );
  }

  Widget _buildTypeFilter() {
    final types = [
      _TypeFilter(null, 'ทั้งหมด'),
      _TypeFilter('asset', 'สินทรัพย์'),
      _TypeFilter('liability', 'หนี้สิน'),
      _TypeFilter('equity', 'ทุน'),
      _TypeFilter('revenue', 'รายได้'),
      _TypeFilter('expense', 'ค่าใช้จ่าย'),
    ];

    return GlassCard(
      section: GlassSection.card,
      borderRadius: 12,
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: types.map((t) {
          final isSelected = _filterType == t.value;
          return ChoiceChip(
            label: Text(t.label),
            selected: isSelected,
            onSelected: (_) => setState(() => _filterType = t.value),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCustomFilter() {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilterChip(
        label: const Text('เฉพาะที่สร้าง/แก้ไขเอง'),
        selected: _filterCustomOnly,
        onSelected: (v) => setState(() => _filterCustomOnly = v),
        avatar: _filterCustomOnly
            ? const Icon(Icons.person, size: 18)
            : const Icon(Icons.person_outline, size: 18),
      ),
    );
  }

  Future<void> _showAccountDialog({ChartOfAccount? account}) async {
    final isEdit = account != null;
    final codeController = TextEditingController(text: account?.accountCode ?? '');
    final nameController = TextEditingController(text: account?.accountName ?? '');
    String selectedType = account?.accountType ?? 'asset';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'แก้ไขบัญชี' : 'เพิ่มบัญชีใหม่'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              decoration: const InputDecoration(labelText: 'รหัสบัญชี'),
            ),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'ชื่อบัญชี'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'ประเภท'),
              initialValue: selectedType,
              items: const [
                DropdownMenuItem(value: 'asset', child: Text('สินทรัพย์')),
                DropdownMenuItem(value: 'liability', child: Text('หนี้สิน')),
                DropdownMenuItem(value: 'equity', child: Text('ทุน')),
                DropdownMenuItem(value: 'revenue', child: Text('รายได้')),
                DropdownMenuItem(value: 'expense', child: Text('ค่าใช้จ่าย')),
              ],
              onChanged: (v) => selectedType = v ?? 'asset',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              if (codeController.text.trim().isEmpty ||
                  nameController.text.trim().isEmpty) {
                return;
              }
              Navigator.of(ctx).pop({
                'account_code': codeController.text.trim(),
                'account_name': nameController.text.trim(),
                'account_type': selectedType,
                'profession_id': widget.professionId,
              });
            },
            child: Text(isEdit ? 'บันทึก' : 'สร้าง'),
          ),
        ],
      ),
    );

    if (result == null) return;

    final notifier = ref.read(phaseThreeProvider.notifier);
    if (isEdit) {
      await notifier.updateChartOfAccount(account.id, result);
    } else {
      await notifier.createChartOfAccount(result);
    }
  }

  Future<void> _handleReset(ChartOfAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('รีเซตผังบัญชี'),
        content: Text(
          'คืนค่า "${account.accountName}" กลับไปตามผังบัญชีมาตรฐาน?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('รีเซต'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final notifier = ref.read(phaseThreeProvider.notifier);
    await notifier.resetChartOfAccount(account.id, widget.professionId);
  }

  Future<void> _handleDelete(ChartOfAccount account) async {
    final notifier = ref.read(phaseThreeProvider.notifier);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );

    final deps = await notifier.checkDeleteChartOfAccount(account.id);
    if (!mounted) return;
    Navigator.of(context).pop();

    final canDelete = deps?['can_delete'] == true;
    final linkedProducts = deps?['linked_products'] as List<dynamic>? ?? [];
    final glCount = (deps?['gl_entries_count'] as num?)?.toInt() ?? 0;
    final journalCount = (deps?['journal_lines_count'] as num?)?.toInt() ?? 0;
    final parentCount = (deps?['parent_accounts_count'] as num?)?.toInt() ?? 0;

    if (!canDelete) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange),
              SizedBox(width: 8),
              Text('ไม่สามารถลบได้'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('บัญชีนี้ถูกใช้งานอยู่ในระบบ กรุณาตรวจสอบรายการด้านล่าง:'),
                const SizedBox(height: 12),
                if (glCount > 0)
                  _buildBlockItem(Icons.receipt_long, 'รายการบัญชีแยกประเภท (GL)', '$glCount รายการ'),
                if (journalCount > 0)
                  _buildBlockItem(Icons.menu_book, 'รายการสมุดรายวัน', '$journalCount รายการ'),
                if (parentCount > 0)
                  _buildBlockItem(Icons.account_tree, 'บัญชีย่อย', '$parentCount บัญชี'),
                if (linkedProducts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('สินค้า/บริการที่เชื่อมโยง:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ...linkedProducts.map((p) {
                    final typeLabel = switch (p['mapping_type']?.toString()) {
                      'revenue' => 'รายได้',
                      'cogs' => 'ต้นทุน',
                      'inventory' => 'สินค้าคงเหลือ',
                      'adjustment' => 'ปรับปรุง',
                      _ => p['mapping_type']?.toString() ?? '',
                    };
                    return _buildBlockItem(
                      Icons.inventory_2,
                      'ID: ${p['product_id']}',
                      '${p['product_type']} ($typeLabel)',
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ปิด'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ลบบัญชี "${account.accountName}" (${account.accountCode})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await notifier.deleteChartOfAccount(account.id);
    }
  }

  Widget _buildBlockItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String type;
  final String label;
  final Color color;
  final int count;

  const _SectionHeader({
    required this.type,
    required this.label,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count บัญชี',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          Container(
            height: 1,
            color: Colors.grey.withValues(alpha: 0.2),
            width: 40,
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final ChartOfAccount account;
  final Color color;
  final VoidCallback onEdit;
  final VoidCallback? onReset;
  final VoidCallback? onDelete;

  const _AccountCard({
    required this.account,
    required this.color,
    required this.onEdit,
    this.onReset,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isCustom = account.isCustom;
    final barColor = isCustom ? Colors.amber : color;
    final nameColor = isCustom ? Colors.amber.shade700 : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${account.accountCode} — ${account.accountName}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: nameColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        account.typeLabel,
                        style: TextStyle(fontSize: 12, color: color),
                      ),
                      if (isCustom) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Custom',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.amber.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (onReset != null)
              IconButton(
                icon: const Icon(Icons.restore, size: 20),
                tooltip: 'รีเซตเป็นผังบัญชีมาตรฐาน',
                color: Colors.grey,
                onPressed: onReset,
              ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'ลบบัญชี',
                color: Colors.red.shade300,
                onPressed: onDelete,
              ),
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeFilter {
  final String? value;
  final String label;
  _TypeFilter(this.value, this.label);
}
