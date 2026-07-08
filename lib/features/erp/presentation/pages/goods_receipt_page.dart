import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/organization_settings_provider.dart';
import '../providers/phase_one_provider.dart';
import '../widgets/glass_card.dart';
import '../../../../shared/widgets/thai_buddhist_date_picker.dart';

class GoodsReceiptPage extends ConsumerStatefulWidget {
  final String professionId;

  const GoodsReceiptPage({
    super.key,
    required this.professionId,
  });

  @override
  ConsumerState<GoodsReceiptPage> createState() => _GoodsReceiptPageState();
}

class _GoodsReceiptPageState extends ConsumerState<GoodsReceiptPage> {
  String? _selectedProductId;
  String? _selectedCustomMedId;
  String? _selectedBranchId;
  final _lotController = TextEditingController();
  final _qtyController = TextEditingController();
  final _costController = TextEditingController();
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final notifier = ref.read(phaseOneProvider.notifier);
      notifier.loadProducts(widget.professionId);
      notifier.loadCustomMedications(widget.professionId);
      notifier.loadInventoryLots(widget.professionId);
      ref.read(organizationSettingsProvider.notifier).loadOrganization(widget.professionId);
    });
  }

  Future<void> _submit() async {
    if ((_selectedProductId == null && _selectedCustomMedId == null) ||
        _lotController.text.trim().isEmpty ||
        _qtyController.text.trim().isEmpty ||
        _costController.text.trim().isEmpty) {
      _showSnackBar('กรุณากรอกข้อมูลให้ครบถ้วน');
      return;
    }

    final qty = int.tryParse(_qtyController.text);
    final cost = double.tryParse(_costController.text);
    if (qty == null || qty <= 0 || cost == null || cost < 0) {
      _showSnackBar('จำนวนและต้นทุนต้องเป็นตัวเลขที่ถูกต้อง');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final success = await ref.read(phaseOneProvider.notifier).recordStockReceipt(
      professionId: widget.professionId,
      productId: _selectedProductId,
      customMedicationId: _selectedCustomMedId,
      branchId: _selectedBranchId,
      warehouseLocationId: null,
      lotNumber: _lotController.text.trim(),
      quantity: qty,
      unitCost: cost,
      expiryDate: _expiryDate,
    );

    if (mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(success ? 'บันทึกรับเข้าสำเร็จ' : 'บันทึกรับเข้าล้มเหลว')),
      );
    }

    if (success && mounted) {
      _resetForm();
      ref.read(phaseOneProvider.notifier).loadInventoryLots(widget.professionId);
    }
  }

  void _resetForm() {
    setState(() {
      _selectedProductId = null;
      _selectedCustomMedId = null;
      _lotController.clear();
      _qtyController.clear();
      _costController.clear();
      _expiryDate = null;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseOneProvider);
    final orgState = ref.watch(organizationSettingsProvider);
    final branches = orgState.settings?.branches ?? [];

    // Build combined item list
    final productItems = state.products.map((p) => DropdownMenuItem(
      value: 'p_${p.id}',
      child: Text(p.name),
    )).toList();
    final customItems = state.customMedications.map((m) => DropdownMenuItem(
      value: 'c_${m.id}',
      child: Text('${m.name} (Custom)'),
    )).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('รับของเข้าคลัง'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading && state.products.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('เลือกสินค้า', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                GlassCard(
                  section: GlassSection.card,
                  borderRadius: 16,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'สินค้า / ยา'),
                        initialValue: _selectedProductId != null ? 'p_$_selectedProductId' : (_selectedCustomMedId != null ? 'c_$_selectedCustomMedId' : null),
                      items: [...productItems, ...customItems],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            if (v.startsWith('p_')) {
                              _selectedProductId = v.substring(2);
                              _selectedCustomMedId = null;
                            } else {
                              _selectedCustomMedId = v.substring(2);
                              _selectedProductId = null;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (branches.isNotEmpty)
                        DropdownButtonFormField<String?>(
                          decoration: const InputDecoration(labelText: 'สาขา (ถ้ามี)'),
                          value: _selectedBranchId,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('คลังหลัก')),
                            ...branches.map((b) => DropdownMenuItem(
                              value: b.id,
                              child: Text(b.displayName),
                            )),
                          ],
                          onChanged: (v) => setState(() => _selectedBranchId = v),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _lotController,
                        decoration: const InputDecoration(
                          labelText: 'หมายเลข Lot / Batch',
                          hintText: 'เช่น LOT-202606-001',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _qtyController,
                        decoration: const InputDecoration(labelText: 'จำนวนรับเข้า'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _costController,
                        decoration: const InputDecoration(labelText: 'ต้นทุนต่อหน่วย'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 12),
                      ThaiBuddhistDatePickerField(
                        value: _expiryDate,
                        label: 'วันหมดอายุ (ถ้ามี)',
                        hint: 'เลือกวันหมดอายุ',
                        onDateSelected: (date) => setState(() => _expiryDate = date),
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
                        : const Text('บันทึกรับเข้า'),
                  ),
                ),
                const SizedBox(height: 32),
                const Text('รายการรับเข้าล่าสุด', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...state.inventoryLots.take(10).map((lot) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    section: GlassSection.card,
                    borderRadius: 12,
                    padding: const EdgeInsets.all(12),
                    child: ListTile(
                      dense: true,
                      title: Text('Lot: ${lot.lotNumber}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('รับเข้า: ${lot.quantityReceived} | คงเหลือ: ${lot.quantityRemaining}'),
                          if (lot.expiryDate != null)
                            Text('หมดอายุ: ${ThaiDateUtils.formatShortDateBE(lot.expiryDate!)}'),
                        ],
                      ),
                      trailing: Chip(
                        label: Text(lot.status, style: const TextStyle(fontSize: 11)),
                        backgroundColor: lot.status == 'active'
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                )),
              ],
            ),
    );
  }
}
