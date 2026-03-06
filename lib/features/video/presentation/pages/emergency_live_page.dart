import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/glassmorphism_button.dart';

/// หน้า Emergency Live - ออกแบบตาม Figma
/// แสดงวิดีโอไลฟ์ + แผนที่ GPS + ปุ่มโต้ตอบ
class EmergencyLivePage extends StatefulWidget {
  final String? videoId;

  const EmergencyLivePage({super.key, this.videoId});

  @override
  State<EmergencyLivePage> createState() => _EmergencyLivePageState();
}

class _EmergencyLivePageState extends State<EmergencyLivePage>
    with TickerProviderStateMixin {
  int _selectedTab = 0;
  int _viewerCount = 10000;
  int _likeCount = 1200;
  double _donationTotal = 625;
  late AnimationController _liveBlinkController;

  // Mock GPS Route
  final List<LatLng> _routePoints = [
    LatLng(35.7150, 51.4050),
    LatLng(35.7165, 51.4080),
    LatLng(35.7180, 51.4110),
    LatLng(35.7195, 51.4140),
    LatLng(35.7210, 51.4170),
    LatLng(35.7230, 51.4200),
    LatLng(35.7260, 51.4230),
  ];

  @override
  void initState() {
    super.initState();
    _liveBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _liveBlinkController.dispose();
    super.dispose();
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      final k = count / 1000;
      return k == k.roundToDouble() ? '${k.round()}K' : '${k.toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // === Layer 1: Map Background ===
          _buildMapBackground(),

          // === Layer 2: All Overlays ===
          SafeArea(
            child: Column(
              children: [
                // Top Bar: Status + Code Icon
                _buildTopBar(),
                const SizedBox(height: 8),

                // Driver Profile
                _buildDriverProfile(),
                const SizedBox(height: 12),

                // Video Player + Trending Panel
                _buildVideoAndTrending(),
                const SizedBox(height: 8),

                // Viewer Count
                _buildViewerCount(),
                const SizedBox(height: 8),

                // Action Buttons (ส่งกำลังใจ, ให้ทาง, บริจาค)
                _buildActionButtons(),

                const Spacer(),

                // Bottom Tabs (Live, ความสัมพันธ์, แจ้งเหตุ)
                _buildBottomTabs(),
                const SizedBox(height: 12),

                // Bottom Navigation Bar
                _buildBottomNav(),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapBackground() {
    return FlutterMap(
      options: MapOptions(
        initialCenter: _routePoints.isNotEmpty
            ? _routePoints[_routePoints.length ~/ 2]
            : LatLng(35.72, 51.41),
        initialZoom: 14.5,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.sheserved.app',
        ),
        // GPS Route Polyline
        PolylineLayer(
          polylines: [
            Polyline(
              points: _routePoints,
              color: const Color(0xFF7B2FF7),
              strokeWidth: 5,
              borderColor: const Color(0xFF7B2FF7).withOpacity(0.3),
              borderStrokeWidth: 2,
            ),
          ],
        ),
        // Current Position Marker
        MarkerLayer(
          markers: [
            if (_routePoints.isNotEmpty)
              Marker(
                point: _routePoints.last,
                width: 30,
                height: 30,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF7B2FF7).withOpacity(0.3),
                    border: Border.all(
                      color: const Color(0xFF7B2FF7),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF7B2FF7),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            'Emergency',
            style: TextStyle(
              fontFamily: 'SukhumvitSet',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black54,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {},
            child: Icon(Icons.code, size: 22, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverProfile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[300],
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              image: const DecorationImage(
                image: NetworkImage('https://i.pravatar.cc/96'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MAHDIFAKHR',
                style: TextStyle(
                  fontFamily: 'SukhumvitSet',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                'DRIVER',
                style: TextStyle(
                  fontFamily: 'SukhumvitSet',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[500],
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.arrow_back, color: Colors.green[600], size: 24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoAndTrending() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Video Player
          Expanded(
            flex: 5,
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      // Placeholder for Video Player
                      Container(
                        color: Colors.black,
                        child: Center(
                          child: Icon(
                            Icons.play_circle_outline,
                            size: 40,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Trending Panel
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'ยอดนิยม',
                        style: TextStyle(
                          fontFamily: 'SukhumvitSet',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B35),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '10 อันดับแรก',
                          style: TextStyle(
                            fontFamily: 'SukhumvitSet',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewerCount() {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'กำลังรับชม',
                style: TextStyle(
                  fontFamily: 'SukhumvitSet',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${_formatCount(_viewerCount)} ราย',
                style: TextStyle(
                  fontFamily: 'SukhumvitSet',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ส่งกำลังใจ
          GlassmorphismButton(
            label: 'ส่งกำลังใจ',
            value: _formatCount(_likeCount),
            textColor: const Color(0xFFFF6B35),
            onTap: () {
              setState(() => _likeCount++);
            },
          ),
          const SizedBox(height: 6),
          // ให้ทาง
          GlassmorphismButton(
            label: 'ให้ทาง',
            value: '20%',
            textColor: const Color(0xFFFF6B35),
            onTap: () {},
          ),
          const SizedBox(height: 6),
          // บริจาค
          GlassmorphismButton(
            label: 'บริจาค',
            value: '${_donationTotal.toStringAsFixed(0)}บ.',
            textColor: const Color(0xFFFF6B35),
            onTap: () => _showDonationSheet(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Live Tab
          Expanded(
            child: GlassTabButton(
              label: 'Live',
              isActive: _selectedTab == 0,
              leading: AnimatedBuilder(
                animation: _liveBlinkController,
                builder: (context, child) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.lerp(
                            Colors.red,
                            Colors.red.withOpacity(0.3),
                            _liveBlinkController.value,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              onTap: () => setState(() => _selectedTab = 0),
            ),
          ),
          const SizedBox(width: 8),
          // ความสัมพันธ์ Tab
          Expanded(
            child: GlassTabButton(
              label: 'ความสัมพันธ์',
              isActive: _selectedTab == 1,
              onTap: () => setState(() => _selectedTab = 1),
            ),
          ),
          const SizedBox(width: 8),
          // แจ้งเหตุ Tab
          Expanded(
            child: GlassTabButton(
              label: 'แจ้งเหตุ\nขอความช่วยเหลือ',
              isActive: _selectedTab == 2,
              trailing: Icon(
                Icons.error_outline,
                size: 20,
                color: _selectedTab == 2 ? Colors.red : Colors.grey,
              ),
              onTap: () => setState(() => _selectedTab = 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _navIcon(Icons.home_outlined, isActive: true),
              _navIcon(Icons.person_outline),
              _navIcon(Icons.camera_alt_outlined),
              _navIcon(Icons.search),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navIcon(IconData icon, {bool isActive = false}) {
    return GestureDetector(
      onTap: () {},
      child: Icon(
        icon,
        size: 26,
        color: isActive ? Colors.black87 : Colors.grey[400],
      ),
    );
  }

  void _showDonationSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'บริจาค',
                    style: TextStyle(
                      fontFamily: 'SukhumvitSet',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'เลือกจำนวนเงินที่ต้องการบริจาค',
                    style: TextStyle(
                      fontFamily: 'SukhumvitSet',
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Quick Amount Buttons
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [10, 50, 100, 500, 1000].map((amount) {
                      return GestureDetector(
                        onTap: () {
                          setState(() => _donationTotal += amount);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'บริจาค $amount บาท สำเร็จ ขอบคุณครับ! 🙏',
                                style: const TextStyle(fontFamily: 'SukhumvitSet'),
                              ),
                              backgroundColor: const Color(0xFF4CAF50),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        },
                        child: Container(
                          width: 90,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6B35), Color(0xFFFF8F65)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF6B35).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '$amount ฿',
                              style: TextStyle(
                                fontFamily: 'SukhumvitSet',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
