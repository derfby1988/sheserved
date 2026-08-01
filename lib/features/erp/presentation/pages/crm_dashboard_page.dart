import 'package:flutter/material.dart';
import '../../data/repositories/crm_repository.dart';
import '../../data/repositories/phase_one_repository.dart';
import 'customer_package_page.dart';
import 'customer_profile_360_page.dart';
import 'loyalty_rules_page.dart';
import '../widgets/package_deduction_dialog.dart';

/// CRM Main Dashboard Page (Group D - Phase 11)
class CrmDashboardPage extends StatefulWidget {
  final CrmRepository crmRepo;
  final PhaseOneRepository phaseOneRepo;
  final String professionId;

  const CrmDashboardPage({
    super.key,
    required this.crmRepo,
    required this.phaseOneRepo,
    required this.professionId,
  });

  @override
  State<CrmDashboardPage> createState() => _CrmDashboardPageState();
}

class _CrmDashboardPageState extends State<CrmDashboardPage> {
  bool _isLoading = true;
  int _totalCustomers = 0;
  int _activePackages = 0;
  int _totalLoyaltyMembers = 0;
  int _totalCouponUsages = 0;
  List<Map<String, dynamic>> _recentWallets = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final customers = await widget.phaseOneRepo.getCustomers(widget.professionId);
      final packages = await widget.crmRepo.getCustomerPackages(widget.professionId);
      final wallets = await widget.crmRepo.getCustomerLoyaltyWallets(widget.professionId);
      final usages = await widget.crmRepo.getCouponUsages(widget.professionId);

      if (mounted) {
        setState(() {
          _totalCustomers = customers.length;
          _activePackages = packages.where((p) => p.remainingSessions > 0).length;
          _totalLoyaltyMembers = wallets.where((w) => (w['current_points'] as int? ?? 0) > 0).length;
          _totalCouponUsages = usages.length;
          _recentWallets = wallets.take(5).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[CrmDashboardPage] error loading data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                Icon(icon, color: color, size: 24),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM Dashboard & Customer Hub'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stat Overview Grid
                    GridView.count(
                      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildStatCard('ลูกค้าทั้งหมด', '$_totalCustomers คน', Icons.people, Colors.blue),
                        _buildStatCard('คอร์สที่เปิดใช้งาน', '$_activePackages คอร์ส', Icons.card_membership, Colors.purple),
                        _buildStatCard('สมาชิกสะสมแต้ม', '$_totalLoyaltyMembers คน', Icons.stars, Colors.amber),
                        _buildStatCard('การใช้คูปองสะสม', '$_totalCouponUsages ครั้ง', Icons.local_offer, Colors.green),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Quick Action Menu
                    Text('เมนูดำเนินการด่วน', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CustomerPackagePage(
                                  crmRepo: widget.crmRepo,
                                  professionId: widget.professionId,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.card_membership),
                          label: const Text('จัดการคอร์สแพ็กเกจ'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LoyaltyRulesPage(professionId: widget.professionId),
                              ),
                            );
                          },
                          icon: const Icon(Icons.stars),
                          label: const Text('ตั้งค่า Loyalty Points'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Recent Customer Loyalty Wallets Overview
                    Text('สรุปสมาชิก Loyalty ล่าสุด', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _recentWallets.isEmpty
                        ? const Card(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('ยังไม่มีข้อมูลสมาชิกสะสมแต้ม'),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _recentWallets.length,
                            itemBuilder: (context, index) {
                              final wallet = _recentWallets[index];
                              final displayName = wallet['display_name'] as String? ?? 'ลูกค้าทั่วไป';
                              final points = wallet['current_points'] as int? ?? 0;
                              final tier = wallet['tier'] as String? ?? 'bronze';
                              final customerId = wallet['customer_id'] as String;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: theme.colorScheme.primaryContainer,
                                    child: Icon(Icons.person, color: theme.colorScheme.primary),
                                  ),
                                  title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('ระดับสมาชิก: ${tier.toUpperCase()} | สะสม: $points แต้ม'),
                                  trailing: OutlinedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CustomerProfile360Page(
                                            crmRepo: widget.crmRepo,
                                            phaseOneRepo: widget.phaseOneRepo,
                                            professionId: widget.professionId,
                                            customerId: customerId,
                                          ),
                                        ),
                                      );
                                    },
                                    child: const Text('ดู Profile 360°'),
                                  ),
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ),
    );
  }
}
