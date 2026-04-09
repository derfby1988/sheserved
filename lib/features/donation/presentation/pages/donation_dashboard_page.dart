import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/repositories/donation_repository.dart';
import '../../models/donation_models.dart';
import '../widgets/category_icon.dart';
import '../widgets/donation_stats_row.dart';
import '../widgets/trending_donation_card.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../../core/constants/app_colors.dart';
import 'donation_detail_page.dart';
import 'donation_list_page.dart';
import 'donation_create_page.dart';

class DonationDashboardPage extends StatefulWidget {
  const DonationDashboardPage({super.key});

  @override
  State<DonationDashboardPage> createState() => _DonationDashboardPageState();
}

class _DonationDashboardPageState extends State<DonationDashboardPage> {
  late final DonationRepository _repository;
  DonationStats? _stats;
  List<Map<String, dynamic>> _pendingRefunds = [];

  @override
  void initState() {
    super.initState();
    _repository = DonationRepository(Supabase.instance.client);
    AuthService.instance.addListener(_onAuthChanged);
    _loadData();
    
    // Check for auto-create argument (redirected from login)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args == 'auto_create' && ServiceLocator.instance.currentUser != null) {
        _handleAutoCreateAfterLogin();
      }
    });
  }

  void _handleAutoCreateAfterLogin() {
    // Show a snackbar to inform the user
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('กำลังนำคุณไปยังหน้าสร้างคำร้องขอ...'),
        duration: Duration(seconds: 1),
      ),
    );
    
    // Wait for 1 second as requested before navigating
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const DonationCreatePage()),
        );
      }
    });
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    // Only fetch non-streaming stats here
    try {
      final stats = await _repository.getOverallStats();
      setState(() {
        _stats = stats;
      });
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }

    // Check for pending refunds
    final currentUser = ServiceLocator.instance.currentUser;
    if (currentUser != null) {
      try {
        final refunds = await _repository.getRefundPendingTransactions(currentUser.id);
        if (mounted) {
          setState(() {
            _pendingRefunds = refunds;
          });
        }
      } catch (e) {
        debugPrint('Error checking refunds: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: const TlzDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (ServiceLocator.instance.currentUser != null) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DonationCreatePage()),
            );
          } else {
            Navigator.pushNamed(
              context,
              '/login',
              arguments: {
                'redirect': '/donate',
                'args': 'auto_create',
              },
            );
          }
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_circle_outline, color: Colors.white),
        label: const Text('ขอรับบริจาค', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<List<DonationCategory>>(
        stream: _repository.watchCategories(),
        builder: (context, catSnapshot) {
          if (!catSnapshot.hasData) return const _SkeletonDashboard();
          
          final categories = catSnapshot.data!;
          final emergencyCategories = categories.where((c) => c.isEmergency).toList();
          final generalCategories = categories.where((c) => !c.isEmergency).toList();
          
          return StreamBuilder<List<DonationRequest>>(
            stream: _repository.watchRequests(),
            builder: (context, reqSnapshot) {
              final trendingRequests = reqSnapshot.data?.where((r) => r.isTrending).toList() ?? [];
              
              return SingleChildScrollView(
                child: Column(
                  children: [
                    if (_pendingRefunds.isNotEmpty) _buildRefundAlert(),
                    // Banner & Emergency Section Layout (Stack)
                    Stack(
                      children: [
                        // 1. Background Image Banner
                        Container(
                          width: double.infinity,
                          height: 250,
                          decoration: const BoxDecoration(
                            image: DecorationImage(
                              image: AssetImage("assets/images/donation_banner.png"),
                              fit: BoxFit.cover,
                            ),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withOpacity(0.6),
                                  Colors.transparent,
                                   Colors.black.withOpacity(0.1),
                                ],
                                stops: const [0.0, 0.4, 1.0],
                              ),
                            ),
                          ),
                        ),
                        // 2. Top Bar
                        SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: TlzAppTopBar.onLight(
                              onMenuPressed: () => Scaffold.of(context).openDrawer(),
                              searchHintText: 'ค้นหาการบริจาค...',
                              showQRButton: false,
                            ),
                          ),
                        ),
                        // 3. Emergency Card (Overlapping Banner correctly)
                        Padding(
                          padding: const EdgeInsets.only(top: 190), // Offset down to overlap bottom of banner
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.primary, const Color(0xFF1B4E4E)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.3),
                                  blurRadius: 15,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Row(
                                    children: const [
                                      Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 22),
                                      SizedBox(width: 8),
                                      Text(
                                        'เหตุด่วน / ภัยพิบัติ',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Row(
                                    children: emergencyCategories.map((cat) => Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: CategoryIcon(
                                        label: cat.name,
                                        icon: _getIconData(cat.iconName),
                                        iconColor: AppColors.primary,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => DonationListPage(
                                                categoryId: cat.id,
                                                categoryName: cat.name,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    )).toList(),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                if (_stats != null) ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 0),
                                    child: DonationStatsRow(stats: _stats!),
                                  ),
                                  const SizedBox(height: 20),
                                  // Dynamic Progress Bar
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'ความคืบหน้าภาพรวม',
                                              style: TextStyle(color: Colors.white70, fontSize: 13),
                                            ),
                                            Text(
                                              '${((_stats!.received / (_stats!.requested == 0 ? 1 : _stats!.requested)) * 100).toStringAsFixed(1)}%',
                                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        _PulseProgressBar(
                                          progress: (_stats!.received / (_stats!.requested == 0 ? 1 : _stats!.requested)).clamp(0.0, 1.0),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // General Categories Section
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'หมวดหมู่บริการ',
                            style: TextStyle(
                              color: Color(0xFF2C3E50),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          GridView.builder(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 0.85,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 12,
                            ),
                            itemCount: generalCategories.length,
                            itemBuilder: (context, index) {
                              final cat = generalCategories[index];
                              return CategoryIcon(
                                label: cat.name,
                                icon: _getIconData(cat.iconName),
                                iconColor: const Color(0xFF76A5A5),
                                labelColor: const Color(0xFF4A6A8A),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DonationListPage(
                                        categoryId: cat.id,
                                        categoryName: cat.name,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // Trending Section
                    Padding(
                      padding: const EdgeInsets.only(left: 20, bottom: 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.local_fire_department_rounded, color: Colors.orange, size: 24),
                              SizedBox(width: 8),
                              Text(
                                'กำลังได้รับความนิยม',
                                style: TextStyle(
                                  color: Color(0xFF2C3E50),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 220,
                            child: trendingRequests.isEmpty
                              ? const Center(child: Text('ไม่มีข้อมูลยอดนิยมในขณะนี้'))
                              : ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: trendingRequests.length,
                                  itemBuilder: (context, index) {
                                    return TrendingDonationCard(
                                      request: trendingRequests[index],
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => DonationDetailPage(request: trendingRequests[index]),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _getIconData(String? iconName) {
    switch (iconName) {
      case 'emergency_share': return Icons.emergency_share;
      case 'gavel': return Icons.gavel;
      case 'local_fire_department': return Icons.local_fire_department;
      case 'water_damage': return Icons.water_damage;
      case 'payments': return Icons.payments;
      case 'inventory_2': return Icons.inventory_2;
      case 'restaurant': return Icons.restaurant;
      case 'healing': return Icons.healing;
      case 'pets': return Icons.pets;
      case 'warning': return Icons.warning_amber_rounded;
      case 'favorite': return Icons.favorite;
      case 'home': return Icons.home;
      case 'local_shipping': return Icons.local_shipping;
      case 'elderly': return Icons.elderly;
      default: return Icons.help_outline;
    }
  }

  Widget _buildRefundAlert() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 88, left: 16, right: 16), // Bottom of Safe Top Bar
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade900,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'บางรายการบริจาคของคุณถูกยกเลิกเนื่องจากเหตุการณ์สิ้นสุด',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, color: Colors.white54, size: 16),
                onPressed: () => setState(() => _pendingRefunds = []),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'กรุณาคลิกเลือกวิธีจัดการเงินบริจาค เพื่อสิทธิประโยชน์ของคุณ',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _showRefundResolutionDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue.shade900,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('ดำเนินการเลือกวิธีคืนเงิน', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _showRefundResolutionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('จัดการเงินคืน (Refund Resolution)', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _pendingRefunds.map((tx) {
                  final amount = tx['amount']?.toString() ?? '0';
                  final title = tx['request']?['title'] ?? 'คำร้องนี้';
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('รายการ: $title', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('ยอดเงิน: ฿$amount', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                          const Divider(),
                          const Text('เลือกวิธีจัดการ:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await _repository.updateRefundPreference(tx['id'], 'credit');
                                    _loadData(); // Re-check
                                    if (mounted) Navigator.pop(ctx);
                                  },
                                  child: const Text('รับเครดิตในแอป', style: TextStyle(fontSize: 12)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () async {
                                    await _repository.updateRefundPreference(tx['id'], 'beneficiary');
                                    _loadData(); // Re-check
                                    if (mounted) Navigator.pop(ctx);
                                  },
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                                  child: const Text('มอบให้กองทุน', style: TextStyle(fontSize: 12, color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ไว้ภายหลัง'),
            ),
          ],
        ),
      ),
    );
  }
}

/// แถบความคืบหน้าแบบมีแอนิเมชัน Pulse
class _PulseProgressBar extends StatefulWidget {
  final double progress;
  const _PulseProgressBar({required this.progress});

  @override
  State<_PulseProgressBar> createState() => _PulseProgressBarState();
}

class _PulseProgressBarState extends State<_PulseProgressBar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Stack(
          children: [
            FractionallySizedBox(
              widthFactor: widget.progress,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blueAccent,
                      Colors.cyanAccent.shade400,
                    ],
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Positioned(
                  left: (widget.progress * MediaQuery.of(context).size.width) * _animation.value,
                  child: Container(
                    width: 40,
                    height: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0),
                          Colors.white.withOpacity(0.5),
                          Colors.white.withOpacity(0),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonDashboard extends StatelessWidget {
  const _SkeletonDashboard();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(height: 200, color: Colors.white),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(4, (i) => CircleAvatar(radius: 30, backgroundColor: Colors.white)),
          ),
          const SizedBox(height: 32),
          Container(height: 20, width: 150, color: Colors.white),
          const SizedBox(height: 16),
          Row(
            children: List.generate(2, (i) => Expanded(child: Container(height: 150, margin: const EdgeInsets.all(4), color: Colors.white))),
          ),
        ],
      ),
    );
  }
}
