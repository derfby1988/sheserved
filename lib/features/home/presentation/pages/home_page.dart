import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';

/// Home Page - Medical App Design
/// Main dashboard for health/medical services
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  double? _dragStartX;
  bool _isDraggingFromLeft = false;
  late ScrollController _scrollController;
  final GlobalKey _headerSectionKey = GlobalKey();
  double _headerSectionHeight = 0;
  bool _showTopBarBorderRadius = false;
  
  // Map state
  bool _isMapLoaded = false;
  bool _mapHasError = false;
  int _mapErrorCount = 0;
  static const int _maxMapErrors = 5; // จำนวน error สูงสุดก่อนแสดง error UI
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    // Shimmer animation controller
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    // วัดความสูงของ Header Section หลังจาก build เสร็จ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureHeaderSectionHeight();
    });
    
    // เริ่มโหลดแผนที่
    _startMapLoading();
  }
  
  void _startMapLoading() {
    // รอให้ map tiles โหลด (ปกติใช้เวลา 2-3 วินาที)
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && !_mapHasError) {
        setState(() {
          _isMapLoaded = true;
        });
      }
    });
  }
  
  void _retryMapLoad() {
    setState(() {
      _isMapLoaded = false;
      _mapHasError = false;
      _mapErrorCount = 0;
    });
    _startMapLoading();
  }
  
  void _onMapTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    _mapErrorCount++;
    debugPrint('Map tile error #$_mapErrorCount: $error');
    
    // ถ้า error เกินจำนวนที่กำหนด ให้แสดง error UI
    if (_mapErrorCount >= _maxMapErrors && mounted && !_mapHasError) {
      setState(() {
        _mapHasError = true;
        _isMapLoaded = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _measureHeaderSectionHeight() {
    final RenderBox? renderBox = _headerSectionKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      setState(() {
        _headerSectionHeight = renderBox.size.height;
      });
    }
  }

  void _onScroll() {
    if (!mounted) return;
    
    // วัดความสูงของ Header Section ถ้ายังไม่ได้ค่า
    if (_headerSectionHeight <= 0) {
      _measureHeaderSectionHeight();
      if (_headerSectionHeight <= 0) return;
    }

    // เมื่อ scroll offset >= ความสูงของ Header Section
    // หมายความว่า Header Section ได้เลื่อนผ่านไปแล้ว (ส่วนล่างถึง Top Nav Bar)
    final shouldShowBorderRadius = _scrollController.offset >= _headerSectionHeight;

    if (shouldShowBorderRadius != _showTopBarBorderRadius) {
      setState(() {
        _showTopBarBorderRadius = shouldShowBorderRadius;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const TlzDrawer(),
      drawerEnableOpenDragGesture: true, // เปิดใช้งานการปัดเพื่อเปิด drawer
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/test');
        },
        backgroundColor: AppColors.primary,
        child: const Icon(
          Icons.bug_report,
          color: AppColors.textOnPrimary,
        ),
        tooltip: 'ทดสอบ WebSocket',
      ),
      body: Builder(
        builder: (context) => GestureDetector(
          // ตรวจสอบการปัดจากขอบซ้ายเพื่อเปิด drawer
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (details) {
            if (details.globalPosition.dx < 30) {
              setState(() {
                _dragStartX = details.globalPosition.dx;
                _isDraggingFromLeft = true;
              });
            } else {
              setState(() {
                _isDraggingFromLeft = false;
              });
            }
          },
          onHorizontalDragUpdate: (details) {
            if (_isDraggingFromLeft && _dragStartX != null && details.globalPosition.dx > _dragStartX! + 50) {
              Scaffold.of(context).openDrawer();
              setState(() {
                _isDraggingFromLeft = false;
                _dragStartX = null;
              });
            }
          },
          onHorizontalDragEnd: (details) {
            if (_isDraggingFromLeft && details.velocity.pixelsPerSecond.dx > 300) {
              Scaffold.of(context).openDrawer();
            }
            setState(() {
              _isDraggingFromLeft = false;
              _dragStartX = null;
            });
          },
          child: Container(
            // พื้นหลังสีเขียวด้านบน (รวมพื้นที่ status bar)
            color: AppColors.primary,
            child: SafeArea(
              child: Column(
                children: [
                  // Top Navigation Bar - อยู่กับที่ (ไม่เลื่อน)
                  _buildTopNavigationBar(context),
                
                // Main Content with Scrollable Header Section
                Expanded(
                  child: Container(
                    // พื้นหลังสีเดียวกับ search bar
                    color: AppColors.primary,
                    child: ClipRect(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: Stack(
                          children: [
                            // Background Layer - Map ขยายลงมาถึงกลาง Pharmacy Card
                            Column(
                              children: [
                                // Map Background - ความสูงถึงกลาง pharmacy card
                                // Header(~144) + SizedBox(16) + Consultation(~220) + SizedBox(24) + HalfPharmacy(~60) = ~464
                                SizedBox(
                                  height: 500, // ความสูงถึงกลาง pharmacy card
                                  child: _buildMapBackground(),
                                ),
                                // Content ด้านล่าง map - พื้นหลังสี #EDF5DA
                                Container(
                                  width: double.infinity,
                                  color: const Color(0xFFEDF5DA),
                                  child: Column(
                                    children: [
                                      // Spacer สำหรับครึ่งล่างของ Pharmacy Card + SizedBox(24)
                                      const SizedBox(height: 100),
                                      _buildRecommendedSection(context),
                                      const SizedBox(height: 24),
                                      _buildInterestingSection(context),
                                      const SizedBox(height: 32),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            // Foreground Layer - Header, Consultation, Pharmacy Card
                            Column(
                              children: [
                                _buildHeaderSection(context),
                                const SizedBox(height: 16),
                                _buildConsultationWidget(context),
                                const SizedBox(height: 24),
                                _buildPharmacyCard(context),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapBackground() {
    // ตำแหน่งเริ่มต้น: กรุงเทพมหานคร
    const initialLocation = LatLng(13.7563, 100.5018);
    
    return Stack(
      fit: StackFit.expand, // ให้ Stack ขยายเต็มพื้นที่
      children: [
        // Skeleton Loader (shows while map is loading)
        if (!_isMapLoaded && !_mapHasError) _buildMapSkeleton(),
        
        // Error UI (shows when map fails to load)
        if (_mapHasError) _buildMapError(),
        
        // Map with Blur Effect (with fade-in animation)
        if (!_mapHasError)
          AnimatedOpacity(
            opacity: _isMapLoaded ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 500),
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: initialLocation,
                    initialZoom: 13.0,
                    minZoom: 10.0,
                    maxZoom: 18.0,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none, // ปิดการโต้ตอบกับแผนที่
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.tree_law_zoo',
                      maxZoom: 19,
                      tileProvider: CancellableNetworkTileProvider(),
                      errorTileCallback: _onMapTileError,
                      evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
                    ),
                  ],
                ),
              ),
            ),
          ),
        
        // Overlay สีเพื่อให้แผนที่ดูเบาลงและเข้ากับธีม
        if (!_mapHasError)
          Container(
            decoration: BoxDecoration(
              color: AppColors.background.withOpacity(0.05),
            ),
          ),
      ],
    );
  }
  
  /// Error widget when map fails to load
  Widget _buildMapError() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background,
            AppColors.background.withOpacity(0.8),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Error Icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.map_outlined,
                size: 48,
                color: AppColors.textHint,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Error Message
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ไม่สามารถโหลดแผนที่ได้',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ต',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Retry Button
                  TextButton.icon(
                    onPressed: _retryMapLoad,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('ลองใหม่'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Skeleton loader for map with shimmer effect
  Widget _buildMapSkeleton() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2 * _shimmerController.value, 0),
              end: Alignment(-1.0 + 2 * _shimmerController.value + 1, 0),
              colors: [
                AppColors.background,
                AppColors.background.withOpacity(0.5),
                AppColors.surface,
                AppColors.background.withOpacity(0.5),
                AppColors.background,
              ],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // Grid pattern to simulate map tiles
              CustomPaint(
                size: Size.infinite,
                painter: _MapSkeletonPainter(
                  color: AppColors.border.withOpacity(0.3),
                ),
              ),
              // Center loading indicator
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.shadow,
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'กำลังโหลดแผนที่...',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
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
  }

  /// Top Navigation Bar - อยู่กับที่ (ไม่เลื่อน)
  Widget _buildTopNavigationBar(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: _showTopBarBorderRadius
            ? const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              )
            : null,
      ),
      child: TlzAppTopBar.onPrimary(
        notificationCount: 1,
        searchHintText: 'ค้นหายา ร้านยา หมอ...',
        // onMenuPressed: null → ใช้ default behavior เพื่อเปิด Drawer
        onQRTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('QR Scanner จะเปิดใช้งานเร็วๆ นี้'),
              duration: Duration(seconds: 1),
            ),
          );
        },
        onNotificationTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('การแจ้งเตือนจะเปิดใช้งานเร็วๆ นี้'),
              duration: Duration(seconds: 1),
            ),
          );
        },
        onCartTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ตะกร้าสินค้าจะเปิดใช้งานเร็วๆ นี้'),
              duration: Duration(seconds: 1),
            ),
          );
        },
        onResultTap: (item) {
          // เมื่อกดผลการค้นหา
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('เลือก: ${item['title']}'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
      ),
    );
  }

  /// Header Section (Content Row) - สามารถเลื่อนได้
  Widget _buildHeaderSection(BuildContext context) {
    return Container(
      key: _headerSectionKey,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Side: Status Text & Profile Picture
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // กดเพื่อไปหน้า Health
                GestureDetector(
                  onTap: () {
                    Navigator.pushNamed(context, '/health');
                  },
                  child: Text(
                    'สุขภาพ "ดี"',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.textOnPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Profile Picture Button - กดเพื่อไปหน้า Login
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.pushNamed(context, '/login');
                    },
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.textOnPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.textOnPrimary,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.person,
                        color: AppColors.primary,
                        size: 36,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Right Side: Medicine Reminder & Popular Badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'อีก 10 นาที\nทานยา',
                textAlign: TextAlign.right,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textOnPrimary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.textOnPrimary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'ได้รับความนิยม',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textOnPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConsultationWidget(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer Solid Green Ring - วงแหวนสีเขียวทึบด้านนอก
          SizedBox(
            width: 280,
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Solid Green Circle (outer ring)
                Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    color: AppColors.primary, // สีเขียว #71BE0A
                    shape: BoxShape.circle,
                  ),
                ),
                // White Circle (inner cutout)
                Container(
                  width: 240,
                  height: 240,
                  decoration: const BoxDecoration(
                    color: AppColors.backgroundWhite,
                    shape: BoxShape.circle,
                  ),
                ),
                // Green Dots on Ring (top right และ bottom left)
                Positioned(
                  right: 0,
                  top: 20,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  bottom: 20,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Inner Circle Background - White
          Container(
            width: 240,
            height: 240,
            decoration: const BoxDecoration(
              color: AppColors.backgroundWhite, // สีขาว
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Inner Dotted Line - เส้นประสีเทาอ่อนด้านใน
                SizedBox(
                  width: 220,
                  height: 220,
                  child: CustomPaint(
                    painter: DottedCirclePainter(
                      color: AppColors.textHint.withOpacity(0.3), // สีเทาอ่อน
                      strokeWidth: 1.5,
                      dashWidth: 4,
                      dashSpace: 3,
                    ),
                  ),
                ),
                
                // Content
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Stethoscope Icon (สีดำ, ไม่มี background circle)
                    const Icon(
                      Icons.medical_services,
                      size: 56,
                      color: AppColors.textPrimary, // สีดำ
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Title "ปรึกษา" (สีดำ, ตัวหนา)
                    Text(
                      'ปรึกษา',
                      style: AppTextStyles.heading3.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    
                    const SizedBox(height: 6),
                    
                    // Subtitle "แพทย์ & เภสัช" ("&" สีเทา)
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        children: [
                          const TextSpan(text: 'แพทย์ '),
                          TextSpan(
                            text: '&',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textSecondary, // "&" สีเทา
                            ),
                          ),
                          const TextSpan(text: ' เภสัช'),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Status "พร้อมให้บริการขณะนี้" (สีเทา)
                    Text(
                      'พร้อมให้บริการขณะนี้',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary, // สีเทา
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Count "20 ราย" (สีเทา, มีจุดสีเขียว)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.primary, // จุดสีเขียว
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '20 ราย',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary, // สีเทา
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPharmacyCard(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Card content
    Widget cardContent = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon (สีดำตาม design)
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.local_pharmacy,
              size: 32,
              color: AppColors.textPrimary, // สีดำตาม design
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ร้านยาใกล้คุณ',
                  style: AppTextStyles.heading5.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'จัดส่งภายใน 10 นาที',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'คลินิก / นวดสปา / ฟิสเนส',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          
          // Search Button
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'ค้นหา',
              style: AppTextStyles.buttonSmall.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
    
    // Wrap with width constraint for landscape
    if (isLandscape) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: screenWidth * 0.5, // 50% ของความกว้างหน้าจอในแนวนอน
            child: cardContent,
          ),
        ),
      );
    }
    
    // Portrait: full width
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: cardContent,
    );
  }

  Widget _buildRecommendedSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'แนะนำโดยผู้เชี่ยวชาญ',
                style: AppTextStyles.heading5.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: Text(
                  'เพิ่มเติม',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Horizontal Scrollable List
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 5,
            itemBuilder: (context, index) {
              return Container(
                width: 300,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Placeholder Image
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                      ),
                      child: const Icon(
                        Icons.image,
                        size: 48,
                        color: AppColors.textHint,
                      ),
                    ),
                    
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ชื่อผู้เชี่ยวชาญ',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'คำอธิบายสั้นๆ',
                            style: AppTextStyles.caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInterestingSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'น่าสนใจ',
                style: AppTextStyles.heading5.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: Text(
                  'เพิ่มเติม',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Cards Grid - Fixed width, horizontal scroll
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildInterestingCard(
                'จัดอันดับการบริจาค',
                'สังคม ผู้สูงอายุ',
                '85%',
                '99%',
              ),
              const SizedBox(width: 12),
              _buildInterestingCard(
                'จัดอันดับการบริจาค',
                'สังคม ผู้สูงอายุ',
                '85%',
                '99%',
              ),
              const SizedBox(width: 12),
              _buildInterestingCard(
                'อาสาสมัคร',
                'ชุมชน สิ่งแวดล้อม',
                '72%',
                '88%',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInterestingCard(
    String title,
    String subtitle,
    String value1,
    String value2,
  ) {
    return Container(
      width: 160, // Fixed width - ขนาดคงที่ไม่ปรับตามหน้าจอ
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon - Very Pale Mint Green Circle
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.background, // Very pale mint green #EBF5E0
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.trending_up,
              color: AppColors.textPrimary, // สีดำตาม design
              size: 24,
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Title
          Text(
            title,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 4),
          
          // Subtitle
          Text(
            subtitle,
            style: AppTextStyles.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 8),
          
          // Values
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                value1,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                value2,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Custom Painter for Dotted Circle Border
class DottedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  DottedCirclePainter({
    required this.color,
    this.strokeWidth = 3.0,
    this.dashWidth = 8.0,
    this.dashSpace = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Draw dotted circle - ใช้ ui.Path เพื่อหลีกเลี่ยง conflict กับ latlong2.Path
    final path = ui.Path();
    final circumference = 2 * math.pi * radius;
    final dashLength = dashWidth;
    final gapLength = dashSpace;
    final totalLength = dashLength + gapLength;
    final segments = (circumference / totalLength).floor();
    final angleStep = (2 * math.pi) / segments;

    for (int i = 0; i < segments; i++) {
      final startAngle = i * angleStep;
      final endAngle = startAngle + (dashLength / radius);
      
      path.addArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        endAngle - startAngle,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom Painter for Map Skeleton Grid Pattern
class _MapSkeletonPainter extends CustomPainter {
  final Color color;
  
  _MapSkeletonPainter({required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    
    const tileSize = 50.0; // Size of each "tile" in the grid
    
    // Draw vertical lines
    for (double x = 0; x < size.width; x += tileSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }
    
    // Draw horizontal lines
    for (double y = 0; y < size.height; y += tileSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
    
    // Draw some "road" lines to simulate map features
    final roadPaint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    
    // Diagonal road
    canvas.drawLine(
      Offset(0, size.height * 0.3),
      Offset(size.width, size.height * 0.7),
      roadPaint,
    );
    
    // Horizontal road
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      roadPaint,
    );
    
    // Vertical road
    canvas.drawLine(
      Offset(size.width * 0.4, 0),
      Offset(size.width * 0.4, size.height),
      roadPaint,
    );
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
