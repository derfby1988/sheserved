import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/vendor_contract.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_two_provider.dart';
import '../widgets/glass_card.dart';

class VendorContractsPage extends ConsumerStatefulWidget {
  final String professionId;

  const VendorContractsPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<VendorContractsPage> createState() => _VendorContractsPageState();
}

class _VendorContractsPageState extends ConsumerState<VendorContractsPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseTwoProvider.notifier).loadVendorContracts(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseTwoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('สัญญาผู้ให้บริการ / Vendor Contracts'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : state.vendorContracts?.isEmpty ?? true
                  ? const Center(
                      child: Text(
                        'ยังไม่มีสัญญาผู้ให้บริการ',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.vendorContracts!.length,
                      itemBuilder: (context, index) {
                        final contract = state.vendorContracts![index];
                        return _VendorContractCard(contract: contract);
                      },
                    ),
    );
  }
}

class _VendorContractCard extends StatelessWidget {
  final VendorContract contract;

  const _VendorContractCard({required this.contract});

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
                  child: Text(
                    contract.vendorName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: contract.isActive
                        ? Colors.green.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    contract.isActive ? 'ใช้งาน' : 'หยุดใช้งาน',
                    style: TextStyle(
                      color: contract.isActive ? Colors.green : Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('ค่าธรรมเนียม: ${contract.feePercent.toStringAsFixed(2)}%'),
            if (contract.payoutCycleDays != null)
              Text('รอบจ่าย: ${contract.payoutCycleDays} วัน'),
          ],
        ),
      ),
    );
  }
}
