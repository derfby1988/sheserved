import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/customer.dart';
import '../providers/phase_one_provider.dart';
import '../widgets/glass_card.dart';

class CustomerListPage extends ConsumerStatefulWidget {
  final String professionId;

  const CustomerListPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends ConsumerState<CustomerListPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseOneProvider.notifier).loadCustomers(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseOneProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ลูกค้า / CRM'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.customers.length,
                  itemBuilder: (context, index) {
                    final customer = state.customers[index];
                    return _CustomerCard(customer: customer);
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateCustomerDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('เพิ่มลูกค้า'),
      ),
    );
  }

  void _showCreateCustomerDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิ่มลูกค้าใหม่'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'ชื่อแสดง')),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'โทรศัพท์')),
            TextField(controller: emailController, decoration: const InputDecoration(labelText: 'อีเมล')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () async {
              final notifier = ref.read(phaseOneProvider.notifier);
              final success = await notifier.createCustomer({
                'profession_id': widget.professionId,
                'display_name': nameController.text.trim(),
                'phone': phoneController.text.trim(),
                'email': emailController.text.trim(),
              });
              if (success && mounted) {
                Navigator.pop(context);
                notifier.loadCustomers(widget.professionId);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('เพิ่มลูกค้าสำเร็จ')),
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

class _CustomerCard extends StatelessWidget {
  final Customer customer;

  const _CustomerCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 16,
        padding: const EdgeInsets.all(14),
        child: ListTile(
          leading: CircleAvatar(
            child: Text(customer.displayName.isNotEmpty ? customer.displayName[0] : '?'),
          ),
          title: Text(customer.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (customer.phone != null) Text(customer.phone!),
              Text('ประเภท: ${customer.customerTypeLabel}'),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${customer.totalPoints} pts', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${customer.visitCount} ครั้ง', style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
