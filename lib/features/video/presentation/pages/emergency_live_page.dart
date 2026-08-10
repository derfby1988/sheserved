import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sheserved/features/home/presentation/widgets/background_permission_dialog.dart';
import '../../../../services/location_tracking_service.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/constants/app_text_styles.dart';
import 'widgets/yield_way_map_dialog.dart';
import '../../../../config/sync_config.dart';
import '../../../../config/app_config.dart';
import '../../../../services/websocket_service.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../emergency/data/repositories/emergency_dead_man_repository.dart';
import '../../../donation/models/donation_models.dart';
import '../../../donation/data/repositories/donation_repository.dart';
import '../../../donation/presentation/pages/donation_create_page.dart';  // ✅ เพิ่ม import

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../models/video_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'widgets/live_view_widget.dart';
import 'widgets/thai_mhung_ruler_gallery_widget.dart';
import 'widgets/glassmorphism_video_controls.dart';
import 'widgets/incident_report_widget.dart';
import 'widgets/donation_sheet_widget.dart';
import 'widgets/thai_mhung_gallery_widget.dart';
import 'widgets/emergency_map_section.dart';
import 'widgets/emergency_ui_overlay.dart';
import 'widgets/floating_back_button.dart';
import 'widgets/emergency_chat_widget.dart';
import 'widgets/rescue_accept_panel_widget.dart';
import 'widgets/rescue_control_panel_widget.dart';
import 'widgets/triage_sheet_widget.dart';
import '../../data/repositories/victim_repository.dart';
import '../../models/triage_models.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:intl/intl.dart';

// Part files for logic
part 'parts/emergency_reporting_logic.dart';
part 'parts/emergency_websocket_logic.dart';
part 'parts/emergency_navigation_logic.dart';

/// หน้า Emergency Live - ออกแบบตาม Figma
/// แสดงวิดีโอไลฟ์ + แผนที่ GPS + ปุ่มโต้ตอบ
class EmergencyLivePage extends StatefulWidget {
  final String? videoId;
  final String? responseId;
  final bool autoOpenChat;

  const EmergencyLivePage({super.key, this.videoId, this.responseId, this.autoOpenChat = false});

  @override
  State<EmergencyLivePage> createState() => _EmergencyLivePageState();
}

class _EmergencyLivePageState extends State<EmergencyLivePage> with TickerProviderStateMixin {
  // === State Variables ===
  final GlobalKey _trendingPanelKey = GlobalKey();
  double _trendingPanelBottom = 0;
  bool _isOverlayVisible = false;
  int _selectedTab = 0;
  int _triageBadgeCount = 0;
  final VictimRepository _victimRepository = VictimRepository();
  int _viewerCount = 0;
  int _likeCount = 0;
  bool _hasLiked = false;    // ✅ [Support Analytics] DB Toggle state
  int _likeTrigger = 0;      // ✅ [Support Analytics] increments to force chart refresh
  int _yieldWayCount = 0;
  int _yieldWayNotifiedCount = 0; // ✅ จำนวนผู้ที่ระบบแจ้งเตือนให้ทางไป (สำหรับคำนวณกราฟ)
  bool _isYieldPulsing = false; // ✅ สำหรับแสดง pulse effect บนแผนที่
  // ✅ รองรับหลายคำร้องต่อวิดีโอเดียว: Map<requestId, currentAmount>
  Map<String, double> _requestTotals = {};
  // เก็บรายการคำร้องที่ดึงมาสำหรับแสดงใน ActionButtonsWidget
  List<DonationRequest> _activeDonationRequests = [];
  int _activeRequestIndex = 0;
  // เก็บยอดรวมสำหรับแสดง (หากไม่มีคำร้อง active ใดเลยให้แสดง 0)
  double get _donationTotal {
    if (_activeDonationRequests.isEmpty) return 0.0;
    final req = _activeDonationRequests[_activeRequestIndex.clamp(0, _activeDonationRequests.length - 1)];
    return _requestTotals[req.id] ?? req.currentAmount ?? 0.0;
  }
  RealtimeChannel? _supabaseInteractionSub;
  RealtimeChannel? _emergencyHealthSessionSub;
  RealtimeChannel? _emergencyHealthTokenSub;
  LatLng? _userLocation;
  bool _isConnected = true;
  String? _currentVideoId;
  Video? _currentVideo;
  late AnimationController _liveBlinkController;
  late AnimationController _pulseController;
  GoogleMapController? _mapController;
  
