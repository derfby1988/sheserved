import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/loyalty_rule.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_five_provider.dart';
import '../widgets/glass_card.dart';

class LoyaltyRulesPage extends ConsumerStatefulWidget {
  final String professionId;

  const LoyaltyRulesPage({super.key, required this.professionId});

  @override
  ConsumerState<LoyaltyRulesPage> createState() => _LoyaltyRulesPageState();
}

class _LoyaltyRulesPageState extends ConsumerState<LoyaltyRulesPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseFiveProvider.notifier).loadLoyaltyRules(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseFiveProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('กฎแต้มสะสม / Loyalty Rules'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : state.loyaltyRules.isEmpty
                  ? const Center(child: Text('ยังไม่มีกฎแต้ม', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.loyaltyRules.length,
                      itemBuilder: (context, index) {
                        final rule = state.loyaltyRules[index];
                        return _LoyaltyRuleCard(rule: rule);
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddRuleDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddRuleDialog(BuildContext context) {
    final nameController = TextEditingController();
    final pointsController = TextEditingController(text: '0.01');
    final multiplierController = TextEditingController(text: '1.0');
    final minPurchaseController = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิ่มกฎแต้ม'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'ชื่อกฎ')),
              TextField(controller: pointsController, decoration: const InputDecoration(labelText: 'แต้มต่อบาท'), keyboardType: TextInputType.number),
              TextField(controller: multiplierController, decoration: const InputDecoration(labelText: 'ตัวคูณ'), keyboardType: TextInputType.number),
              TextField(controller: minPurchaseController, decoration: const InputDecoration(labelText: 'ยอดขั้นต่ำ'), keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () async {
              final notifier = ref.read(phaseFiveProvider.notifier);
              await notifier.createLoyaltyRule({
                'profession_id': widget.professionId,
                'rule_name': nameController.text,
                'points_per_baht': double.tryParse(pointsController.text) ?? 0.01,
                'bonus_multiplier': double.tryParse(multiplierController.text) ?? 1.0,
                'min_purchase': double.tryParse(minPurchaseController.text) ?? 0,
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}

class _LoyaltyRuleCard extends StatelessWidget {
  final LoyaltyRule rule;

  const _LoyaltyRuleCard({required this.rule});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(rule.ruleName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                if (rule.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Active', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${rule.pointsPerBaht} แต้ม/บาท × ${rule.bonusMultiplier} = ${(rule.pointsPerBaht * rule.bonusMultiplier).toStringAsFixed(4)} แต้ม/บาท'),
            if (rule.minPurchase > 0)
              Text('ยอดขั้นต่ำ: ฿${rule.minPurchase.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12)),
            Text('ใช้กับ: ${rule.appliesTo}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
