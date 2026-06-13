import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/inventory_item.dart';
import '../providers/organization_settings_provider.dart';
import '../providers/phase_one_provider.dart';
import '../widgets/glass_card.dart';

class StockTransferPage extends ConsumerStatefulWidget {
  final String professionId;

  const StockTransferPage({
    super.key,
    required this.professionId,
  });

  @override
  ConsumerState<StockTransferPage> createState() => _StockTransferPageState();
}

class _StockTransferPageState extends ConsumerState<StockTransferPage> {
  final _selectedItems = <Map<String, dynamic>>[];
  String? _currentItemId;
  final _qtyController = TextEditingController();
  final _notesController = TextEditingController();
  String? _fromBranchId;
  String? _toBranchId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseOneProvider.notifier).loadInventoryItems(widget.professionId);
      ref.read(organizationSettingsProvider.notifier).loadOrganization(widget.professionId);
    });
  }

  Future<void> _submit() async {
    if (_selectedItems.isEmpty) {
      _showSnackBar('กรุณาเลือกสินค้าอย่างน้อย 1 รายการ');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final id = await ref.read(phaseOneProvider.notifier).createInventoryTransfer(
      professionId: widget.professionId,
      fromBranchId: _fromBranchId,
      toBranchId: _toBranchId,
      items: _selectedItems,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(id != null ? 'สร้างรายการโอนย้ายสำเร็จ' : 'สร้างรายการโอนย้ายล้มเหลว')),
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
    final orgState = ref.watch(organizationSettingsProvider);
    final branches = orgState.settings?.branches ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('โอนย้ายสินค้า'),
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
                    const Text('เลือกสาขา', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (branches.isNotEmpty)
                      GlassCard(
                        section: GlassSection.card,
                        borderRadius: 12,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            DropdownButtonFormField<String?>(
                              decoration: const InputDecoration(labelText: 'จากสาขา'),
                              initialValue: _fromBranchId,
                              items: [
                                const DropdownMenuItem(value: null, child: Text('คลังหลัก')),
                                ...branches.map((b) => DropdownMenuItem(
                                  value: b.id,
                                  child: Text(b.displayName),
                                )),
                              ],
                              onChanged: (v) => setState(() => _fromBranchId = v),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String?>(
                              decoration: const InputDecoration(labelText: 'ถึงสาขา'),
                              initialValue: _toBranchId,
                              items: [
                                const DropdownMenuItem(value: null, child: Text('คลังหลัก')),
                                ...branches.map((b) => DropdownMenuItem(
                                  value: b.id,
                                  child: Text(b.displayName),
                                )),
                              ],
                              onChanged: (v) => setState(() => _toBranchId = v),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                    const Text('เลือกสินค้าและจำนวน', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                            onChanged: (v) => setState(() => _currentItemId = v),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _qtyController,
                            decoration: const InputDecoration(labelText: 'จำนวน'),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                if (_currentItemId == null) return;
                                final qty = int.tryParse(_qtyController.text);
                                if (qty == null || qty <= 0) {
                                  _showSnackBar('กรุณาระบุจำนวนที่ถูกต้อง');
                                  return;
                                }
                                setState(() {
                                  _selectedItems.add({
                                    'inventory_item_id': _currentItemId!,
                                    'quantity': qty,
                                  });
                                  _qtyController.clear();
                                });
                              },
                              child: const Text('เพิ่มรายการ'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_selectedItems.isNotEmpty) ...[
                      const Text('รายการที่เลือก', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ..._selectedItems.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final item = entry.value;
                        final id = item['inventory_item_id'] as String;
                        final qty = item['quantity'] as int;
                        final invItem = state.inventoryItems.firstWhere((i) => i.id == id);
                        final name = _resolveName(invItem, state.products, state.customMedications);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            section: GlassSection.card,
                            borderRadius: 12,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: ListTile(
                              dense: true,
                              title: Text(name),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('x$qty'),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20),
                                    onPressed: () => setState(() => _selectedItems.removeAt(idx)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 20),
                    TextField(
                      controller: _notesController,
                      decoration: const InputDecoration(labelText: 'หมายเหตุ (ถ้ามี)'),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: state.isSaving ? null : _submit,
                        child: state.isSaving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('สร้างรายการโอนย้าย'),
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