  StreamSubscription? _connectionSub;
  StreamSubscription? _interactionSub;
  StreamSubscription? _progressSub;
  StreamSubscription? _rescueIncomingSub;
  StreamSubscription? _videoStatusSub;
  StreamSubscription? _locationSub;
  StreamSubscription? _myLocationStreamSub;
  StreamSubscription? _emergencySub;
  StreamSubscription? _compassSub;
  StreamSubscription? _viewerCountSub;
  StreamSubscription? _yieldWayAlertSub;
  StreamSubscription? _emergencyHealthSensorAlertSub;
  StreamSubscription? _emergencyHealthDeadManReminderSub;
  StreamSubscription? _emergencyHealthDeadManTriggeredSub;
  StreamSubscription? _photoBlurSub;
  StreamSubscription? _thaiMhungPhotoSub;

  double? _deviceHeading;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  List<VideoGpsTrack> _dbGpsTracks = [];
  VideoGpsTrack? _lastSyncedVideoTrack;
  List<Map<String, dynamic>> _responders = [];
  String? _currentResponseId;

  CameraController? _cameraController;
  bool _isRecording = false;
  Timer? _gpsTimer;
  DateTime? _recordingStartTime;
  List<Map<String, dynamic>> _recordedGpsTracks = [];
  String? _selectedEmergencyCategoryId;
  DonationCategory? _selectedEmergencyCategory;
  List<DonationCategory> _emergencyCategories = [];
  bool _isLoadingCategories = false;

  List<Video> _trendingVideos = []; int _trendingPage = 1; bool _hasMoreTrending = true; bool _isLoadingMoreTrending = false;
  bool _isLoadingTrending = true;
  String? _highlightVideoId;

  int _prepCountdown = 0;
  int _recordingTimeLeft = SyncConfig.maxEmergencyRecordingSeconds;
  Timer? _countdownTimer;
  Timer? _durationTimer;
  
  bool _isPhotoMode = false;
  bool _isThaiMhungReporting = false;
  bool _isSendingThaiMhungPhotos = false;
  final List<XFile> _capturedPhotos = [];
  List<ThaiMhungPhoto> _thaiMhungPhotos = []; int _galleryPage = 1; bool _hasMoreGallery = true; bool _isLoadingMoreGallery = false; ScrollController _galleryScrollController = ScrollController();
  final List<LatLng> _routePoints = [];
  bool _canViewUnblurred = false;
  bool _isUiVisible = true;
  bool _isChatVisible = false;
  bool _hasRejected = false;
  String? _currentProfessionName;
  Map<String, dynamic>? _emergencyHealthSession;
  bool _isEmergencyHealthPanicVisible = false;
  bool _hasPlayedEmergencyHealthAlert = false;
  int _emergencyHealthCountdownSeconds = 0;
  Timer? _emergencyHealthCountdownTimer;
  Map<String, dynamic>? _emergencyHealthData;
  bool _isEmergencyHealthDataAvailable = false;
  EmergencyDeadManCheckin? _deadManCheckin;
  bool _isDeadManLoading = false;
  bool _isDeadManCheckingIn = false;

  @override
  void initState() {
    super.initState();
    _currentVideoId = widget.videoId;
    _currentResponseId = widget.responseId;
    _isChatVisible = widget.autoOpenChat;

    _liveBlinkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
    
    _checkPermissions();
    _ensureWebSocketConnected();
    _setupWebSocketStreams();
    _loadInitialData();
    _loadDeadManCheckinState();
    _loadDonationRequests(); // ✅ โหลดรายการคำร้องบริจาคที่แอคทีฟอยู่
    _startResponderTracking();
    _initCompass();
  }

  ThaiMhungRulerPhoto? _floatingMapPhoto;
  Timer? _floatingPhotoTimer;

