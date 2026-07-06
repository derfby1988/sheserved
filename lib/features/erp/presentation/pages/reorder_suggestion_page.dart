import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/phase_one_provider.dart';
import '../widgets/glass_card.dart';

class ReorderSuggestionPage extends ConsumerStatefulWidget {
  final String professionId;
  final String? branchId;
  final String? userId;

  const ReorderSuggestionPage({
    super.key,
    required this.professionId,
    this.branchId,
    this.userId,
  });

  @override
  ConsumerState<ReorderSuggestionPage> createState() =>
      _ReorderSuggestionPageState();
}

class _ReorderSuggestionPageState extends ConsumerState<ReorderSuggestionPage> {
  String _statusFilter = 'pending';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSuggestions();
    });
  }

  void _loadSuggestions() {
    ref
        .read(phaseOneProvider.notifier)
        .loadReorderSuggestions(widget.professionId, status: _statusFilter == 'all' ? null : _statusFilter);
  }

  Future<void> _checkReorderPoints() async {
    final result = await ref
        .read(phaseOneProvider.notifier)
        .checkReorderPoints(widget.professionId, branchId: widget.branchId);

    if (!mounted) return;

    final newCount = result?['new_suggestions'] ?? 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newCount > 0
            ? 'พบ $newCount รายการที่ควรสั่งซื้อใหม่'
            : 'ไม่มีรายการที่ต้องสั่งซื้อใหม่ในขณะนี้'),
        backgroundColor: newCount > 0 ? Colors.green : Colors.grey,
      ),
    );
  }

  Future<void> _confirmSuggestion(Map<String, dynamic> suggestion) async {
    final userId = widget.userId ?? '';
    final success = await ref
        .read(phaseOneProvider.notifier)
        .confirmReorderSuggestion(suggestion['id'] as String, userId);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'ยืนยันคำแนะนำสำเร็จ' : 'ยืนยันล้มเหลว'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
    if (success) _loadSuggestions();
  }

  Future<void> _rejectSuggestion(Map<String, dynamic> suggestion) async {
    final userId = widget.userId ?? '';
    final success = await ref
        .read(phaseOneProvider.notifier)
        .rejectReorderSuggestion(suggestion['id'] as String, userId);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'ปฏิเสธคำแนะนำสำเร็จ' : 'ปฏิเสธล้มเหลว'),
        backgroundColor: success ? Colors.orange : Colors.red,
      ),
    );
    if (success) _loadSuggestions();
  }

  Future<void> _convertToPr(Map<String, dynamic> suggestion) async {
    final userId = widget.userId ?? '';
    final result = await ref
        .read(phaseOneProvider.notifier)
        .convertReorderToPr(suggestion['id'] as String, userId);

    if (!mounted) return;
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('สร้าง PR ${result['pr_number']} สำเร็จ'),
          backgroundColor: Colors.green,
        ),
      );
      _loadSuggestions();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('แปลงเป็น PR ล้มเหลว'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'rejected':
        return Colors.red;
      case 'converted_to_pr':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'รอยืนยัน';
      case 'confirmed':
        return 'ยืนยันแล้ว';
      case 'rejected':
        return 'ปฏิเสธ';
      case 'converted_to_pr':
        return 'แปลงเป็น PR แล้ว';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseOneProvider);
    final suggestions = state.reorderSuggestions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('คำแนะนำการสั่งซื้อ / Reorder Suggestions'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (state.isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'ตรวจสอบจุดสั่งซื้อ',
              onPressed: _checkReorderPoints,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _filterChip('pending', 'รอยืนยัน'),
                const SizedBox(width: 8),
                _filterChip('confirmed', 'ยืนยันแล้ว'),
                const SizedBox(width: 8),
                _filterChip('converted_to_pr', 'แปลงแล้ว'),
                const SizedBox(width: 8),
                _filterChip('all', 'ทั้งหมด'),
              ],
            ),
          ),
        ),
      ),
      body: state.isLoading && suggestions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : suggestions.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () async => _loadSuggestions(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: suggestions.length,
                    itemBuilder: (context, index) {
                      final s = suggestions[index];
                      return _buildSuggestionCard(s);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.isSaving ? null : _checkReorderPoints,
        icon: const Icon(Icons.radar),
        label: const Text('ตรวจสต็อกต่ำ'),
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    return FilterChip(
      label: Text(label),
      selected: _statusFilter == value,
      onSelected: (selected) {
        if (selected) {
          setState(() => _statusFilter = value);
          _loadSuggestions();
        }
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'ไม่มีคำแนะนำการสั่งซื้อ',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'กดปุ่ม "ตรวจสต็อกต่ำ" เพื่อตรวจสอบสินค้าที่ควรสั่งซื้อใหม่',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard(Map<String, dynamic> s) {
    final status = s['status'] as String? ?? 'pending';
    final productData = s['products'] as Map<String, dynamic>?;
    final productName = productData?['name'] as String? ?? 'ไม่ทราบสินค้า';
    final productSku = productData?['sku'] as String? ?? '';
    final unit = productData?['unit_of_measure'] as String? ?? '';
    final currentQty = s['current_quantity'] as int? ?? 0;
    final reorderPoint = s['reorder_point'] as int? ?? 0;
    final suggestedQty = s['suggested_quantity'] as int? ?? 0;
    final supplierData = s['suppliers'] as Map<String, dynamic>?;
    final supplierName = supplierData?['supplier_name'] as String?;
    final createdAt = s['created_at'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        section: GlassSection.card,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      productName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _statusColor(status).withOpacity(0.3)),
                    ),
                    child: Text(
                      _statusLabel(status),
                      style: TextStyle(
                        color: _statusColor(status),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (productSku.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'SKU: $productSku',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildInfoChip('สต็อกปัจจุบัน', '$currentQty $unit', Colors.red),
                  const SizedBox(width: 8),
                  _buildInfoChip('จุดสั่งซื้อ', '$reorderPoint $unit', Colors.orange),
                  const SizedBox(width: 8),
                  _buildInfoChip('แนะนำสั่ง', '$suggestedQty $unit', Colors.green),
                ],
              ),
              if (supplierName != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.local_shipping, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'ผู้จัดจำหน่าย: $supplierName',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
              if (createdAt.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'สร้างเมื่อ: ${createdAt.substring(0, 10)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[500],
                      ),
                ),
              ],
              if (status == 'pending') ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _rejectSuggestion(s),
                      child: const Text('ปฏิเสธ', style: TextStyle(color: Colors.red)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _confirmSuggestion(s),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('ยืนยัน'),
                    ),
                  ],
                ),
              ],
              if (status == 'confirmed') ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _convertToPr(s),
                      icon: const Icon(Icons.note_add, size: 18),
                      label: const Text('แปลงเป็น PR'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
