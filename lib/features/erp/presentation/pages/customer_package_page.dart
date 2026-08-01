import 'package:flutter/material.dart';
import '../../data/models/customer_package.dart';
import '../../data/repositories/crm_repository.dart';
import '../widgets/package_deduction_dialog.dart';

/// หน้าจัดการคอร์สแพ็กเกจล่วงหน้า (Customer Packages Management Page - Group C Phase 10)
class CustomerPackagePage extends StatefulWidget {
  final CrmRepository crmRepo;
  final String professionId;
  final String? customerId;

  const CustomerPackagePage({
    super.key,
    required this.crmRepo,
    required this.professionId,
    this.customerId,
  });

  @override
  State<CustomerPackagePage> createState() => _CustomerPackagePageState();
}

class _CustomerPackagePageState extends State<CustomerPackagePage> {
  late Future<List<CustomerPackage>> _packagesFuture;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPackages();
  }

  void _loadPackages() {
    setState(() {
      _packagesFuture = widget.crmRepo.getCustomerPackages(
        widget.professionId,
        customerId: widget.customerId,
      );
    });
  }

  Future<void> _openCreatePackageDialog() async {
    final nameCtrl = TextEditingController();
    final customerIdCtrl = TextEditingController(text: widget.customerId ?? '');
    final sessionsCtrl = TextEditingController(text: '10');
    final priceCtrl = TextEditingController(text: '5000');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ขายคอร์สแพ็กเกจใหม่'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'ชื่อคอร์ส/แพ็กเกจ', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: customerIdCtrl,
                decoration: const InputDecoration(labelText: 'Customer ID', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sessionsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'จำนวนครั้งทั้งหมด', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ราคาแพ็กเกจ (บาท)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () async {
              final sessions = int.tryParse(sessionsCtrl.text.trim()) ?? 0;
              final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
              if (nameCtrl.text.trim().isEmpty || sessions <= 0) return;

              final pkg = await widget.crmRepo.createCustomerPackage({
                'profession_id': widget.professionId,
                'customer_id': customerIdCtrl.text.trim(),
                'package_name': nameCtrl.text.trim(),
                'total_sessions': sessions,
                'used_sessions': 0,
                'remaining_sessions': sessions,
                'total_price': price,
                'status': 'active',
              });

              if (ctx.mounted) {
                Navigator.pop(ctx, pkg != null);
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );

    if (result == true) {
      _loadPackages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('สร้างคอร์สแพ็กเกจเรียบร้อยแล้ว')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการคอร์สแพ็กเกจ (Prepaid Packages)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPackages,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreatePackageDialog,
        icon: const Icon(Icons.add),
        label: const Text('ขายคอร์สใหม่'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'ค้นหาคอร์สแพ็กเกจ...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CustomerPackage>>(
              future: _packagesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
                }

                final packages = snapshot.data ?? [];
                final query = _searchController.text.trim().toLowerCase();
                final filtered = packages.where((p) => p.packageName.toLowerCase().contains(query)).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text('ไม่พบคอร์สแพ็กเกจในระบบ'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final pkg = filtered[index];
                    final isExpired = pkg.status == 'expired' || (pkg.expiresAt != null && DateTime.now().isAfter(pkg.expiresAt!));
                    final isCompleted = pkg.remainingSessions <= 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isCompleted
                              ? Colors.grey
                              : isExpired
                                  ? Colors.red.shade100
                                  : theme.colorScheme.primaryContainer,
                          child: Icon(
                            Icons.card_membership,
                            color: isCompleted
                                ? Colors.grey.shade700
                                : isExpired
                                    ? Colors.red
                                    : theme.colorScheme.primary,
                          ),
                        ),
                        title: Text(pkg.packageName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('ราคา: ฿${pkg.totalPrice.toStringAsFixed(2)} | เซสชัน: ${pkg.usedSessions}/${pkg.totalSessions} ครั้ง'),
                            Text(
                              'คงเหลือ: ${pkg.remainingSessions} ครั้ง',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: pkg.remainingSessions > 0 ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                        trailing: ElevatedButton.icon(
                          onPressed: (pkg.remainingSessions > 0 && !isExpired)
                              ? () async {
                                  final result = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => PackageDeductionDialog(
                                      crmRepo: widget.crmRepo,
                                      package: pkg,
                                    ),
                                  );
                                  if (result == true) {
                                    _loadPackages();
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.exposure_minus_1, size: 18),
                          label: const Text('ตัดเซสชัน'),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
