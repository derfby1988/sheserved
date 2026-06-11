import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/supplier.dart';
import '../providers/phase_one_provider.dart';
import '../widgets/glass_card.dart';

class SupplierListPage extends ConsumerStatefulWidget {
  final String professionId;

  const SupplierListPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<SupplierListPage> createState() => _SupplierListPageState();
}

class _SupplierListPageState extends ConsumerState<SupplierListPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseOneProvider.notifier).loadSuppliers(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseOneProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ผู้จำหน่าย / Suppliers'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.suppliers.length,
                  itemBuilder: (context, index) {
                    final supplier = state.suppliers[index];
                    return _SupplierCard(supplier: supplier);
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSupplierDialog(),
        icon: const Icon(Icons.add_business),
        label: const Text('เพิ่มผู้จำหน่าย'),
      ),
    );
  }

  void _showCreateSupplierDialog() {
    final nameController = TextEditingController();
    final contactController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิ่มผู้จำหน่าย'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'ชื่อบริษัท')),
            TextField(controller: contactController, decoration: const InputDecoration(labelText: 'ผู้ติดต่อ')),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'โทรศัพท์')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () async {
              final notifier = ref.read(phaseOneProvider.notifier);
              final success = await notifier.createSupplier({
                'profession_id': widget.professionId,
                'supplier_name': nameController.text.trim(),
                'contact_name': contactController.text.trim(),
                'phone': phoneController.text.trim(),
              });
              if (success && mounted) {
                Navigator.pop(context);
                notifier.loadSuppliers(widget.professionId);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('เพิ่มผู้จำหน่ายสำเร็จ')),
                );
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  final Supplier supplier;

  const _SupplierCard({required this.supplier});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 16,
        padding: const EdgeInsets.all(14),
        child: ListTile(
          title: Text(supplier.supplierName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (supplier.contactName != null) Text('ผู้ติดต่อ: ${supplier.contactName}'),
              if (supplier.phone != null) Text('โทร: ${supplier.phone}'),
              Text('เครดิต: ${supplier.paymentTerms} | นำเข้า: ${supplier.leadTimeDays} วัน'),
            ],
          ),
          trailing: supplier.isActive
              ? const Icon(Icons.check_circle, color: Colors.green)
              : const Icon(Icons.cancel, color: Colors.grey),
        ),
      ),
    );
  }
}
