import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/dashboard_theme.dart';
import '../../data/models/procurement_settings.dart';
import '../providers/phase_one_provider.dart';
import '../widgets/glass_card.dart';

class ProcurementSettingsPage extends ConsumerStatefulWidget {
  final String professionId;

  const ProcurementSettingsPage({super.key, required this.professionId});

  @override
  ConsumerState<ProcurementSettingsPage> createState() =>
      _ProcurementSettingsPageState();
}

class _ProcurementSettingsPageState
    extends ConsumerState<ProcurementSettingsPage> {
  late final TextEditingController _thresholdController;
  late final TextEditingController _multiplierController;
  String _paymentTerms = 'net_30';
  bool _enablePriceHistory = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _thresholdController = TextEditingController();
    _multiplierController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(phaseOneProvider.notifier)
          .loadProcurementSettings(widget.professionId);
    });
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    _multiplierController.dispose();
    super.dispose();
  }

  void _syncFromState(ProcurementSettings? settings) {
    if (settings == null || _initialized) return;
    _thresholdController.text = settings.approvalAmountThreshold.toStringAsFixed(2);
    _multiplierController.text =
        settings.autoReorderThresholdMultiplier.toStringAsFixed(2);
    _paymentTerms = settings.defaultPaymentTerms;
    _enablePriceHistory = settings.enablePriceHistoryTracking;
    _initialized = true;
  }

  Future<void> _save() async {
    final threshold = double.tryParse(_thresholdController.text) ?? 10000;
    final multiplier = double.tryParse(_multiplierController.text) ?? 1.0;

    final success = await ref
        .read(phaseOneProvider.notifier)
        .updateProcurementSettings(widget.professionId, {
      'approval_amount_threshold': threshold,
      'auto_reorder_threshold_multiplier': multiplier,
      'default_payment_terms': _paymentTerms,
      'enable_price_history_tracking': _enablePriceHistory,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'บันทึกการตั้งค่าสำเร็จ' : 'บันทึกการตั้งค่าล้มเหลว'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseOneProvider);
    _syncFromState(state.procurementSettings);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งค่าระบบจัดซื้อ'),
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
              icon: const Icon(Icons.save),
              onPressed: _save,
              tooltip: 'บันทึก',
            ),
        ],
      ),
      body: state.isLoading && state.procurementSettings == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GlassCard(
                    section: GlassSection.card,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'วงเงินอนุมัติ (Approval Threshold)',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'PR ที่มียอดรวมต่ำกว่าวงเงินนี้จะอนุมัติอัตโนมัติ',
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _thresholdController,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'วงเงินอนุมัติ (บาท)',
                              border: OutlineInputBorder(),
                              prefixText: '฿ ',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassCard(
                    section: GlassSection.card,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ตัวคูณ Reorder Point',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'คูณ reorder_point เพื่อสร้างคำแนะนำการสั่งซื้อล่วงหน้า (เช่น 1.5 = สั่งเมื่อสต็อก ≤ 150% ของ reorder_point)',
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _multiplierController,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'ตัวคูณ (เช่น 1.0, 1.5, 2.0)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassCard(
                    section: GlassSection.card,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'เงื่อนไขการชำระเงิน (Payment Terms)',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _paymentTerms,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'net_7', child: Text('เครดิต 7 วัน')),
                              DropdownMenuItem(value: 'net_15', child: Text('เครดิต 15 วัน')),
                              DropdownMenuItem(value: 'net_30', child: Text('เครดิต 30 วัน')),
                              DropdownMenuItem(value: 'net_60', child: Text('เครดิต 60 วัน')),
                              DropdownMenuItem(value: 'cod', child: Text('เงินสด (COD)')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _paymentTerms = v);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassCard(
                    section: GlassSection.card,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Price History Tracking (โหมด B)',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'เปิดเพื่อบันทึกประวัติราคาต่อ Supplier และสินค้า',
                          ),
                          SwitchListTile(
                            title: const Text('เปิดใช้งาน Price History'),
                            value: _enablePriceHistory,
                            onChanged: (v) =>
                                setState(() => _enablePriceHistory = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: state.isSaving ? null : _save,
                      icon: const Icon(Icons.save),
                      label: const Text('บันทึกการตั้งค่า'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