  void _handleNewPhotoArrived(ThaiMhungRulerPhoto photo) {
    setState(() {
      _floatingMapPhoto = photo;
    });

    if (photo.latitude != null && photo.longitude != null) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(photo.latitude!, photo.longitude!),
            zoom: 18,
          ),
        ),
      );
    }

    _floatingPhotoTimer?.cancel();
    _floatingPhotoTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _floatingMapPhoto = null);
    });
  }

  // ✅ [Yield Way] แสดง pulse animation เมื่อมีคนกดให้ทาง
  void _triggerYieldPulse() {
    if (!mounted) return;
    setState(() => _isYieldPulsing = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isYieldPulsing = false);
    });
  }

  @override
  void dispose() {
    if (_currentVideoId != null) {
      WebSocketService().leaveVideoRoom(_currentVideoId!);
    }
    _videoPlayerController?.removeListener(_syncGpsWithVideo);
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    _liveBlinkController.dispose();
    _pulseController.dispose();
    _connectionSub?.cancel();
    _interactionSub?.cancel();
    _supabaseInteractionSub?.unsubscribe();
    _progressSub?.cancel();
    _rescueIncomingSub?.cancel();
    _videoStatusSub?.cancel();
    _locationSub?.cancel();
    _myLocationStreamSub?.cancel();
    _emergencySub?.cancel();
    _emergencyHealthSessionSub?.unsubscribe();
    _emergencyHealthTokenSub?.unsubscribe();
    _compassSub?.cancel();
    _viewerCountSub?.cancel();
    _yieldWayAlertSub?.cancel();
    _emergencyHealthSensorAlertSub?.cancel();
    _emergencyHealthDeadManReminderSub?.cancel();
    _emergencyHealthDeadManTriggeredSub?.cancel();
    _photoBlurSub?.cancel();
    _thaiMhungPhotoSub?.cancel();
    _countdownTimer?.cancel();
    _durationTimer?.cancel();
    if (_gpsTimer != null) _gpsTimer!.cancel();
    _emergencyHealthCountdownTimer?.cancel();
    _floatingPhotoTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // วัดตำแหน่งด้านล่างของกล่องยอดนิยมหลัง Build เพื่อปรับขนาดแชท
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_trendingPanelKey.currentContext != null) {
        final RenderBox? box = _trendingPanelKey.currentContext!.findRenderObject() as RenderBox?;
        if (box != null) {
          final position = box.localToGlobal(Offset.zero);
          final bottom = position.dy + box.size.height;
          if (_trendingPanelBottom != bottom) {
            setState(() {
              _trendingPanelBottom = bottom;
            });
          }
        }
      }
    });

    return Scaffold(
      body: GestureDetector(
        onTap: () {
          if (_isChatVisible) {
            FocusScope.of(context).unfocus();
          }
        },
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
          // Layer 1: Background layers (Map, Compass, Gallery, Back Button)
          EmergencyMapSection(
            currentVideoId: _currentVideoId,
            currentVideo: _currentVideo,
            routePoints: _routePoints,
            userLocation: _userLocation,
            responders: _responders,
            selectedTab: _selectedTab,
            onMapCreated: (controller) {
               _mapController = controller;
               Future.delayed(const Duration(milliseconds: 500), () => _adjustMapBounds());
            },
            isUiVisible: _isUiVisible,
            topPadding: _calculateMapTopPadding(),
            onMapTap: () {
               if (_selectedTab != 0 || _isThaiMhungReporting) {
                 setState(() {
                   _selectedTab = 0;
                   _isThaiMhungReporting = false;
                   _isUiVisible = true;
                 });
               } else {
                 _toggleUiVisibility();
               }
            },
            currentResponseId: _currentResponseId,
            deviceHeading: _deviceHeading,
            isThaiMhungReporting: _isThaiMhungReporting,
            onBackTap: () {
              setState(() {
                _isThaiMhungReporting = false;
                _selectedTab = 0;
              });
            },
            isYieldPulsing: _isYieldPulsing, // ✅ ส่งสถานะ pulse ให้ Map
            isEmergencyHealthDataAvailable: _isEmergencyHealthDataAvailable,
            onShowHealthDataTap: _showEmergencyHealthDataDialog,
            emergencyHealthStatus: _emergencyHealthSession?['status']?.toString(),
          ),

          // Floating New Photo Effect
          if (_currentVideoId != null)
             Positioned.fill(
               child: IgnorePointer(
                 child: Align(
                   alignment: Alignment.center,
                   child: AnimatedOpacity(
                     opacity: _floatingMapPhoto != null ? 1.0 : 0.0,
                     duration: const Duration(milliseconds: 600),
                     child: _floatingMapPhoto != null ? Container(
                       margin: const EdgeInsets.only(bottom: 120), // ยกขึ้นไม่ให้โดนบัง
                       padding: const EdgeInsets.all(8),
                       decoration: BoxDecoration(
                         color: Colors.black.withOpacity(0.6),
                         borderRadius: BorderRadius.circular(16),
                         border: Border.all(color: Colors.pinkAccent.withOpacity(0.5), width: 2),
                         boxShadow: [
                           BoxShadow(
                             color: Colors.pinkAccent.withOpacity(0.3),
                             blurRadius: 20,
                             spreadRadius: 5,
                           ),
                         ],
                       ),
                       child: Column(
                         mainAxisSize: MainAxisSize.min,
                         children: [
                           const Text(
                             '✨ พิกัดภาพถ่ายใหม่',
                             style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                           ),
                           const SizedBox(height: 8),
                           ClipRRect(
                             borderRadius: BorderRadius.circular(8),
                             child: Image.network(
                               _floatingMapPhoto!.photoUrl,
                               height: 150,
                               fit: BoxFit.cover,
                               errorBuilder: (context, _, __) => const Icon(Icons.broken_image, color: Colors.white54, size: 40),
                             ),
                           ),
                         ],
                       ),
                     ) : const SizedBox.shrink(),
                   ),
                 ),
               ),
             ),

          // Layer 2: Main UI Interaction Overlay
          EmergencyUiOverlay(
            isUiVisible: _isUiVisible,
            isConnected: _isConnected,
            selectedTab: _selectedTab,
            isThaiMhungReporting: _isThaiMhungReporting,
            currentResponseId: _currentResponseId,
            isEligibleResponder: _isEligibleResponder(),
            liveBlinkController: _liveBlinkController,
            hasVideo: _currentVideoId != null,
            onTabSelected: (index) {
              if (index == 0) {
                _onThaiMhungTabSelected();
              } else {
                setState(() {
                  _selectedTab = index;
                  _isThaiMhungReporting = false;
                });
              }
            },
            onEmergencyTabSelected: () async {
               setState(() { _selectedTab = 2; _isThaiMhungReporting = false; });
               await _loadConfigFromDatabase();
               if (_emergencyCategories.isEmpty) _loadEmergencyCategories();
               _initCamera();
            },
            onOpenInMaps: _openInGoogleMaps,
            onUpdateStatus: _updateRescueStatus,
            onAcceptRescue: _acceptRescue,
            onToggleUi: () {
              if (_isChatVisible) {
                FocusScope.of(context).unfocus();
              } else if (_isThaiMhungReporting || _selectedTab == 2) {
                setState(() {
                  _selectedTab = 0;
                  _isThaiMhungReporting = false;
                  _isUiVisible = true;
                });
              } else {
                setState(() => _isUiVisible = !_isUiVisible);
              }
            },
             onToggleChat: () => setState(() => _isChatVisible = !_isChatVisible),
             isChatVisible: _isChatVisible,
             onDeclineRescue: _declineRescueDialog,
            triageBadgeCount: _triageBadgeCount,
            onTriageTabSelected: () {
              if (_currentVideoId != null) {
                TriageSheetWidget.show(context, _currentVideoId!, _victimRepository);
              }
            },
            content: _buildMainContent(),
           ),

          // Layer 3: Top Bar (Back Button and Custom Video Controls)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FloatingBackButton(
                  visible: _isUiVisible && _selectedTab != 2 && _selectedTab != 1 && !_isThaiMhungReporting,
                  onTap: () => Navigator.of(context).pop(),
                ),
                if (_isUiVisible && _selectedTab != 2 && _selectedTab != 1 && !_isThaiMhungReporting && _chewieController != null && !_isOverlayVisible) ...[
                  const SizedBox(width: 12),
                  GlassmorphismVideoControls(
                    controller: _chewieController!.videoPlayerController,
                  ),
                ],
              ],
            ),
          ),
          
          // Emergency Chat Overlay (Floating Window at bottom-right)
          if (_isChatVisible && _currentVideoId != null && _isUiVisible && _selectedTab != 2 && !_isThaiMhungReporting)
            Positioned(
              right: 16,
              // วางชิดด้านล่างขวาของจอ (ระดับเดียวกับปุ่ม Tab ที่เลื่อนไปซ้าย)
              bottom: MediaQuery.of(context).padding.bottom + 16,
              width: MediaQuery.of(context).size.width * 0.55, 
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  // คำนวณความสูงสูงสุด: จอทั้งหมด - (ตำแหน่งล่างของกล่องยอดนิยม) - ระยะแป้นพิมพ์ - ระยะห่างจากขอบล่าง - ระยะห่างจากกล่องยอดนิยม (12)
                  maxHeight: _trendingPanelBottom > 0 
                      ? (MediaQuery.of(context).size.height - _trendingPanelBottom - MediaQuery.of(context).viewInsets.bottom - (MediaQuery.of(context).padding.bottom + 16) - 12)
                          .clamp(100, MediaQuery.of(context).size.height * 0.4) // ให้สูงได้สูงสุด 40% ของจอ
                      : MediaQuery.of(context).size.height * 0.25, // Fallback
                ),
                child: EmergencyChatWidget(
                key: ValueKey(_currentVideoId!), // ผูก key ให้สร้างใหม่เมื่อเปลี่ยนเหตุการณ์
                videoId: _currentVideoId!,
                userId: AuthService.instance.userId ?? 'unknown',
                userName: AuthService.instance.currentUser?.fullName ?? 'Anonymous',
                role: _getChatRole(),
                professionName: _currentProfessionName,
                profileImageUrl: AuthService.instance.currentUser?.profileImageUrl,
                onClose: () => setState(() => _isChatVisible = false),
              ),
              ),
            ),
          
          // Layer 5: Rescue Accept Panel (Must be on topmost layer, over chat window)
          if (_isUiVisible && _isEligibleResponder() && _selectedTab == 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 48,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: RescueAcceptPanelWidget(
                  onAccept: _acceptRescue,
                ),
              ),
            ),
          
          // Layer 6: Rescue Control Panel (MUST BE ABOVE CHAT AND OVERLAY)
          if (_isUiVisible && _currentResponseId != null && _selectedTab == 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 105, // อยู่เหนือ Bottom Tabs
              child: RescueControlPanelWidget(
                onOpenInMaps: _openInGoogleMaps,
                onUpdateStatus: _updateRescueStatus,
              ),
            ),

          // ✅ [Phase 3a] Floating button to view patient health data
          if (_isUiVisible && _currentResponseId != null && _isEmergencyHealthDataAvailable && _selectedTab != 1)
            Positioned(
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 160,
              child: FloatingActionButton.extended(
                onPressed: _showEmergencyHealthDataDialog,
                backgroundColor: Colors.green.shade700,
                icon: const Icon(Icons.medical_services, color: Colors.white),
                label: const Text(
                  'ข้อมูลสุขภาพ',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'SukhumvitSet',
                  ),
                ),
              ),
            ),

          if (_isUiVisible && _deadManCheckin?.isEnabled == true && _selectedTab != 1)
            Positioned(
              left: 16,
              top: MediaQuery.of(context).padding.top + 88,
              child: _buildDeadManCheckInChip(),
            ),

          if (_isEmergencyHealthPanicVisible && _emergencyHealthSession != null && _selectedTab != 1)
            Positioned.fill(
              child: _buildEmergencyHealthPanicOverlay(),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildEmergencyHealthPanicOverlay() {
    final remaining = _emergencyHealthCountdownSeconds;
    final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');
    final sessionStatus = _emergencyHealthSession?['status']?.toString() ?? 'counting';

    return IgnorePointer(
      ignoring: false,
      child: Container(
        color: Colors.black.withOpacity(0.86),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 540),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.red.shade900.withOpacity(0.96),
                          Colors.deepOrange.shade900.withOpacity(0.88),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withOpacity(0.35),
                          blurRadius: 40,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_rounded, color: Colors.white, size: 72),
                        const SizedBox(height: 16),
                        const Text(
                          'Panic Cancel Notification',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'SukhumvitSet',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          sessionStatus == 'counting'
                              ? 'ข้อมูลสุขภาพจะปลดล็อกในอีก $minutes:$seconds'
                              : 'สถานะปัจจุบัน: $sessionStatus',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SukhumvitSet',
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withOpacity(0.14)),
                          ),
                          child: Text(
                            'กดปุ่มด้านล่างเพื่อยกเลิกการปลดล็อกข้อมูลสุขภาพทันที ถ้าคุณกดผิดหรือไม่ต้องการให้ระบบแชร์ข้อมูลกับผู้ช่วยเหลือ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.96),
                              fontSize: 15,
                              height: 1.35,
                              fontFamily: 'SukhumvitSet',
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _cancelEmergencyHealthSession,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.redAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text(
                              'ยกเลิกการปลดล็อก',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'SukhumvitSet',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('กำลังนับถอยหลังจากฝั่งเซิร์ฟเวอร์อยู่'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          child: const Text(
                            'นับถอยหลังควบคุมโดยเซิร์ฟเวอร์',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SukhumvitSet',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// คำนวณบทบาทว่าคนคนนี้คือใครในแชท
  String _getChatRole() {
    final currentUserId = AuthService.instance.userId;

    // 1. Reporter: เจ้าของวิดีโอ หรือกำลังรายงานอยู่
    if (_currentVideo != null && _currentVideo?.userId == currentUserId) return 'reporter';
    if (_selectedTab == 2 || _isRecording) return 'reporter';

    // 2. Responder: ต้องเป็นคนทีกด "ยืนยันรับการช่วยเหลือ" ของเหตุการณ์นี้แล้ว (_currentResponseId มีค่า)
    if (_currentResponseId != null) return 'responder';

    // 3. Thai Mhung: ถ้ากำลังอยู่ในโหมดรายงานแบบไทยมุง
    if (_isThaiMhungReporting) return 'thaimhung';

    return 'viewer';
  }



  Future<void> _declineRescueDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ปฏิเสธการช่วยเหลือ', style: TextStyle(fontFamily: 'SukhumvitSet', fontWeight: FontWeight.bold)),
        content: const Text('ยืนยันว่าจะปฏิเสธการช่วยเหลือเหตุการณ์นี้ใช่หรือไม่?', style: TextStyle(fontFamily: 'SukhumvitSet')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('ยืนยัน', style: TextStyle(color: Colors.red))),
        ],
      )
    );
    if (confirm == true) {
      if (!mounted) return;
      setState(() {
        _hasRejected = true;
        _isChatVisible = false; // กลับสู่โหมด emergency ปกติ (ซ่อนแชทด้วยเผื่อเปิดค้างไว้)
      });
      final userId = AuthService.instance.userId;
      if (userId != null && _currentVideoId != null) {
        await ServiceLocator.instance.videoRepository.rejectIncident(videoId: _currentVideoId!, responderId: userId);
        
        // Save to dismissed alert IDs so it disappears from Home page stack
        try {
          final repo = ServiceLocator.instance.userRepository;
          final saved = await repo.getUiPreference(userId, 'dismissed_emergency_alert_ids');
          final list = saved != null && saved.isNotEmpty ? saved.split(',').toList() : <String>[];
          if (!list.contains(_currentVideoId!)) {
            list.add(_currentVideoId!);
            await repo.saveUiPreference(userId, 'dismissed_emergency_alert_ids', list.join(','));
          }
        } catch (e) {
          debugPrint('Error saving dismissed alert on reject: $e');
        }
      }
    }
  }

  Widget _buildMainContent() {
    if (_selectedTab == 0) {
      if (_isThaiMhungReporting) {
        return IncidentReportWidget(
          isRecording: _isRecording,
          isLoadingCategories: _isLoadingCategories,
          prepCountdown: _prepCountdown,
          recordingTimeLeft: _recordingTimeLeft,
          isPhotoMode: _isPhotoMode,
          capturedPhotos: _capturedPhotos,
          selectedEmergencyCategoryId: _selectedEmergencyCategoryId,
          selectedEmergencyCategory: _selectedEmergencyCategory,
          emergencyCategories: _emergencyCategories,
          cameraController: _cameraController,
          onTakePhoto: _takePhoto,
          onSendPhotos: _sendPhotos,
          onLongPressDownVideo: _onLongPressDownVideo,
          onLongPressEndCancelVideo: _onLongPressEndCancelVideo,
          onCategorySelected: (cat) => setState(() {
            _selectedEmergencyCategoryId = cat.id;
            _selectedEmergencyCategory = cat;
          }),
          onModeChanged: (photoMode) => setState(() => _isPhotoMode = photoMode),
          onLoadCategories: _loadEmergencyCategories,
          onYieldWay: _yieldWay,
          yieldWayCount: '$_yieldWayCount คน',
          yieldWayCountValue: _yieldWayCount,
          yieldWayNotifiedCount: _yieldWayNotifiedCount,
          onBackTap: () => setState(() {
            _selectedTab = 0;
            _isThaiMhungReporting = false;
            _isUiVisible = true;
          }),
          isThaiMhungMode: true,
          isSendingPhotos: _isSendingThaiMhungPhotos,
        );
      } else {
      return LiveViewWidget(
        chewieController: _chewieController,
        currentVideoId: _currentVideoId,
        currentVideo: _currentVideo,
        formattedViewerCount: _formatCount(_viewerCount),
        viewerCount: _viewerCount,
        likeCountFormatted: _formatCount(_likeCount),
        activeRequests: _activeDonationRequests,
        activeRequestIndex: _activeRequestIndex,
        userCanCreateRequest: _canCreateDonationRequest(),
        onSwitchRequest: (forward) {
          if (_activeDonationRequests.isEmpty) return;
          setState(() {
            _activeRequestIndex = ((_activeRequestIndex + (forward ? 1 : -1)) %
                _activeDonationRequests.length);
          });
        },
        trendingVideos: _trendingVideos,
        onLoadMoreTrending: _loadMoreTrendingVideos,
        isLoadingTrending: _isLoadingTrending,
        highlightVideoId: _highlightVideoId,
        canViewUnblurred: _canViewUnblurred,
        yieldWayCount: '$_yieldWayCount คน',
        yieldWayCountValue: _yieldWayCount,
        yieldWayNotifiedCount: _yieldWayNotifiedCount,
        onLike: _onLike,
        isLiked: _hasLiked,
        likeCount: _likeCount,
        likeTrigger: _likeTrigger,
        onYieldWay: _yieldWay,
        onDonate: _showDonationSheet,
        onSwitchVideo: _switchVideo,
        onNewPhotoArrived: _handleNewPhotoArrived,
        onOverlayChanged: (visible) => setState(() => _isOverlayVisible = visible),
        trendingPanelKey: _trendingPanelKey,
      );
      }
    } else if (_selectedTab == 1) {
      return const SizedBox.shrink();
    } else {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: IncidentReportWidget(
          isRecording: _isRecording,
          isLoadingCategories: _isLoadingCategories,
          prepCountdown: _prepCountdown,
          recordingTimeLeft: _recordingTimeLeft,
          isPhotoMode: _isPhotoMode,
          capturedPhotos: _capturedPhotos,
          selectedEmergencyCategoryId: _selectedEmergencyCategoryId,
          selectedEmergencyCategory: _selectedEmergencyCategory,
          emergencyCategories: _emergencyCategories,
          cameraController: _cameraController,
          onTakePhoto: _takePhoto,
          onSendPhotos: _sendPhotos,
          onLongPressDownVideo: _onLongPressDownVideo,
          onLongPressEndCancelVideo: _onLongPressEndCancelVideo,
          onCategorySelected: (cat) => setState(() {
            _selectedEmergencyCategoryId = cat.id;
            _selectedEmergencyCategory = cat;
          }),
          onModeChanged: (photoMode) => setState(() => _isPhotoMode = photoMode),
          onLoadCategories: _loadEmergencyCategories,
          onYieldWay: _yieldWay,
          yieldWayCount: '$_yieldWayCount คน',
          yieldWayCountValue: _yieldWayCount,
          yieldWayNotifiedCount: _yieldWayNotifiedCount,
          onBackTap: () => setState(() {
            _selectedTab = 0;
            _isThaiMhungReporting = false;
            _isUiVisible = true;
          }),
          isSendingPhotos: _isSendingThaiMhungPhotos,
        ),
      );
    }
  }

  /// ดึงชื่ออาชีพของผู้ใช้ปัจจุบัน (เพื่อแสดงใน Chat สำหรับ Responder)
  Future<void> _fetchProfessionName() async {
    final user = AuthService.instance.currentUser;
    if (user != null && user.professionId != null) {
      try {
        final repo = ServiceLocator.instance.professionRepository;
        final profession = await repo.getProfessionById(user.professionId!);
        if (profession != null && mounted) {
          setState(() => _currentProfessionName = profession.name);
        }
      } catch (e) {
        debugPrint('Error fetching profession name: $e');
      }
    }
  }
}
