import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/widgets.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../health/data/models/health_article_models.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../consultation/presentation/logic/consultation_guard.dart';

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
  
  List<HealthArticle> _recommendedArticles = [];
  List<HealthArticle> _interestingArticles = [];
  bool _isLoadingArticles = true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    // Listen for auth state changes to refresh data (e.g., after login)
    AuthService.instance.addListener(_loadHomeData);
    
    // วัดความสูงของ Header Section หลังจาก build เสร็จ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureHeaderSectionHeight();
    });

    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    debugPrint('HomePage: _loadHomeData called. Reloading articles...');
    
    // Show loading indicator
    setState(() => _isLoadingArticles = true);
    
    try {
      final repository = ServiceLocator.instance.healthArticleRepository;
      
      final currentUserId = ServiceLocator.instance.currentUser?.id;
      
      // Fetch recommended articles
      final recommended = await repository.getAllArticles(
        category: 'แนะนำ', 
        pageSize: 5,
        userId: currentUserId,
      );
      
      // Fetch interesting/popular articles
      final interesting = await repository.getAllArticles(
        category: 'ยอดนิยม', 
        pageSize: 5,
        userId: currentUserId,
      );
      
      if (mounted) {
        setState(() {
          _recommendedArticles = recommended;
          _interestingArticles = interesting;
          _isLoadingArticles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingArticles = false);
      }
    }
  }

  Future<void> _onToggleBookmark(HealthArticle article) async {
    final currentUser = ServiceLocator.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบเพื่อบุ๊กมาร์ก')),
      );
      Navigator.pushNamed(context, '/login'); 
      return;
    }
    
    // Save previous state for revert
    final prevIsBookmarked = article.isBookmarked;
    
    // Optimistic Update
    setState(() {
      final recIndex = _recommendedArticles.indexWhere((a) => a.id == article.id);
      if (recIndex != -1) {
        final current = _recommendedArticles[recIndex];
        _recommendedArticles[recIndex] = current.copyWith(isBookmarked: !current.isBookmarked);
      }
      
      final intIndex = _interestingArticles.indexWhere((a) => a.id == article.id);
      if (intIndex != -1) {
        final current = _interestingArticles[intIndex];
        _interestingArticles[intIndex] = current.copyWith(isBookmarked: !current.isBookmarked);
      }
    });

    try {
      final repository = ServiceLocator.instance.healthArticleRepository;
      final result = await repository.toggleInteraction(
        articleId: article.id,
        userId: currentUser.id,
        type: 'bookmark',
      );

      if (mounted && result['success'] == true) {
        // Update with real state from DB
        final isActive = result['isActive'] as bool;
        setState(() {
          final recIndex = _recommendedArticles.indexWhere((a) => a.id == article.id);
          if (recIndex != -1) {
            _recommendedArticles[recIndex] = _recommendedArticles[recIndex].copyWith(
              isBookmarked: isActive,
              bookmarkCount: result['newCount'] as int,
            );
          }
          final intIndex = _interestingArticles.indexWhere((a) => a.id == article.id);
          if (intIndex != -1) {
            _interestingArticles[intIndex] = _interestingArticles[intIndex].copyWith(
              isBookmarked: isActive,
              bookmarkCount: result['newCount'] as int,
            );
          }
        });
        
        ScaffoldMessenger.of(context).clearSnackBars(); // Clear existing to prevent stacking
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
            content: Text(isActive ? 'บันทึกบทความแล้ว' : 'ยกเลิกการบันทึกแล้ว'),
            duration: const Duration(seconds: 1),
            backgroundColor: isActive ? const Color(0xFFF1AE27) : Colors.grey[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (mounted && result['success'] == false) {
        // Revert on failure
        setState(() {
          final recIndex = _recommendedArticles.indexWhere((a) => a.id == article.id);
          if (recIndex != -1) {
            _recommendedArticles[recIndex] = _recommendedArticles[recIndex].copyWith(isBookmarked: prevIsBookmarked);
          }
          final intIndex = _interestingArticles.indexWhere((a) => a.id == article.id);
          if (intIndex != -1) {
            _interestingArticles[intIndex] = _interestingArticles[intIndex].copyWith(isBookmarked: prevIsBookmarked);
          }
        });
      }
    } catch (e) {
      // Revert or reload on error
      _loadHomeData();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    AuthService.instance.removeListener(_loadHomeData);
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
                                        _isLoadingArticles
                                          ? _buildSectionSkeleton()
                                          : HomeRecommendedSection(
                                              articles: _recommendedArticles,
                                              onMoreTap: () => Navigator.pushNamed(context, '/articles', arguments: 'แนะนำ'),
                                              onItemTap: (article) async {
                                                await Navigator.pushNamed(
                                                  context, 
                                                  '/health/article',
                                                  arguments: article,
                                                );
                                                debugPrint('HomePage: Returning from Recommended Article, reloading data...');
                                                await _loadHomeData();
                                              },
                                              onBookmarkTap: _onToggleBookmark,
                                            ),
                                        const SizedBox(height: 24),
                                        _isLoadingArticles
                                          ? _buildSectionSkeleton()
                                          : HomeInterestingSection(
                                              articles: _interestingArticles,
                                              onMoreTap: () => Navigator.pushNamed(context, '/health/article'),
                                              onItemTap: (article) async {
                                                await Navigator.pushNamed(
                                                  context, 
                                                  '/health/article',
                                                  arguments: article,
                                                );
                                                debugPrint('HomePage: Returning from Interesting Article, reloading data...');
                                                await _loadHomeData();
                                              },
                                              onBookmarkTap: _onToggleBookmark,
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
                                    onHealthTap: () {
                                      if (ServiceLocator.instance.currentUser != null) {
                                        Navigator.pushNamed(context, '/health');
                                      } else {
                                        Navigator.pushNamed(
                                          context, 
                                          '/login',
                                          arguments: '/health',
                                        );
                                      }
                                    },
                                    onProfileTap: () => Navigator.pushNamed(
                                      context, 
                                      '/login',
                                      arguments: '/',
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  HomeConsultationWidget(
                                    onTap: () => ConsultationGuard.startConsultation(context),
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

  Widget _buildSectionSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              width: 180,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 3,
            itemBuilder: (context, index) {
              return Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Container(
                  width: 300,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
