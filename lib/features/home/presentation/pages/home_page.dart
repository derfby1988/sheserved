import 'package:flutter/material.dart';
// Updated Alert System UI and logic - v2
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
import '../../../../services/websocket_service.dart';
import 'package:sheserved/features/video/presentation/pages/emergency_live_page.dart';
import 'dart:async';
import '../../../donation/data/repositories/donation_repository.dart';
import '../../../donation/models/donation_models.dart';
import 'package:geolocator/geolocator.dart';

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
  
  // === Emergency Alert State ===
  StreamSubscription? _emergencySub;
  final List<Map<String, dynamic>> _activeAlerts = [];
  Map<String, dynamic>? _focusedAlert; // รายการที่กำลังโฟกัสบนแผนที่
  List<DonationCategory> _emergencyCategories = []; // เก็บสิทธิอาสาสมัครจากตารางจริง
  final DonationRepository _donationRepo = DonationRepository(Supabase.instance.client);
  final List<String> _dismissedAlertIds = [];
  static const String _kDismissedAlertsKey = 'dismissed_emergency_alert_ids';

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
    _listenForEmergencyAlerts();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    final userId = ServiceLocator.instance.currentUser?.id;
    if (userId != null) {
      WebSocketService().resetConnectionAttempts();
      WebSocketService().connect(userId: userId);
    }
  }

  void _listenForEmergencyAlerts() {
    _emergencySub = WebSocketService().emergencyNotificationStream.listen((data) async {
      if (!mounted) return;
      
      final user = AuthService.instance.currentUser;
      if (user == null) return;

      debugPrint('HomePage: Received emergency notification: $data');

      // 1. Determine relevance based on category and profession
      bool isRelevant = false;
      final categoryId = data['categoryId'] as String? ?? data['category_id'] as String?;
      
      final isThaiMhungAlert = data['isThaiMhungEnabled'] == true || data['is_thai_mhung_enabled'] == true;

      if (categoryId != null) {
        final category = _emergencyCategories.any((c) => c.id == categoryId) 
            ? _emergencyCategories.firstWhere((c) => c.id == categoryId)
            : null;
        
        if (category != null) {
          final userProfessionId = user.professionId;
          if (userProfessionId != null && category.volunteerProfessionIds.contains(userProfessionId)) {
            isRelevant = true;
          }
        }
      }

      // 1.1 Extract or establish timestamp for sorting
      final createdAt = data['created_at'] != null 
          ? DateTime.tryParse(data['created_at'].toString()) ?? DateTime.now()
          : DateTime.now();

      // Initial filtering
      if (!isRelevant && (!isThaiMhungAlert || !user.isThaiMhungEnabled)) {
        debugPrint('HomePage: Alert not relevant to user profession (isRelevant: $isRelevant) or Thai Mhung (isThaiMhungAlert: $isThaiMhungAlert, enabled: ${user.isThaiMhungEnabled})');
        return;
      }

      // 2. Distance-based Proximity Check
      try {
        final lat = _parseDouble(data['latitude']);
        final lng = _parseDouble(data['longitude']);
        
        if (lat != 0 && lng != 0) {
          final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            lat,
            lng,
          );
          debugPrint('HomePage: Distance to incident: ${distance.toStringAsFixed(0)}m, user.alertRadius: ${user.alertRadius}');

          if (isRelevant) {
            // Professionals: Use strictly defined alertRadius
            if (distance > user.alertRadius) {
              debugPrint('HomePage: Alert too far for Professional ($distance m > ${user.alertRadius} m)');
              return;
            }
          } else if (isThaiMhungAlert) {
            // Thai Mhung: Use user's defined alertRadius
            if (distance > user.alertRadius) {
              debugPrint('HomePage: Alert REJECTED - too far for Thai Mhung ($distance m > ${user.alertRadius} m)');
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('HomePage: Error checking distance: $e');
        // Fallback: If location fails, show it anyway if it was relevant
      }

      // 3. Add to alerts list and refresh
      if (mounted) {
        setState(() {
          final alert = Map<String, dynamic>.from(data);
          final videoId = alert['videoId']?.toString() ?? alert['video_id']?.toString() ?? '';
          
          // Check if user has already dismissed this alert
          if (_dismissedAlertIds.contains(videoId)) {
            debugPrint('HomePage: Alert $videoId was previously dismissed, skipping.');
            return;
          }

          // Add normalized createdAt for sorting
          alert['createdAt'] = data['created_at'] != null 
              ? DateTime.tryParse(data['created_at'].toString()) ?? DateTime.now()
              : DateTime.now();
          
          // Prevent duplicates
          if (!_activeAlerts.any((a) => a['videoId'] == alert['videoId'])) {
            _activeAlerts.insert(0, alert);
            
            // Re-sort just in case out-of-order notifications arrive
            _activeAlerts.sort((a, b) {
              final at = a['createdAt'] as DateTime;
              final bt = b['createdAt'] as DateTime;
              return bt.compareTo(at); // Newest first
            });
            
            // Force mini mode to show map and alert
            _isConsultationMini = true;
            _consultPosition = ConsultationPosition.leftCenter;
            _focusedAlert = _activeAlerts.first;
          }
        });
        
        // Refresh home data to potentially show this in popular/interesting section
        _loadHomeData();
      }
    });
  }

  Future<void> _loadActiveAlerts() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    try {
      final videoRepo = ServiceLocator.instance.videoRepository;
      final activeVideos = await videoRepo.getEmergencyVideos();
      
      final List<Map<String, dynamic>> newAlerts = [];
      
      for (var video in activeVideos) {
        bool isRelevant = false;
        final categoryId = video.categoryId;
        
        if (categoryId != null) {
          final category = _emergencyCategories.any((c) => c.id == categoryId) 
              ? _emergencyCategories.firstWhere((c) => c.id == categoryId)
              : null;
          
          if (category != null) {
            final userProfessionId = user.professionId;
            if (userProfessionId != null && category.volunteerProfessionIds.contains(userProfessionId)) {
              isRelevant = true;
            }
          }
        }

        if (isRelevant) {
          final vidId = video.id;
          if (!_dismissedAlertIds.contains(vidId)) {
            newAlerts.add({
              'videoId': vidId,
              'categoryId': video.categoryId,
              'categoryName': _emergencyCategories.any((c) => c.id == video.categoryId) 
                  ? _emergencyCategories.firstWhere((c) => c.id == video.categoryId).name
                  : 'แจ้งเหตุฉุกเฉิน',
              'latitude': video.latitude,
              'longitude': video.longitude,
              'address': video.address,
              'title': video.title,
              'createdAt': video.createdAt,
            });
          }
        }
      }

      if (mounted && newAlerts.isNotEmpty) {
        setState(() {
          for (var alert in newAlerts) {
            if (!_activeAlerts.any((a) => a['videoId'] == alert['videoId'])) {
              _activeAlerts.add(alert);
            }
          }
          
          // Sort by creation: Newest at index 0
          _activeAlerts.sort((a, b) {
            final at = a['createdAt'] as DateTime;
            final bt = b['createdAt'] as DateTime;
            return bt.compareTo(at);
          });

          if (_activeAlerts.isNotEmpty) {
            _focusedAlert = _activeAlerts.first;
            
            // วัดความสูงก่อนย่อถ้ายังไม่ได้วัด
            _captureConsultationHeight();
            
            // Force mini mode automatically if there are alerts
            _isConsultationMini = true;
            _consultPosition = ConsultationPosition.leftCenter;
          }
        });
      }
    } catch (e) {
      debugPrint('HomePage: Error loading active alerts: $e');
    }
  }

  double _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
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
    
    // หากมีเหตุฉุกเฉินอยู่แล้ว ให้ข้ามการโหลดตำแหน่งบันทึก เพื่อไม่ให้ทับซ้อนระบบอัติโนมัติ
    if (_activeAlerts.isNotEmpty) {
      debugPrint('HomePage: Emergency active, skipping saved position load.');
      return;
    }
    
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

      // เพิ่มความชัวร์: หากโหลดเหตุฉุกเฉินเสร็จแล้วพบว่ามีเหตุค้างอยู่ ให้ยกเลิกการโหลดตำแหน่งบันทึก
      if (_activeAlerts.isNotEmpty) {
        debugPrint('HomePage: Emergency detected after delay, skipping saved position bounce.');
        return;
      }

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

    // โหลดรายการแจ้งเหตุที่เคยยกเลิกไปแล้ว
    _loadDismissedAlerts();
  }

  /// โหลดรายการแจ้งเหตุที่ผู้ใช้กดปิดไปแล้ว (จะไม่แสดงซ้ำ)
  Future<void> _loadDismissedAlerts() async {
    final userId = ServiceLocator.instance.currentUser?.id;
    if (userId == null) return;

    try {
      final repo = ServiceLocator.get<UserRepository>();
      final saved = await repo.getUiPreference(userId, _kDismissedAlertsKey);
      if (saved != null && saved.isNotEmpty) {
        setState(() {
          _dismissedAlertIds.clear();
          _dismissedAlertIds.addAll(saved.split(','));
        });
        debugPrint('HomePage: Loaded ${_dismissedAlertIds.length} dismissed alerts.');
      }
    } catch (e) {
      debugPrint('HomePage: Error loading dismissed alerts: $e');
    }
  }

  /// บันทึกการปิดแจ้งเหตุลงฐานข้อมูล
  Future<void> _recordDismissedAlert(String videoId) async {
    if (videoId.isEmpty) return;
    
    if (!_dismissedAlertIds.contains(videoId)) {
      _dismissedAlertIds.add(videoId);
    }

    final userId = ServiceLocator.instance.currentUser?.id;
    if (userId == null) return;

    try {
      final repo = ServiceLocator.get<UserRepository>();
      await repo.saveUiPreference(userId, _kDismissedAlertsKey, _dismissedAlertIds.join(','));
      debugPrint('HomePage: Recorded dismissal for $videoId');
    } catch (e) {
      debugPrint('HomePage: Error saving dismissed alert: $e');
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
    _connectWebSocket();
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
            if (score is num) {
              _healthScore = score.toDouble();
            } else if (score is String) {
              _healthScore = double.tryParse(score) ?? 0;
            } else {
              _healthScore = 0;
            }
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
      
      // Fetch Emergency Categories for filtering rights
      final emergencyCategories = await _donationRepo.getEmergencyCategories();

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
          _emergencyCategories = emergencyCategories;
          _isLoadingArticles = false;
        });
        // โหลดเหตุฉุกเฉินที่กำลังเกิดค้างอยู่
        _loadActiveAlerts();
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
    _emergencySub?.cancel();
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
                                    child: HomeMapBackground(
                                      focusedAlert: _focusedAlert,
                                    ),
                                  ),
                                  Container(
                                    width: double.infinity,
                                    color: const Color(0xFFEDF5DA),
                                    child: Column(
                                      children: [
                                        const SizedBox(height: 110), // เพิ่มพื้นที่เว้นว่างเผื่อ Card แจ้งเตือนที่ลอยอยู่
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
                                    emergencyCount: _activeAlerts.length,
                                    onEmergencyTap: () {
                                      if (_activeAlerts.isNotEmpty) {
                                        // นำทางไปยังเหตุการณ์แรกที่มีการแจ้งเตือน
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => EmergencyLivePage(videoId: _activeAlerts.first['videoId']),
                                          ),
                                        );
                                      }
                                    },
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
                                       arguments: '/profile',
                                     ),
                                  ),
                                  const SizedBox(height: 16),
                                  // เมื่ออยู่ในโหมด center: แสดงปุ่มปกติ
                                  // เมื่ออยู่มุม: แสดง Placeholder เพื่อรักษาขนาดแผนที่
                                  if (_isConsultationMini) 
                                    SizedBox(
                                      key: _consultationKey,
                                      height: _savedConsultationHeight > 0 ? _savedConsultationHeight : 280,
                                      child: const SizedBox(height: 90), // Placeholder internal
                                    )
                                  else
                                    GestureDetector(
                                      onLongPressStart: _onConsultationLongPressStart,
                                      onLongPressMoveUpdate: _onConsultationLongPressMoveUpdate,
                                      onLongPressEnd: _onConsultationLongPressEnd,
                                      child: HomeConsultationWidget(
                                        key: _consultationKey,
                                      ),
                                    ),
                                  const SizedBox(height: 24),
                                  HomePharmacyCard(
                                    key: _pharmacyKey,
                                    onSearchTap: () => _showSnackBar(context, 'ค้นหาร้านยา'),
                                  ),
                                  const SizedBox(height: 24),
                                ],
                              ),
                              // Floating Stacked Alerts - Layered above Pharmacy but below Consultation
                              if (_activeAlerts.isNotEmpty)
                                Positioned(
                                  top: (_headerSectionHeight / 2) + _mapHeight - 110,
                                  left: 16,
                                  right: 16,
                                  child: _buildStackedAlerts(),
                                ),
                              // Topmost Layer - Floating Mini Consultation (อยู่เหนือ Header/Pharmacy/Alerts)
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

                  // Emergency Overlays moved inside map Stack
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
                    color: AppColors.textSecondary.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
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
                  color: Colors.black.withValues(alpha: 0.15),
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

  // Removed _buildActiveAlertsOverlay as it is now integrated into the map Stack

  Widget _buildEmergencyAlertCard(Map<String, dynamic> alert, {int index = 0, int total = 1}) {
    final videoId = alert['videoId']?.toString() ?? '';
    
    return Dismissible(
      key: Key('alert_$videoId'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          // Swipe Left -> Close
          _recordDismissedAlert(videoId);
          setState(() {
            _activeAlerts.removeAt(index);
            if (_activeAlerts.isEmpty) {
              _focusedAlert = null;
            } else {
              _focusedAlert = _activeAlerts.first;
            }
          });
          return true;
        } else if (direction == DismissDirection.startToEnd) {
          // Swipe Right -> View Incident
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EmergencyLivePage(videoId: videoId),
            ),
          );
          return false; // Don't remove it visually from the list yet
        }
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: Colors.green.withOpacity(0.5),
        child: const Icon(Icons.emergency, color: Colors.white, size: 32),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.black.withOpacity(0.3),
        child: const Icon(Icons.close, color: Colors.white, size: 32),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Stack(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EmergencyLivePage(videoId: videoId),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.red.shade800.withOpacity(0.95),
                        Colors.red.shade600.withOpacity(0.95),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 24), // Space for Close button
                          Expanded(
                            child: Text(
                              '🚨 ${alert['categoryName'] ?? 'แจ้งเหตุฉุกเฉินด่วน!'}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // "Emergency" status label
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: const Text(
                              'เหตุฉุกเฉิน',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Text(
                          alert['address'] ?? '',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (total > 1) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(width: 24),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${total - index}/$total',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Close button (Top Left)
            Positioned(
              top: 2,
              left: 2,
              child: GestureDetector(
                onTap: () {
                  _recordDismissedAlert(videoId);
                  setState(() {
                    _activeAlerts.removeAt(index);
                    if (_activeAlerts.isEmpty) {
                      _focusedAlert = null;
                    } else {
                      _focusedAlert = _activeAlerts.first;
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStackedAlerts() {
    final total = _activeAlerts.length;
    // Show top card and edges of 2 cards behind it
    const int maxVisible = 3;
    final displayCount = total > maxVisible ? maxVisible : total;

    return SizedBox(
      height: 100, // Card height + stack offset
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: List.generate(displayCount, (i) {
          // Bottom-up: Oldest in stack children should be index 0
          // But our _activeAlerts[0] is LATEST.
          // So children = [ _activeAlerts[2], _activeAlerts[1], _activeAlerts[0] ]
          // i=0 is bottom-most in Stack => index = displayCount - 1
          final visualRank = displayCount - 1 - i; 
          final alertIndex = visualRank; 
          final alert = _activeAlerts[alertIndex];
          
          return Positioned(
            top: i * 8.0,
            left: i * 4.0,
            right: i * 4.0,
            child: _buildEmergencyAlertCard(alert, index: alertIndex, total: total),
          );
        }),
      ),
    );
  }
}
