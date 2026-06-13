import 'package:flutter/material.dart';
import '../../data/models/chart_of_account.dart';

/// แสดง bottom sheet เลือกบัญชีแบบจัดกลุ่มตามหมวด พร้อมจำนวน
Future<ChartOfAccount?> showAccountSelectorSheet({
  required BuildContext context,
  required List<ChartOfAccount> accounts,
  String? title,
  ChartOfAccount? selected,
}) async {
  return showModalBottomSheet<ChartOfAccount?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _AccountSelectorSheet(
      accounts: accounts,
      title: title ?? 'เลือกบัญชี',
      selected: selected,
    ),
  );
}

class _AccountSelectorSheet extends StatefulWidget {
  final List<ChartOfAccount> accounts;
  final String title;
  final ChartOfAccount? selected;

  const _AccountSelectorSheet({
    required this.accounts,
    required this.title,
    this.selected,
  });

  @override
  State<_AccountSelectorSheet> createState() => _AccountSelectorSheetState();
}

class _AccountSelectorSheetState extends State<_AccountSelectorSheet> {
  String _searchQuery = '';

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
    'revenue': Colors.lightBlue,
    'expense': Colors.orange,
  };

  List<ChartOfAccount> get _filteredAccounts {
    if (_searchQuery.isEmpty) return widget.accounts;
    final q = _searchQuery.toLowerCase();
    return widget.accounts.where((a) {
      return a.accountCode.toLowerCase().contains(q) ||
          a.accountName.toLowerCase().contains(q);
    }).toList();
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
    final groups = _groupedAccounts;
    final selectedId = widget.selected?.id;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Search
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'ค้นหารหัสหรือชื่อบัญชี',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ],
              ),
            ),
            // List
            Expanded(
              child: groups.isEmpty
                  ? const Center(
                      child: Text(
                        'ไม่พบบัญชี',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: groups.entries.length * 2 - 1,
                      itemBuilder: (context, index) {
                        final entryIndex = index ~/ 2;
                        final isDivider = index.isOdd;
                        if (isDivider) {
                          return const SizedBox(height: 8);
                        }
                        final entry = groups.entries.elementAt(entryIndex);
                        final type = entry.key;
                        final items = entry.value;
                        final color = _typeColors[type] ?? Colors.grey;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Section Header
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
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
                                    _typeLabels[type] ?? type,
                                    style: const TextStyle(
                                      fontSize: 14,
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
                                      '${items.length} บัญชี',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: color,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Items
                            ...items.map((account) {
                              final isSelected = account.id == selectedId;
                              final isCustom = account.isCustom;
                              final barColor = isCustom ? Colors.amber : color;

                              return InkWell(
                                onTap: () => Navigator.of(ctx).pop(account),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? color.withValues(alpha: 0.08)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 3,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: barColor,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${account.accountCode} — ${account.accountName}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: isCustom
                                                    ? Colors.amber.shade700
                                                    : Colors.black87,
                                              ),
                                            ),
                                            if (isCustom)
                                              Text(
                                                'Custom',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.amber.shade700,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(Icons.check_circle, color: color, size: 20),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
