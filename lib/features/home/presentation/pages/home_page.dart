import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/widgets.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../health/data/models/health_article_models.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../consultation/presentation/logic/consultation_guard.dart';
import '../../../auth/data/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ตำแหน่งที่ปุ่มปรึกษาสามารถ Snap ไปวางได้ (8 ตำแหน่ง + กลาง)
enum ConsultationPosition {
  center,
  // 4 มุม
  topLeft, topRight, bottomLeft, bottomRight,
  // 4 กลางขอบ
  topCenter, bottomCenter, leftCenter, rightCenter,
}

/// Preference key สำหรับบันทึกใน Supabase
const _kConsultPosKey = 'home_consultation_position';

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
  final GlobalKey _consultationKey = GlobalKey();
  final GlobalKey _pharmacyKey = GlobalKey();
  final GlobalKey _mapAreaKey = GlobalKey();
  double _headerSectionHeight = 0;
  double _consultationHeight = 0;
  double _pharmacyHeight = 0;
  double _mapHeight = 500; // ค่าเริ่มต้น จะถูกอัปเดตหลัง build
  bool _showTopBarBorderRadius = false;

  // === Snap-to-Corner State ===
  ConsultationPosition _consultPosition = ConsultationPosition.center;
  bool _isConsultationMini = false; // เปลี่ยนจาก getter เป็นตัวแปรเพื่อควบคุมแยกต่างหาก
  Offset? _dragOffset; // ตำแหน่งชั่วคราวขณะลาก
  bool _isDraggingConsultation = false;
  double _savedConsultationHeight = 0; // บันทึกความสูงก่อนย่อ เพื่อใช้เป็น Placeholder
  double _spinTurns = 0.0; // บันทึกรอบการหมุนของ widget
  
  List<HealthArticle> _recommendedArticles = [];
  List<HealthArticle> _interestingArticles = [];
  bool _isLoadingArticles = true;

  // Pagination for Recommended section
  int _recommendedPage = 1;
  bool _hasMoreRecommended = true;
  bool _isLoadingMoreRecommended = false;

  // Pagination for Interesting section
  int _interestingPage = 1;
  bool _hasMoreInteresting = true;
  bool _isLoadingMoreInteresting = false;

  double? _healthScore; // Null หมายถึง Guest หรือยังโหลดไม่เสร็จ

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    // Listen for auth state changes to refresh data and re-load preferences
    AuthService.instance.addListener(_onAuthChanged);
    
    // Initial load of health score if already logged in
    _loadHealthScore();
    
    // วัดความสูงของ Header Section หลังจาก build เสร็จ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureHeaderSectionHeight();
      // โหลดตำแหน่ง consultation หลังจาก build แรกเสร็จ (เพื่อให้วัดความสูงได้)
      _loadConsultationPosition();
    });

    _loadHomeData();
  }

  // === Snap-to-Corner Helpers ===
  
  /// คำนวณพิกัดจริงของปุ่มเมื่ออยู่ในแต่ละตำแหน่ง
  Offset _getSnapOffset(ConsultationPosition pos, Size mapSize) {
    const double miniSize = 90.0;
    const double margin = 12.0;
    final double halfW = (mapSize.width - miniSize) / 2;
    final double halfH = (mapSize.height - miniSize) / 2;
    switch (pos) {
      case ConsultationPosition.center:
        return Offset(halfW, halfH);
      case ConsultationPosition.topLeft:
        return const Offset(margin, margin);
      case ConsultationPosition.topRight:
        return Offset(mapSize.width - miniSize - margin, margin);
      case ConsultationPosition.bottomLeft:
        return Offset(margin, mapSize.height - miniSize - margin);
      case ConsultationPosition.bottomRight:
        return Offset(mapSize.width - miniSize - margin, mapSize.height - miniSize - margin);
      case ConsultationPosition.topCenter:
        return Offset(halfW, margin);
      case ConsultationPosition.bottomCenter:
        return Offset(halfW, mapSize.height - miniSize - margin);
      case ConsultationPosition.leftCenter:
        return Offset(margin, halfH);
      case ConsultationPosition.rightCenter:
        return Offset(mapSize.width - miniSize - margin, halfH);
    }
  }

  /// หาตำแหน่งที่ใกล้ที่สุดจากตำแหน่งที่ปล่อยนิ้ว (จาก 8 ตำแหน่ง)
  ConsultationPosition _findNearestCorner(Offset position, Size mapSize) {
    const double miniSize = 90.0;
    final double halfW = mapSize.width / 2;
    final double halfH = mapSize.height / 2;

    final Map<ConsultationPosition, Offset> targets = {
      ConsultationPosition.topLeft:      const Offset(miniSize / 2, miniSize / 2),
      ConsultationPosition.topRight:     Offset(mapSize.width - miniSize / 2, miniSize / 2),
      ConsultationPosition.bottomLeft:   Offset(miniSize / 2, mapSize.height - miniSize / 2),
      ConsultationPosition.bottomRight:  Offset(mapSize.width - miniSize / 2, mapSize.height - miniSize / 2),
      ConsultationPosition.topCenter:    Offset(halfW, miniSize / 2),
      ConsultationPosition.bottomCenter: Offset(halfW, mapSize.height - miniSize / 2),
      ConsultationPosition.leftCenter:   Offset(miniSize / 2, halfH),
      ConsultationPosition.rightCenter:  Offset(mapSize.width - miniSize / 2, halfH),
    };

    double minDist = double.infinity;
    ConsultationPosition nearest = ConsultationPosition.topRight;
    for (final entry in targets.entries) {
      final dist = (position - entry.value).distance;
      if (dist < minDist) {
        minDist = dist;
        nearest = entry.key;
      }
    }
    return nearest;
  }

  /// วัดและเก็บความสูงของ consultation widget ก่อนย่อ
  void _captureConsultationHeight() {
    if (_savedConsultationHeight > 0) return; // วัดแล้ว
    final RenderBox? box = _consultationKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      _savedConsultationHeight = box.size.height;
      debugPrint('HomePage: Captured consultationHeight = $_savedConsultationHeight');
    }
  }

  void _onConsultationLongPressStart(LongPressStartDetails details) {
    // บันทึกความสูงปัจจุบันก่อนย่อ
    _captureConsultationHeight();
    
    // หาตำแหน่ง map area
    final RenderBox? mapBox = _mapAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (mapBox == null || !mapBox.hasSize) return;
    
    final mapTopLeft = mapBox.localToGlobal(Offset.zero);
    final localPos = details.globalPosition - mapTopLeft;
    
    setState(() {
      _isConsultationMini = true;
      _isDraggingConsultation = true;
      _dragOffset = Offset(
        localPos.dx - 45,
        localPos.dy - 45,
      );
    });
  }

  void _onConsultationLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final RenderBox? mapBox = _mapAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (mapBox == null || !mapBox.hasSize) return;
    
    final mapTopLeft = mapBox.localToGlobal(Offset.zero);
    final localPos = details.globalPosition - mapTopLeft;
    const double miniSize = 90.0;
    
    setState(() {
      _dragOffset = Offset(
        (localPos.dx - miniSize / 2).clamp(0, mapBox.size.width - miniSize),
        (localPos.dy - miniSize / 2).clamp(0, mapBox.size.height - miniSize),
      );
    });
  }

  void _onConsultationLongPressEnd(LongPressEndDetails details) {
    final RenderBox? mapBox = _mapAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (mapBox == null || !mapBox.hasSize) return;
    
    final mapTopLeft = mapBox.localToGlobal(Offset.zero);
    final localPos = details.globalPosition - mapTopLeft;
    
    final nearest = _findNearestCorner(localPos, mapBox.size);
    debugPrint('HomePage: Snap to → ${nearest.name}');
    
    // 1) Snap ทันที (optimistic) – ไม่รอ DB
    setState(() {
      _isDraggingConsultation = false;
      _dragOffset = null;
      if (_consultPosition != nearest) {
        // ให้หมุน 1 รอบเมื่อมีการย้ายตำแหน่งเปลี่ยนไป
        _spinTurns += 1.0; 
      }
      _consultPosition = nearest;
    });
    
    // 2) Save ลง DB ในพื้นหลัง + เขย่าเมื่อ confirm
    _saveAndShake(nearest);
  }
  
  /// กดปุ่ม X หรือ double tap: คืนสู่ตำแหน่งกลาง
  void _resetConsultationToCenter() async {
    debugPrint('HomePage: Reset to center');
    // Save center ลง DB ในพื้นหลัง
    _saveConsultationPosition(ConsultationPosition.center);

    setState(() {
      if (_consultPosition != ConsultationPosition.center) {
        // ให้หมุนกลับหลัง 1 รอบเมื่อถูกรีเซต
        _spinTurns -= 1.0;
      }
      _consultPosition = ConsultationPosition.center;
    });

    // รอให้มันหมุนกลิ้งมาถึงตรงกลาง (1000ms) จากนั้นค่อยเปลี่ยนเป็น Widget ตัวใหญ่
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;

    setState(() {
      _isConsultationMini = false;
      _savedConsultationHeight = 0;
    });
    // วัดความสูงใหม่หลังจากกลับเป็น Full Mode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureHeaderSectionHeight();
    });
  }

  /// Save → รอ confirm → เขย่าปุ่ม 3 จังหวะเป็นการยืนยัน
  Future<void> _saveAndShake(ConsultationPosition pos) async {
    final ok = await _saveConsultationPosition(pos);
    if (!mounted || !ok) return;
    
    // เขย่า 3 จังหวะ: ขยาย → หด → ขยาย → คืน
    for (int i = 0; i < 3; i++) {
      if (!mounted) return;
      setState(() => _snapConfirmed = true);
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      setState(() => _snapConfirmed = false);
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // flag แจ้งว่า DB confirm แล้ว (ใช้แสดงเขย่า)
  bool _snapConfirmed = false;

  // =====================================================
  // UI Preference Persistence
  // =====================================================

  /// โหลดตำแหน่ง consultation จาก Supabase (เฉพาะ user mode)
  /// Flow: center ก่อน → วัดความสูง → delay → bounce ไปตำแหน่งที่บันทึกไว้
  Future<void> _loadConsultationPosition() async {
    // ✅ ใช้ ServiceLocator ตาม auth_data_guidelines
    final userId = ServiceLocator.instance.currentUser?.id;
    debugPrint('HomePage: _loadConsultationPosition userId=$userId');
    
    if (userId == null) {
      // Guest mode → center เสมอ
      if (mounted && _consultPosition != ConsultationPosition.center) {
        setState(() {
          _consultPosition = ConsultationPosition.center;
          _isConsultationMini = false;
        });
      }
      return;
    }

    // เริ่มจาก center (full-size) ก่อนเสมอ
    if (mounted && _consultPosition != ConsultationPosition.center) {
      setState(() {
        _consultPosition = ConsultationPosition.center;
        _isConsultationMini = false;
        _savedConsultationHeight = 0;
      });
    }

    try {
      final repo = UserRepository(Supabase.instance.client);
      debugPrint('HomePage: Querying user_ui_preferences for key=$_kConsultPosKey ...');
      final saved = await repo.getUiPreference(userId, _kConsultPosKey);
      debugPrint('HomePage: DB returned preference_value=$saved');
      
      if (!mounted) return;
      if (saved == null || saved == 'center') {
        debugPrint('HomePage: No saved position or center → stay center');
        return;
      }
      
      final pos = ConsultationPosition.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => ConsultationPosition.center,
      );
      
      if (pos == ConsultationPosition.center) return;
      
      // วัดความสูง consultation widget ก่อนย่อ
      _captureConsultationHeight();

      // แสดง center สักพัก → แล้ว bounce ไปตำแหน่งที่บันทึกไว้
      debugPrint('HomePage: Will bounce to $pos after 2000ms ...');
      await Future.delayed(const Duration(milliseconds: 2000));
      if (!mounted) return;

      // เริ่มสร้าง widget ตัวเล็กขึ้นมาตรงกลาง
      setState(() {
        _isConsultationMini = true;
        _consultPosition = ConsultationPosition.center;
      });
      
      // รอ 1 frame ให้ widget ปรากฏ จากนั้นจึงสั่งกลิ้ง
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;
        setState(() {
          _consultPosition = pos;
          _spinTurns += 2.0; // หมุนเท่ ๆ 2 รอบตอนที่เปิดหน้า Home
        });
        debugPrint('HomePage: ✓ Bounced to saved position → $pos');
      });

    } catch (e) {
      debugPrint('HomePage: ❌ _loadConsultationPosition error: $e');
    }
  }

  /// บันทึกตำแหน่ง consultation ลง Supabase
  /// คืน true = สำเร็จ, false = ล้มเหลว
  /// ✅ ใช้ ServiceLocator ตาม auth_data_guidelines
  Future<bool> _saveConsultationPosition(ConsultationPosition pos) async {
    final userId = ServiceLocator.instance.currentUser?.id;
    debugPrint('HomePage: _saveConsultationPosition userId=$userId pos=${pos.name}');
    if (userId == null) {
      debugPrint('HomePage: Guest mode → skip save');
      return true; // Guest: ถือว่าสำเร็จ
    }
    try {
      final repo = UserRepository(Supabase.instance.client);
      await repo.saveUiPreference(userId, _kConsultPosKey, pos.name);
      debugPrint('HomePage: ✓ Saved to DB → ${pos.name}');
      return true;
    } catch (e) {
      debugPrint('HomePage: ❌ _saveConsultationPosition FAILED: $e');
      return false;
    }
  }

  /// เรียกเมื่อ auth state เปลี่ยน (login / logout)
  void _onAuthChanged() {
    debugPrint('HomePage: _onAuthChanged fired, userId=${ServiceLocator.instance.currentUser?.id}');
    _loadConsultationPosition();
    _loadHealthScore();
    _loadHomeData();
  }

  /// โหลดคะแนนสุขภาพของผู้ใช้
  Future<void> _loadHealthScore() async {
    final currentUser = ServiceLocator.instance.currentUser;
    if (currentUser == null) {
      if (mounted) setState(() => _healthScore = null);
      return;
    }

    try {
      final repo = ServiceLocator.get<UserRepository>();
      final profile = await repo.getConsumerProfile(currentUser.id);
      if (mounted && profile != null) {
        final score = profile.healthInfo?['health_score'];
        setState(() {
          if (score != null) {
            _healthScore = (score as num).toDouble();
          } else {
            _healthScore = 0;
          }
        });
      }
    } catch (e) {
      debugPrint('HomePage: Error loading health score: $e');
    }
  }

  Future<void> _loadHomeData() async {
    debugPrint('HomePage: _loadHomeData called. Reloading articles...');
    
    // Show loading indicator
    setState(() {
      _isLoadingArticles = true;
      _recommendedPage = 1;
      _hasMoreRecommended = true;
      _isLoadingMoreRecommended = false;
      _interestingPage = 1;
      _hasMoreInteresting = true;
      _isLoadingMoreInteresting = false;
    });
    
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
          if (recommended.length < 5) {
            _hasMoreRecommended = false;
          }
          if (interesting.length < 5) {
            _hasMoreInteresting = false;
          }
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

  Future<void> _loadMoreRecommended() async {
    if (_isLoadingMoreRecommended || !_hasMoreRecommended) return;

    if (mounted) {
      setState(() {
        _isLoadingMoreRecommended = true;
      });
    }

    try {
      _recommendedPage++;
      final repository = ServiceLocator.instance.healthArticleRepository;
      final currentUserId = ServiceLocator.instance.currentUser?.id;

      final newArticles = await repository.getAllArticles(
        category: 'แนะนำ',
        page: _recommendedPage,
        pageSize: 5,
        userId: currentUserId,
      );

      if (mounted) {
        setState(() {
          if (newArticles.length < 5) {
            _hasMoreRecommended = false;
          }
          _recommendedArticles.addAll(newArticles);
          _isLoadingMoreRecommended = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMoreRecommended = false;
        });
      }
    }
  }

  Future<void> _loadMoreInteresting() async {
    if (_isLoadingMoreInteresting || !_hasMoreInteresting) return;

    if (mounted) {
      setState(() {
        _isLoadingMoreInteresting = true;
      });
    }

    try {
      _interestingPage++;
      final repository = ServiceLocator.instance.healthArticleRepository;
      final currentUserId = ServiceLocator.instance.currentUser?.id;

      final newArticles = await repository.getAllArticles(
        category: 'ยอดนิยม',
        page: _interestingPage,
        pageSize: 5,
        userId: currentUserId,
      );

      if (mounted) {
        setState(() {
          if (newArticles.length < 5) {
            _hasMoreInteresting = false;
          }
          _interestingArticles.addAll(newArticles);
          _isLoadingMoreInteresting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMoreInteresting = false;
        });
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
    AuthService.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _measureHeaderSectionHeight() {
    if (!mounted) return;
    final RenderBox? headerBox = _headerSectionKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? consultBox = _consultationKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? pharmacyBox = _pharmacyKey.currentContext?.findRenderObject() as RenderBox?;

    if (headerBox != null && headerBox.hasSize) {
      _headerSectionHeight = headerBox.size.height;
    }
    if (consultBox != null && consultBox.hasSize) {
      _consultationHeight = consultBox.size.height;
    }
    if (pharmacyBox != null && pharmacyBox.hasSize) {
      _pharmacyHeight = pharmacyBox.size.height;
    }

    // คำนวณความสูงแผนที่อัตโนมัติ:
    // Map ถูก shift ลงมาด้วย SizedBox(headerHeight / 2) แล้ว
    // ดังนั้น mapHeight = ระยะจากกึ่งกลาง Header ถึงกึ่งกลาง Pharmacy
    // = (headerHeight / 2) + spacing(16) + consultHeight + spacing(24) + (pharmacyHeight / 2)
    if (_headerSectionHeight > 0 && _consultationHeight > 0 && _pharmacyHeight > 0) {
      final calculatedHeight = (_headerSectionHeight / 2) + 16 + _consultationHeight + 24 + (_pharmacyHeight / 2);
      if (calculatedHeight > 0 && calculatedHeight != _mapHeight) {
        setState(() {
          _mapHeight = calculatedHeight;
        });
      }
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
      body: Builder(
        builder: (context) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: (details) => _onHorizontalDragUpdate(details, context),
          onHorizontalDragEnd: (details) => _onHorizontalDragEnd(details, context),
          child: Container(
            color: AppColors.primary, 
            child: SafeArea(
              child: Stack(
                children: [
                  // พื้นหลังสี primary กันช่องว่างเมื่อ overscroll
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 300,
                    child: Container(color: AppColors.primary),
                  ),
                  Positioned.fill(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Column(
                        children: [
                          const SizedBox(height: 70), 
                          Stack(
                            children: [
                              Column(
                                children: [
                                  // เลื่อน Map ลงมาเริ่มที่กึ่งกลาง HeaderSection
                                  SizedBox(height: _headerSectionHeight / 2),
                                  SizedBox(
                                    key: _mapAreaKey,
                                    height: _mapHeight,
                                    child: const HomeMapBackground(),
                                  ),
                                  Container(
                                    width: double.infinity,
                                    color: const Color(0xFFEDF5DA),
                                    child: Column(
                                      children: [
                                        const SizedBox(height: 100),
                                        // Article Sections with separate loading state
                                        _isLoadingArticles
                                          ? _buildSectionSkeleton()
                                          : RecommendedArticleSection(
                                              articles: _recommendedArticles,
                                              hasMore: _hasMoreRecommended,
                                              isLoadingMore: _isLoadingMoreRecommended,
                                              onLoadMore: _loadMoreRecommended,
                                              onMoreTap: () => Navigator.pushNamed(context, '/articles', arguments: 'แนะนำ'),
                                              onItemTap: (article) async {
                                                await Navigator.pushNamed(
                                                  context, 
                                                  '/health/article',
                                                  arguments: article,
                                                );
                                                await _loadHomeData();
                                              },
                                              onBookmarkTap: _onToggleBookmark,
                                            ),
                                        const SizedBox(height: 24),
                                        _isLoadingArticles
                                          ? _buildSectionSkeleton()
                                          : HomeInterestingSection(
                                              articles: _interestingArticles,
                                              hasMore: _hasMoreInteresting,
                                              isLoadingMore: _isLoadingMoreInteresting,
                                              onLoadMore: _loadMoreInteresting,
                                              onMoreTap: () => Navigator.pushNamed(context, '/articles', arguments: 'น่าสนใจ'),
                                              onItemTap: (article) async {
                                                await Navigator.pushNamed(
                                                  context, 
                                                  '/health/article',
                                                  arguments: article,
                                                );
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
                              // Foreground Layer - Actions (Consultation, Pharmacy) are NOT blocked by article loading
                              Column(
                                children: [
                                  HomeHeaderSection(
                                    sectionKey: _headerSectionKey,
                                    isLoading: ServiceLocator.instance.currentUser != null && _healthScore == null,
                                    headerText: ServiceLocator.instance.currentUser != null 
                                      ? (_healthScore != null 
                                          ? 'คะแนนสุขภาพ ${_healthScore!.toInt()}%' 
                                          : 'คะแนนสุขภาพ --%')
                                      : 'ตรวจสุขภาพ',
                                    onHealthTap: () async {
                                      if (ServiceLocator.instance.currentUser != null) {
                                        await Navigator.pushNamed(context, '/health');
                                        _loadHealthScore();
                                      } else {
                                        await Navigator.pushNamed(
                                          context, 
                                          '/login',
                                          arguments: '/health',
                                        );
                                        _loadHealthScore();
                                      }
                                    },
                                    onProfileTap: () => Navigator.pushNamed(
                                      context, 
                                      '/login',
                                      arguments: '/',
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // เมื่ออยู่ในโหมด center: แสดงปุ่มปกติ
                                  // เมื่ออยู่มุม: แสดง Placeholder เพื่อรักษาขนาดแผนที่
                                  if (!_isConsultationMini)
                                    GestureDetector(
                                      onLongPressStart: _onConsultationLongPressStart,
                                      onLongPressMoveUpdate: _onConsultationLongPressMoveUpdate,
                                      onLongPressEnd: _onConsultationLongPressEnd,
                                      child: HomeConsultationWidget(
                                        key: _consultationKey,
                                        onTap: () => ConsultationGuard.startConsultation(context),
                                      ),
                                    )
                                  else
                                    // Placeholder: รักษาความสูงเดิมเพื่อไม่ให้แผนที่หดตัว
                                    SizedBox(
                                      key: _consultationKey,
                                      height: _savedConsultationHeight > 0 ? _savedConsultationHeight : 280,
                                    ),
                                  const SizedBox(height: 24),
                                  HomePharmacyCard(
                                    key: _pharmacyKey,
                                    onSearchTap: () => _showSnackBar(context, 'ค้นหาร้านยา'),
                                  ),
                                  const SizedBox(height: 24),
                                ],
                              ),
                              // Topmost Layer - Floating Mini Consultation (อยู่เหนือ Header/Pharmacy)
                              if (_isConsultationMini || _isDraggingConsultation)
                                _buildFloatingConsultation(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
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

  // ==================== Floating Consultation Widget ====================

  Widget _buildFloatingConsultation() {
    const double miniSize = 90.0;

    // คำนวณขนาด map area จริงจาก RenderBox
    final RenderBox? mapBox = _mapAreaKey.currentContext?.findRenderObject() as RenderBox?;
    final mapWidth = mapBox?.size.width ?? MediaQuery.of(context).size.width;
    final mapSize = Size(mapWidth, _mapHeight);
    
    // Map อยู่ห่างจากขอบ Inner Stack ลงมา = headerHeight / 2
    final double mapTopOffset = _headerSectionHeight / 2;

    // ขณะลาก: ใช้ Positioned ตรง ไม่มี Animation เพื่อให้ติดนิ้ว
    if (_isDraggingConsultation && _dragOffset != null) {
      return Positioned(
        left: _dragOffset!.dx,
        top: _dragOffset!.dy + mapTopOffset,
        child: _buildMiniConsultationBody(miniSize),
      );
    }

    // เมื่อ Snap แล้ว: AnimatedPositioned เป็น direct child ของ Stack
    final snapOffset = _getSnapOffset(_consultPosition, mapSize);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutBack,
      left: snapOffset.dx,
      top: snapOffset.dy + mapTopOffset,
      child: AnimatedRotation( // เพิ่ม AnimatedRotation ครอบชั้นใน
        turns: _spinTurns,
        duration: const Duration(milliseconds: 1000),
        curve: Curves.easeOutBack,
        child: _buildMiniConsultationBody(miniSize),
      ),
    );
  }

  Widget _buildMiniConsultationBody(double miniSize) {
    return AnimatedScale(
      scale: _snapConfirmed ? 1.35 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: GestureDetector(
        onLongPressStart: _onConsultationLongPressStart,
        onLongPressMoveUpdate: _onConsultationLongPressMoveUpdate,
        onLongPressEnd: _onConsultationLongPressEnd,
        onDoubleTap: _resetConsultationToCenter,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            HomeConsultationWidget(
              isMini: true,
              overrideSize: miniSize,
              onTap: () => ConsultationGuard.startConsultation(context),
            ),
            // ปุ่ม X เล็กๆ สำหรับคืนตำแหน่งกลาง
            Positioned(
              top: -4,
              right: -4,
              child: GestureDetector(
                onTap: _resetConsultationToCenter,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withOpacity(0.8),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
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
