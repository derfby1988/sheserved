import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/inventory_item.dart';
import '../providers/phase_one_provider.dart';
import '../widgets/glass_card.dart';

class StockAdjustmentPage extends ConsumerStatefulWidget {
  final String professionId;

  const StockAdjustmentPage({
    super.key,
    required this.professionId,
  });

  @override
  ConsumerState<StockAdjustmentPage> createState() => _StockAdjustmentPageState();
}

class _StockAdjustmentPageState extends ConsumerState<StockAdjustmentPage> {
  String? _selectedItemId;
  String _adjustmentType = 'count';
  final _qtyController = TextEditingController();
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseOneProvider.notifier).loadInventoryItems(widget.professionId);
    });
  }

  Future<void> _submit() async {
    if (_selectedItemId == null) {
      _showSnackBar('กรุณาเลือกสินค้า');
      return;
    }
    final qty = int.tryParse(_qtyController.text);
    if (qty == null) {
      _showSnackBar('กรุณาระบุจำนวนที่ถูกต้อง');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final id = await ref.read(phaseOneProvider.notifier).createStockAdjustment(
      professionId: widget.professionId,
      inventoryItemId: _selectedItemId!,
      adjustmentType: _adjustmentType,
      quantityAfter: qty,
      reason: _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
    );
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(id != null ? 'ปรับสต็อกสำเร็จ' : 'ปรับสต็อกล้มเหลว')),
      );
    }
    if (id != null && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseOneProvider);

    final selectedItem = _selectedItemId != null
        ? state.inventoryItems.firstWhere(
            (i) => i.id == _selectedItemId,
            orElse: () => state.inventoryItems.first,
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ปรับสต็อก'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.inventoryItems.isEmpty
              ? const Center(child: Text('ไม่มีสินค้าในสต็อก'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('เลือกสินค้าและระบุจำนวนใหม่', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    GlassCard(
                      section: GlassSection.card,
                      borderRadius: 16,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            decoration: const InputDecoration(labelText: 'สินค้า'),
                            items: state.inventoryItems.map((i) {
                              final name = _resolveName(i, state.products, state.customMedications);
                              return DropdownMenuItem(
                                value: i.id,
                                child: Text('$name (คงเหลือ ${i.quantity})'),
                              );
                            }).toList(),
                            onChanged: (v) => setState(() => _selectedItemId = v),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            decoration: const InputDecoration(labelText: 'ประเภทการปรับ'),
                            initialValue: _adjustmentType,
                            items: const [
                              DropdownMenuItem(value: 'count', child: Text('ตรวจนับ')),
                              DropdownMenuItem(value: 'damage', child: Text('เสียหาย')),
                              DropdownMenuItem(value: 'expired', child: Text('หมดอายุ')),
                              DropdownMenuItem(value: 'found', child: Text('พบเพิ่ม')),
                              DropdownMenuItem(value: 'lost', child: Text('สูญหาย')),
                              DropdownMenuItem(value: 'other', child: Text('อื่นๆ')),
                            ],
                            onChanged: (v) => setState(() => _adjustmentType = v ?? 'count'),
                          ),
                          const SizedBox(height: 12),
                          if (selectedItem != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'จำนวนปัจจุบัน: ${selectedItem.quantity} หน่วย',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _qtyController,
                            decoration: const InputDecoration(
                              labelText: 'จำนวนหลังปรับ',
                              hintText: 'ระบุจำนวนที่ต้องการให้เหลือ',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _reasonController,
                            decoration: const InputDecoration(
                              labelText: 'เหตุผล (ถ้ามี)',
                              hintText: 'เช่น สินค้าเสียหายจากการขนส่ง',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: state.isSaving ? null : _submit,
                        child: state.isSaving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('บันทึกการปรับสต็อก'),
                      ),
                    ),
                  ],
                ),
    );
  }
}

String _resolveName(
  InventoryItem item,
  List<dynamic> products,
  List<dynamic> medications,
) {
  if (item.productId != null) {
    for (final p in products) {
      if (p.id == item.productId) return p.name as String;
    }
  }
  if (item.customMedicationId != null) {
    for (final m in medications) {
      if (m.id == item.customMedicationId) return m.name as String;
    }
  }
  return 'สินค้า #${item.productId ?? item.customMedicationId ?? item.id.substring(0, 8)}';
}
