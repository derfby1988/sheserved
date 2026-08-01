import 'package:flutter/material.dart';
import '../../data/models/customer.dart';
import '../../data/models/customer_package.dart';
import '../../data/repositories/crm_repository.dart';
import '../../data/repositories/phase_one_repository.dart';
import '../widgets/package_deduction_dialog.dart';

/// หน้าจอ Customer Profile 360° (Group D - Phase 13)
class CustomerProfile360Page extends StatefulWidget {
  final CrmRepository crmRepo;
  final PhaseOneRepository phaseOneRepo;
  final String professionId;
  final String customerId;

  const CustomerProfile360Page({
    super.key,
    required this.crmRepo,
    required this.phaseOneRepo,
    required this.professionId,
    required this.customerId,
  });

  @override
  State<CustomerProfile360Page> createState() => _CustomerProfile360PageState();
}

class _CustomerProfile360PageState extends State<CustomerProfile360Page> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Customer? _customer;
  List<CustomerPackage> _packages = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCustomerProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomerProfile() async {
    setState(() => _isLoading = true);
    try {
      final customers = await widget.phaseOneRepo.getCustomers(widget.professionId);
      final cust = customers.firstWhere(
        (c) => c.id == widget.customerId,
        orElse: () => Customer(
          id: widget.customerId,
          professionId: widget.professionId,
          displayName: 'ไม่พบชื่อลูกค้า',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final pkgs = await widget.crmRepo.getCustomerPackages(
        widget.professionId,
        customerId: widget.customerId,
      );

      if (mounted) {
        setState(() {
          _customer = cust;
          _packages = pkgs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[CustomerProfile360Page] error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cust = _customer;

    return Scaffold(
      appBar: AppBar(
        title: Text(cust?.displayName ?? 'Customer Profile 360°'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCustomerProfile,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header Profile Summary
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: theme.colorScheme.primary,
                        child: Text(
                          (cust?.displayName ?? 'C')[0].toUpperCase(),
                          style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cust?.displayName ?? 'N/A',
                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text('เบอร์โทร: ${cust?.phone ?? 'ไม่ระบุ'} | อีเมล: ${cust?.email ?? 'ไม่ระบุ'}'),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Chip(
                                  label: Text('แต้มสะสม: ${cust?.totalPoints ?? 0}'),
                                  avatar: const Icon(Icons.stars, size: 16, color: Colors.amber),
                                ),
                                const SizedBox(width: 8),
                                Chip(
                                  label: Text('ยอดใช้จ่ายรวม: ฿${(cust?.lifetimeValue ?? 0).toStringAsFixed(2)}'),
                                  avatar: const Icon(Icons.monetization_on, size: 16, color: Colors.green),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Navigation Tabs
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(icon: Icon(Icons.card_membership), text: 'คอร์สแพ็กเกจ'),
                    Tab(icon: Icon(Icons.history), text: 'ประวัติรับบริการ'),
                    Tab(icon: Icon(Icons.info), text: 'ข้อมูลทั่วไป'),
                  ],
                ),

                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Course Packages
                      _packages.isEmpty
                          ? const Center(child: Text('ลูกค้ารายนี้ยังไม่มีคอร์สแพ็กเกจ'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _packages.length,
                              itemBuilder: (context, index) {
                                final pkg = _packages[index];
                                return Card(
                                  child: ListTile(
                                    title: Text(pkg.packageName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text('คงเหลือ: ${pkg.remainingSessions} / ${pkg.totalSessions} ครั้ง'),
                                    trailing: ElevatedButton(
                                      onPressed: pkg.remainingSessions > 0
                                          ? () async {
                                              final res = await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => PackageDeductionDialog(
                                                  crmRepo: widget.crmRepo,
                                                  package: pkg,
                                                ),
                                              );
                                              if (res == true) _loadCustomerProfile();
                                            }
                                          : null,
                                      child: const Text('ตัดเซสชัน'),
                                    ),
                                  ),
                                );
                              },
                            ),

                      // Tab 2: Appointment / Visit History
                      const Center(child: Text('ประวัติการรับบริการคลินิก & POS')),

                      // Tab 3: Additional General Info
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('รหัสลูกค้า: ${cust?.customerCode ?? 'N/A'}'),
                            const SizedBox(height: 8),
                            Text('ประเภทลูกค้า: ${cust?.customerType ?? 'walk_in'}'),
                            const SizedBox(height: 8),
                            Text('วันเกิด: ${cust?.birthday?.toString().split(' ')[0] ?? 'ไม่ระบุ'}'),
                            const SizedBox(height: 8),
                            Text('บันทึกเพิ่มเติม: ${cust?.notes ?? 'ไม่มี'}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
