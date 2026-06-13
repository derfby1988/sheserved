import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../admin/models/organization_settings.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/stocktake_configuration.dart';
import '../providers/organization_settings_provider.dart';
import '../providers/phase_one_provider.dart';
import '../widgets/glass_card.dart';

class StocktakeConfigPage extends ConsumerStatefulWidget {
  final String professionId;

  const StocktakeConfigPage({
    super.key,
    required this.professionId,
  });

  @override
  ConsumerState<StocktakeConfigPage> createState() => _StocktakeConfigPageState();
}

class _StocktakeConfigPageState extends ConsumerState<StocktakeConfigPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseOneProvider.notifier).loadStocktakeConfigurations(widget.professionId);
      ref.read(organizationSettingsProvider.notifier).loadOrganization(widget.professionId);
    });
  }

  Future<void> _refresh() async {
    ref.read(phaseOneProvider.notifier).loadStocktakeConfigurations(widget.professionId);
    await Future.delayed(const Duration(milliseconds: 400));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseOneProvider);
    final orgState = ref.watch(organizationSettingsProvider);
    final branches = orgState.settings?.branches ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งค่าตรวจนับสต็อก'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...state.stocktakeConfigs.map((c) => _ConfigCard(
              config: c,
              branches: branches,
              onEdit: () => _showConfigDialog(config: c, branches: branches),
              onDelete: () => _deleteConfig(c.id),
            )),
            if (state.stocktakeConfigs.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('ยังไม่มีการตั้งค่าตรวจนับ'),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showConfigDialog(branches: branches),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _deleteConfig(String configId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: const Text('ลบการตั้งค่านี้?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('ลบ')),
        ],
      ),
    );
    if (confirmed == true) {
      final success = await ref.read(phaseOneProvider.notifier).deleteStocktakeConfiguration(configId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? 'ลบสำเร็จ' : 'ลบล้มเหลว')),
        );
      }
      if (success) await _refresh();
    }
  }

  void _showConfigDialog({
    StocktakeConfiguration? config,
    required List<OrganizationBranch> branches,
  }) {
    final isEdit = config != null;
    String name = config?.name ?? 'Stocktake';
    String freq = config?.frequencyType ?? 'MONTHLY';
    int? customDays = config?.customIntervalDays;
    DateTime? nextDate = config?.nextStocktakeDate;
    String? selectedBranchId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(isEdit ? 'แก้ไขการตั้งค่า' : 'สร้างการตั้งค่า'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: 'ชื่อรอบตรวจนับ'),
                  controller: TextEditingController(text: name),
                  onChanged: (v) => name = v,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'ความถี่'),
                  initialValue: freq,
                  items: const [
                    DropdownMenuItem(value: 'WEEKLY', child: Text('รายสัปดาห์')),
                    DropdownMenuItem(value: 'MONTHLY', child: Text('รายเดือน')),
                    DropdownMenuItem(value: 'QUARTERLY', child: Text('รายไตรมาส')),
                    DropdownMenuItem(value: 'YEARLY', child: Text('รายปี')),
                    DropdownMenuItem(value: 'CUSTOM', child: Text('กำหนดเอง')),
                  ],
                  onChanged: (v) => setState(() => freq = v ?? 'MONTHLY'),
                ),
                if (freq == 'CUSTOM') ...[
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(labelText: 'จำนวนวัน'),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: customDays?.toString() ?? ''),
                    onChanged: (v) => customDays = int.tryParse(v),
                  ),
                ],
                const SizedBox(height: 12),
                if (branches.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    decoration: const InputDecoration(labelText: 'สาขา (ถ้ามี)'),
                    initialValue: selectedBranchId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('ทุกสาขา')),
                      ...branches.map((b) => DropdownMenuItem(
                        value: b.id,
                        child: Text(b.displayName),
                      )),
                    ],
                    onChanged: (v) => selectedBranchId = v,
                  ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('วันที่ตรวจนับถัดไป'),
                  subtitle: Text(() {
                    final d = nextDate;
                    return d != null ? '${d.day}/${d.month}/${d.year}' : 'ไม่ได้เลือก';
                  }()),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: nextDate ?? DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                    );
                    if (picked != null) {
                      setState(() => nextDate = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ยกเลิก')),
            TextButton(
              onPressed: () async {
                if (name.trim().isEmpty) return;
                Navigator.of(ctx).pop();
                if (isEdit) {
                  await ref.read(phaseOneProvider.notifier).updateStocktakeConfiguration(
                    configId: config.id,
                    name: name.trim(),
                    frequencyType: freq,
                    customIntervalDays: customDays,
                    nextStocktakeDate: nextDate,
                  );
                } else {
                  await ref.read(phaseOneProvider.notifier).createStocktakeConfiguration(
                    professionId: widget.professionId,
                    branchId: selectedBranchId,
                    name: name.trim(),
                    frequencyType: freq,
                    customIntervalDays: customDays,
                    nextStocktakeDate: nextDate,
                  );
                }
                await _refresh();
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigCard extends StatelessWidget {
  final StocktakeConfiguration config;
  final List<OrganizationBranch> branches;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ConfigCard({
    required this.config,
    required this.branches,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final branchName = config.branchId != null
        ? branches.firstWhere(
            (b) => b.id == config.branchId,
            orElse: () => const OrganizationBranch(id: '', branchCode: '', branchName: 'สาขาที่เลือก'),
          ).displayName
        : 'ทุกสาขา';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.all(14),
        child: ListTile(
          title: Text(config.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ความถี่: ${_freqLabel(config.frequencyType)}'),
              Text('สาขา: $branchName'),
              if (config.nextStocktakeDate case final d)
                Text('ครั้งถัดไป: ${d.day}/${d.month}/${d.year}'),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
            ],
          ),
        ),
      ),
    );
  }
}

String _freqLabel(String freq) {
  return switch (freq) {
    'WEEKLY' => 'รายสัปดาห์',
    'MONTHLY' => 'รายเดือน',
    'QUARTERLY' => 'รายไตรมาส',
    'YEARLY' => 'รายปี',
    'CUSTOM' => 'กำหนดเอง',
    _ => freq,
  };
}
