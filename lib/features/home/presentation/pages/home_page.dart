import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/widgets.dart';
import '../widgets/widgets.dart';
import '../../../../services/service_locator.dart';

/// Home Page - Medical App Design
/// Main dashboard for health/medical services
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  double? _dragStartX;
  bool _isDraggingFromLeft = false;
  late ScrollController _scrollController;
  final GlobalKey _headerSectionKey = GlobalKey();
  double _headerSectionHeight = 0;
  bool _showTopBarBorderRadius = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    // วัดความสูงของ Header Section หลังจาก build เสร็จ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureHeaderSectionHeight();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
    
    // วัดความสูงใหม่ถ้ายังไม่ได้ค่า
    if (_headerSectionHeight <= 0) {
      _measureHeaderSectionHeight();
      if (_headerSectionHeight <= 0) return;
    }

    // แสดงมุมโค้งเมื่อเลื่อนลูกกลิ้งลงมาระดับหนึ่ง (เพิ่ม threshold เพื่อไม่ให้สลับเร็วเกินไป)
    final shouldShowBorderRadius = _scrollController.offset > 50;

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
      drawerEnableOpenDragGesture: true,
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, '/test'),
        backgroundColor: AppColors.primary,
        tooltip: 'ทดสอบ WebSocket',
        child: const Icon(
          Icons.bug_report,
          color: AppColors.textOnPrimary,
        ),
      ),
      body: Builder(
        builder: (context) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: (details) => _onHorizontalDragUpdate(details, context),
          onHorizontalDragEnd: (details) => _onHorizontalDragEnd(details, context),
          child: Container(
            color: Colors.transparent, // โปร่งใสเพื่อให้เห็นเนื้อหาด้านหลังมุมโค้ง
            child: SafeArea(
              child: Stack( // ใช้ Stack แทน Column เพื่อให้ Top Bar ลอยทับเนื้อหา
                children: [
                  // Main Content - Scrollable (วางเป็นลำดับแรกเพื่อให้ Header ทับ)
                  Positioned.fill(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Column(
                        children: [
                          // เพิ่มพื้นที่ด้านบนสำหรับ Header ที่ Fixed
                          const SizedBox(height: 70), 
                          Stack(
                            children: [
                              // Background Layer - Map
                              Column(
                                children: [
                                  const SizedBox(
                                    height: 500,
                                    child: HomeMapBackground(),
                                  ),
                                  // Content below map
                                  Container(
                                    width: double.infinity,
                                    color: const Color(0xFFEDF5DA),
                                    child: Column(
                                      children: [
                                        const SizedBox(height: 100),
                                        HomeRecommendedSection(
                                          onMoreTap: () => _showSnackBar(context, 'ดูเพิ่มเติม'),
                                          onItemTap: (index) => _showSnackBar(context, 'เลือกรายการ $index'),
                                        ),
                                        const SizedBox(height: 24),
                                        HomeInterestingSection(
                                          onMoreTap: () => _showSnackBar(context, 'ดูเพิ่มเติม'),
                                          onItemTap: (index) => _showSnackBar(context, 'เลือกรายการ $index'),
                                        ),
                                        const SizedBox(height: 32),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              // Foreground Layer - Header, Consultation, Pharmacy
                              Column(
                                children: [
                                  HomeHeaderSection(
                                    sectionKey: _headerSectionKey,
                                    headerText: ServiceLocator.instance.currentUser != null 
                                      ? 'ข้อมูลสุขภาพ' 
                                      : 'ตรวจสุขภาพ',
                                    onHealthTap: () => Navigator.pushNamed(context, '/health'),
                                    onProfileTap: () => Navigator.pushNamed(
                                      context, 
                                      '/login',
                                      arguments: '/',
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  HomeConsultationWidget(
                                    onTap: () => _showSnackBar(context, 'เปิดหน้าปรึกษาแพทย์'),
                                  ),
                                  const SizedBox(height: 24),
                                  HomePharmacyCard(
                                    onSearchTap: () => _showSnackBar(context, 'ค้นหาร้านยา'),
                                  ),
                                  const SizedBox(height: 24),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Top Navigation Bar - Fixed Overlay
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildTopNavigationBar(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== Helper Methods ====================

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ==================== Drag Gesture Handlers ====================

  void _onHorizontalDragStart(DragStartDetails details) {
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
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, BuildContext context) {
    if (_isDraggingFromLeft && _dragStartX != null && details.globalPosition.dx > _dragStartX! + 50) {
      Scaffold.of(context).openDrawer();
      setState(() {
        _isDraggingFromLeft = false;
        _dragStartX = null;
      });
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details, BuildContext context) {
    if (_isDraggingFromLeft && details.velocity.pixelsPerSecond.dx > 300) {
      Scaffold.of(context).openDrawer();
    }
    setState(() {
      _isDraggingFromLeft = false;
      _dragStartX = null;
    });
  }

  // ==================== Top Navigation Bar ====================

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
        boxShadow: _showTopBarBorderRadius
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: TlzAppTopBar.onPrimary(
        notificationCount: 1,
        searchHintText: 'ค้นหายา ร้านยา หมอ...',
        onQRTap: () => _showSnackBar(context, 'QR Scanner จะเปิดใช้งานเร็วๆ นี้'),
        onNotificationTap: () => _showSnackBar(context, 'การแจ้งเตือนจะเปิดใช้งานเร็วๆ นี้'),
        onCartTap: () => _showSnackBar(context, 'ตะกร้าสินค้าจะเปิดใช้งานเร็วๆ นี้'),
        onResultTap: (item) => _showSnackBar(context, 'เลือก: ${item['title']}'),
      ),
    );
  }
}
