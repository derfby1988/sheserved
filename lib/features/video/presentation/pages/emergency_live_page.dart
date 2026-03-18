import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sheserved/features/home/presentation/widgets/background_permission_dialog.dart';
import '../../../../services/location_tracking_service.dart';
import '../../../../config/sync_config.dart';
import '../../../../config/app_config.dart';
import '../../../../services/websocket_service.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../donation/models/donation_models.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../models/video_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'widgets/live_view_widget.dart';
import 'widgets/incident_report_widget.dart';
import 'widgets/relationship_view_widget.dart';
import 'widgets/donation_sheet_widget.dart';
import 'widgets/thai_mhung_gallery_widget.dart';
import 'widgets/emergency_map_section.dart';
import 'widgets/emergency_ui_overlay.dart';
import 'widgets/floating_back_button.dart';
import 'widgets/emergency_chat_widget.dart';
import 'package:flutter_compass/flutter_compass.dart';

// Part files for logic
part 'parts/emergency_reporting_logic.dart';
part 'parts/emergency_websocket_logic.dart';
part 'parts/emergency_navigation_logic.dart';

/// หน้า Emergency Live - ออกแบบตาม Figma
/// แสดงวิดีโอไลฟ์ + แผนที่ GPS + ปุ่มโต้ตอบ
class EmergencyLivePage extends StatefulWidget {
  final String? videoId;
  final String? responseId;

  const EmergencyLivePage({super.key, this.videoId, this.responseId});

  @override
  State<EmergencyLivePage> createState() => _EmergencyLivePageState();
}

class _EmergencyLivePageState extends State<EmergencyLivePage> with TickerProviderStateMixin {
  // === State Variables ===
  int _selectedTab = 0;
  int _viewerCount = 0;
  int _likeCount = 0;
  double _donationTotal = 0.0;
  RealtimeChannel? _supabaseInteractionSub;
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

  List<Video> _trendingVideos = [];
  bool _isLoadingTrending = true;
  String? _highlightVideoId;

  int _prepCountdown = 0;
  int _recordingTimeLeft = SyncConfig.maxEmergencyRecordingSeconds;
  Timer? _countdownTimer;
  Timer? _durationTimer;
  
  bool _isPhotoMode = false;
  bool _isThaiMhungReporting = false;
  final List<XFile> _capturedPhotos = [];
  List<ThaiMhungPhoto> _thaiMhungPhotos = [];
  final List<LatLng> _routePoints = [];
  bool _canViewUnblurred = false;
  bool _isUiVisible = true;
  bool _isChatVisible = false;

  @override
  void initState() {
    super.initState();
    _currentVideoId = widget.videoId;
    _currentResponseId = widget.responseId;

    _liveBlinkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
    
    _checkPermissions();
    _ensureWebSocketConnected();
    _setupWebSocketStreams();
    _loadInitialData();
    _startResponderTracking();
    _initCompass();
  }

  @override
  void dispose() {
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
    _compassSub?.cancel();
    _countdownTimer?.cancel();
    _durationTimer?.cancel();
    if (_gpsTimer != null) _gpsTimer!.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
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
            thaiMhungPhotos: _thaiMhungPhotos,
            isThaiMhungReporting: _isThaiMhungReporting,
            canViewUnblurred: _canViewUnblurred,
            onPhotoTap: _showPhotoDetail,
            onBackTap: () => Navigator.of(context).pop(),
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
            onToggleUi: () => setState(() => _isUiVisible = !_isUiVisible),
            onToggleChat: () => setState(() => _isChatVisible = !_isChatVisible),
            isChatVisible: _isChatVisible,
            content: _buildMainContent(),
          ),

          // Layer 3: Floating Back Button (Must be on top of layers 1 & 2)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            child: FloatingBackButton(
              visible: _isUiVisible && _selectedTab != 2 && !_isThaiMhungReporting,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          
          // Emergency Chat Overlay (Floating Window at bottom-right)
          if (_isChatVisible && _currentVideoId != null && _isUiVisible && _selectedTab != 2 && !_isThaiMhungReporting)
            Positioned(
              right: 16,
              // เหนือปุ่ม Forum/Chat (ซึ่งอยู่ใน Row > Padding ใน Overlay) 
              // กะจาก bottom tabs + button padding = ~160
              bottom: 180, 
              width: MediaQuery.of(context).size.width * 0.42, // กว้างประมาณชิดขวา
              height: MediaQuery.of(context).size.height * 0.38, // สูงไม่เกินยอดนิยม (ประมาณครึ่งจอล่าง)
              child: EmergencyChatWidget(
                videoId: _currentVideoId!,
                userId: AuthService.instance.userId ?? 'unknown',
                userName: AuthService.instance.currentUser?.fullName ?? 'Anonymous',
                role: _getChatRole(),
                profileImageUrl: AuthService.instance.currentUser?.profileImageUrl,
                onClose: () => setState(() => _isChatVisible = false),
              ),
            ),
        ],
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
          onBackTap: () => setState(() {
            _selectedTab = 0;
            _isThaiMhungReporting = false;
            _isUiVisible = true;
          }),
          isThaiMhungMode: true,
        );
      } else {
        return LiveViewWidget(
          chewieController: _chewieController,
          currentVideoId: _currentVideoId,
          currentVideo: _currentVideo,
          formattedViewerCount: _formatCount(_viewerCount),
          likeCountFormatted: _formatCount(_likeCount),
          donationTotalFormatted: _donationTotal.toStringAsFixed(0),
          trendingVideos: _trendingVideos,
          isLoadingTrending: _isLoadingTrending,
          highlightVideoId: _highlightVideoId,
          canViewUnblurred: _canViewUnblurred,
          onLike: _onLike,
          onDonate: _showDonationSheet,
          onSwitchVideo: _switchVideo,
        );
      }
    } else if (_selectedTab == 1) {
      return RelationshipViewWidget(
        currentVideo: _currentVideo,
        onCategorySelected: (cat) => setState(() {
          _selectedTab = 2;
          _selectedEmergencyCategoryId = cat.id;
          _selectedEmergencyCategory = cat;
        }),
        onBackTap: () => setState(() {
          _selectedTab = 0;
          _isThaiMhungReporting = false;
          _isUiVisible = true;
        }),
      );
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
          onYieldWay: () {},
          onBackTap: () => setState(() {
            _selectedTab = 0;
            _isThaiMhungReporting = false;
            _isUiVisible = true;
          }),
        ),
      );
    }
  }
}
