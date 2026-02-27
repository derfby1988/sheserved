import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/repositories/donation_repository.dart';
import '../../models/donation_models.dart';
import '../widgets/category_icon.dart';
import '../widgets/donation_stats_row.dart';
import '../widgets/trending_donation_card.dart';
import 'package:shimmer/shimmer.dart';
import 'donation_detail_page.dart';

class DonationDashboardPage extends StatefulWidget {
  const DonationDashboardPage({super.key});

  @override
  State<DonationDashboardPage> createState() => _DonationDashboardPageState();
}

class _DonationDashboardPageState extends State<DonationDashboardPage> {
  late final DonationRepository _repository;
  DonationStats? _stats;

  @override
  void initState() {
    super.initState();
    _repository = DonationRepository(Supabase.instance.client);
    _loadData();
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
              
              return CustomScrollView(
            slivers: [
              // Hero Banner with Back Button
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      height: 189,
                      decoration: const BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage("assets/images/donation_banner.png"),
                          fit: BoxFit.cover,
                        ),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 40,
                      left: 16,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_back, color: Color(0xFF76A5A5), size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Emergency Section
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFF97BBBB),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  margin: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'เหตุด่วน / ฉุกเฉิน / ภัยพิบัติ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: emergencyCategories.map((cat) => Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: CategoryIcon(
                              label: cat.name,
                              icon: _getIconData(cat.iconName),
                              onTap: () {},
                            ),
                          )).toList(),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      if (_stats != null) ...[
                        DonationStatsRow(stats: _stats!),
                        const SizedBox(height: 16),
                        // Dynamic Progress Bar (Pulse Effect)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ความคืบหน้าภาพรวม',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              const SizedBox(height: 8),
                              _PulseProgressBar(
                                progress: (_stats!.received / _stats!.requested).clamp(0.0, 1.0),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),

              // General Categories Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'หมวดหมู่',
                        style: TextStyle(
                          color: Color(0xFF7FA2C2),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          childAspectRatio: 0.8,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: generalCategories.length,
                        itemBuilder: (context, index) {
                          final cat = generalCategories[index];
                          return CategoryIcon(
                            label: cat.name,
                            icon: _getIconData(cat.iconName),
                            iconColor: const Color(0xFF76A5A5),
                            onTap: () {},
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Trending Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'กำลังได้รับความนิยม',
                        style: TextStyle(
                          color: Color(0xFF7FA2C2),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
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
              ),
            ],
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
      case 'favorite': return Icons.favorite;
      case 'home': return Icons.home;
      case 'local_shipping': return Icons.local_shipping;
      case 'elderly': return Icons.elderly;
      default: return Icons.help_outline;
    }
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
      width: double.infinity,
      height: 12,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          // Background Progress
          FractionallySizedBox(
            widthFactor: widget.progress,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: Colors.white.withOpacity(0.5), blurRadius: 4),
                ],
              ),
            ),
          ),
          // Shimmer/Pulse Effect
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return FractionallySizedBox(
                widthFactor: widget.progress,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ShaderMask(
                    shaderCallback: (rect) {
                      return LinearGradient(
                        begin: Alignment(_animation.value, 0),
                        end: Alignment(_animation.value + 1.0, 0),
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.4),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ).createShader(rect);
                    },
                    child: Container(color: Colors.white),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Skeleton Loading สำหรับ Dashboard
class _SkeletonDashboard extends StatelessWidget {
  const _SkeletonDashboard();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(height: 189, color: Colors.white),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 200, height: 24, color: Colors.white),
                  const SizedBox(height: 16),
                  Row(
                    children: List.generate(4, (index) => Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: CircleAvatar(radius: 30, backgroundColor: Colors.white),
                    )),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: List.generate(3, (index) => Expanded(
                      child: Container(height: 80, margin: const EdgeInsets.all(4), color: Colors.white),
                    )),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 100, height: 24, color: Colors.white),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: 8,
                    itemBuilder: (_, __) => Column(
                      children: [
                        CircleAvatar(radius: 25, backgroundColor: Colors.white),
                        const SizedBox(height: 8),
                        Container(width: 40, height: 10, color: Colors.white),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
