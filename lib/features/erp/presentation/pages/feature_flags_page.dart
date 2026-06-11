import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/organization_feature_flag.dart';
import '../providers/phase_zero_provider.dart';
import '../widgets/glass_card.dart';

class FeatureFlagsPage extends ConsumerStatefulWidget {
  final String professionId;

  const FeatureFlagsPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<FeatureFlagsPage> createState() => _FeatureFlagsPageState();
}

class _FeatureFlagsPageState extends ConsumerState<FeatureFlagsPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseZeroProvider.notifier).loadFeatureFlags(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseZeroProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feature Flags'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.featureFlags.length,
                  itemBuilder: (context, index) {
                    final flag = state.featureFlags[index];
                    return _FeatureFlagCard(
                      flag: flag,
                      onToggle: () => _toggleFlag(flag),
                    );
                  },
                ),
    );
  }

  Future<void> _toggleFlag(OrganizationFeatureFlag flag) async {
    final notifier = ref.read(phaseZeroProvider.notifier);
    final success = await notifier.toggleFeatureFlag(flag);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${flag.featureName} ${flag.isEnabled ? "ปิด" : "เปิด"} ใช้งานแล้ว',
          ),
        ),
      );
    }
  }
}

class _FeatureFlagCard extends StatelessWidget {
  final OrganizationFeatureFlag flag;
  final VoidCallback onToggle;

  const _FeatureFlagCard({
    required this.flag,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = flag.isEnabled;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 16,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isEnabled ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    flag.featureName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isEnabled ? 'เปิดใช้งาน' : 'ปิดใช้งาน',
                    style: TextStyle(
                      fontSize: 12,
                      color: isEnabled ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: isEnabled,
              onChanged: (_) => onToggle(),
              activeColor: Colors.green,
            ),
          ],
        ),
      ),
    );
  }
}
