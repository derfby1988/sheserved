import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sheserved/features/home/presentation/widgets/background_permission_dialog.dart';
import '../../../../services/location_tracking_service.dart';

import '../../../../config/sync_config.dart';
import '../../../../services/websocket_service.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../data/repositories/video_repository.dart';
import '../../../donation/models/donation_models.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

import '../../models/video_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'widgets/offline_indicator_widget.dart';
import 'widgets/bottom_tabs_widget.dart';
import 'widgets/rescue_control_panel_widget.dart';
import 'widgets/map_background_widget.dart';
import 'widgets/incident_report_widget.dart';
import 'widgets/rescue_accept_panel_widget.dart';
import 'widgets/live_view_widget.dart';
import 'widgets/relationship_view_widget.dart';
import 'widgets/donation_sheet_widget.dart';
import 'widgets/control_back_button_widget.dart';
import 'widgets/thai_mhung_gallery_widget.dart';
import 'widgets/responder_compass_widget.dart';
import 'package:flutter_compass/flutter_compass.dart';

/// หน้า Emergency Live - ออกแบบตาม Figma
/// แสดงวิดีโอไลฟ์ + แผนที่ GPS + ปุ่มโต้ตอบ
class EmergencyLivePage extends StatefulWidget {
  final String? videoId;
  final String? responseId; // ID for response tracking

  const EmergencyLivePage({super.key, this.videoId, this.responseId});

  @override
  State<EmergencyLivePage> createState() => _EmergencyLivePageState();
}

class _EmergencyLivePageState extends State<EmergencyLivePage>
    with TickerProviderStateMixin {
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
  
  // Video Player & Map Sync
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  List<VideoGpsTrack> _dbGpsTracks = [];
  
  // Custom logic to avoid resetting polyline too often
  VideoGpsTrack? _lastSyncedVideoTrack;
  
  // Responders data
  List<Map<String, dynamic>> _responders = [];
  String? _currentResponseId;

  // Emergency Recording
  CameraController? _cameraController;
  bool _isRecording = false;
  Timer? _gpsTimer;
  DateTime? _recordingStartTime;
  List<Map<String, dynamic>> _recordedGpsTracks = [];
  String? _selectedEmergencyCategoryId;
  DonationCategory? _selectedEmergencyCategory; // Full object for display
  
  // Category state
  List<DonationCategory> _emergencyCategories = [];
  bool _isLoadingCategories = false;

  // Trending Videos
  List<Video> _trendingVideos = [];
  bool _isLoadingTrending = true;

  // Video Recording Limits & Timers
  static const int _prepSeconds = 3;
  int _prepCountdown = 0;
  int _recordingTimeLeft = SyncConfig.maxEmergencyRecordingSeconds;
  Timer? _countdownTimer;
  Timer? _durationTimer;
  
  // Emergency Photos
  bool _isPhotoMode = false;
  bool _isThaiMhungReporting = false;
  final List<XFile> _capturedPhotos = [];
  List<ThaiMhungPhoto> _thaiMhungPhotos = [];
  
  // GPS Route Points for the currently watched video
  final List<LatLng> _routePoints = [];

  // Privacy & Permission
  bool _canViewUnblurred = false;

  @override
  void initState() {
    super.initState();
    
    // Auth Check: ตรวจสอบสถานะซ้ำที่ Target Page ตาม navigation guide
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ServiceLocator.instance.currentUser == null) {
        Navigator.pushReplacementNamed(
          context,
          '/login',
          arguments: '/emergency-live',
        );
      }
    });
    
    _currentVideoId = widget.videoId;

    // Check for initial tab argument from Navigator
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic> && args['tab'] != null) {
        setState(() {
          _selectedTab = args['tab'];
        });
        if (_selectedTab == 2) {
          _loadConfigFromDatabase();
          if (_emergencyCategories.isEmpty) {
            _loadEmergencyCategories();
          }
          _initCamera();
        }
      }
    });

    // Check if we have an active incident response for this video
    if (widget.responseId != null) {
      _currentResponseId = widget.responseId;
    }
    
    _liveBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    _checkPermissions();
    _ensureWebSocketConnected();
    _setupWebSocketStreams();
    _loadInitialData();
    _startResponderTracking(); // This will now also init the compass if appropriate
    _initCompass(); // Keep call but we will add conditions inside _initCompass
  }

  void _initCompass() {
    // ALWAYS cancel existing subscription first to prevent leaks
    _compassSub?.cancel();
    _compassSub = null;

    // Only listen to compass if we are a responder to reduce native log noise (D/FlutterCompass)
    if (_currentResponseId == null) return;
    
    _compassSub = FlutterCompass.events?.listen((event) {
      if (mounted && event.heading != null) {
        // Throttle updates: only setState if heading change is > 1.0 degree
        // to reduce UI rebuilds and terminal log noise.
        if (_deviceHeading == null || (event.heading! - _deviceHeading!).abs() > 1.0) {
          setState(() => _deviceHeading = event.heading);
        }
      }
    });
  }

  /// เปิดการติดตามตำแหน่งของอาสาสมัคร (Responder) เพื่อส่งให้ผู้แจ้งเหตุติดตามได้แบบ Real-time
  Future<void> _startResponderTracking() async {
    // ติดตามเฉพาะเมื่อเข้ามาในฐานะผู้ตอบรับการช่วยเหลือ (มี responseId)
    if (_currentResponseId == null) return;
    
    debugPrint('EmergencyLivePage: Starting responder tracking for responseId=$_currentResponseId');

    final locService = LocationTrackingService();
    final isAlwaysGranted = await locService.isBackgroundPermissionGranted();

    if (!isAlwaysGranted) {
      if (mounted) {
        final shouldGoToSettings = await BackgroundPermissionDialog.show(context);
        if (shouldGoToSettings) {
          await openAppSettings();
          return;
        }
      }
    }
    
    _myLocationStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // อัปเดตทุกๆ 10 เมตรเพื่อประหยัดแบตเตอรี่และ data
      ),
    ).listen((Position position) {
      if (!mounted) return;
      
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
      });
      
      // ส่งตำแหน่งไปยัง Server ผ่าน WebSocket
      final userId = AuthService.instance.userId;
      if (userId != null && _isConnected) {
        final socket = WebSocketService().socket;
        if (socket != null && socket.connected) {
          socket.emit('location-update', {
            'userId': userId,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'timestamp': DateTime.now().toIso8601String(),
            'accuracy': position.accuracy,
            'speed': position.speed,
            'heading': position.heading,
          });
            // debugPrint('EmergencyLivePage: Location emitted for volunteer=$userId'); // Reduced noise
        }
      }
    });
  }

  /// Ensure WebSocket is connected before doing anything
  Future<void> _ensureWebSocketConnected() async {
    final ws = WebSocketService();
    final userId = ServiceLocator.instance.currentUser?.id;
    if (userId != null && !ws.isConnected) {
      debugPrint('EmergencyLivePage: WebSocket not connected. Connecting now...');
      ws.resetConnectionAttempts();
      await ws.connect(userId: userId);
      debugPrint('EmergencyLivePage: WebSocket connection initiated. isConnected=${ws.isConnected}');
    } else {
      debugPrint('EmergencyLivePage: WebSocket already connected=${ws.isConnected}, userId=$userId');
    }
  }

  Future<void> _loadConfigFromDatabase() async {
    try {
      await SyncConfig.loadFromSupabase();
      if (mounted) {
        setState(() {
          _recordingTimeLeft = SyncConfig.maxEmergencyRecordingSeconds;
        });
      }
    } catch (e) {
      debugPrint("ERROR loading emergency config: $e");
    }
  }

  Future<void> _checkPermissions() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      // Auto-center camera only if no specific video/incident is being watched
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (mounted) {
        setState(() {
          _userLocation = LatLng(position.latitude, position.longitude);
        });
        
        if (_currentVideoId == null) {
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(_userLocation!, 15.0),
          );
        }
      }
    } catch (e) {
      debugPrint("Error getting current location: $e");
    }
  }

  void _loadInitialData() async {
    await _loadEmergencyCategories();
    if (_currentVideoId != null) {
      final summary = await ServiceLocator.instance.videoRepository
          .getInteractionSummary(_currentVideoId!);
      setState(() {
        _likeCount = summary['likes'] ?? 0;
        _donationTotal = summary['donations']?.toDouble() ?? 0.0;
        _viewerCount = summary['views'] ?? 0;
      });
      
      _recordView();
      _checkPrivacyPermissions();

      // Fetch Video and handle reproduction
      final video = await ServiceLocator.instance.videoRepository.getVideoById(_currentVideoId!);
      if (mounted) {
        setState(() {
          _currentVideo = video;
          // แก้ไขข้อผิดพลาด: นำหมวดหมู่มาใช้เลย ไม่ต้องถามซ้ำ
          if (video?.categoryId != null) {
            _selectedEmergencyCategoryId = video!.categoryId;
            // พยายามโหลด Object หมวดหมู่เพื่อแสดงผล UI
            if (_emergencyCategories.isNotEmpty) {
               _selectedEmergencyCategory = _emergencyCategories.firstWhere(
                 (c) => c.id == video.categoryId,
                 orElse: () => DonationCategory(id: video.categoryId!, name: 'เหตุฉุกเฉิน'),
               );
            }
          }
        });
        
        // ✅ ตรวจสอบสิทธิความเป็นส่วนตัวอีกครั้งหลังจากได้ข้อมูลวิดีโอ (เพื่อให้ _isEligibleResponder ทำงานได้ถูกต้อง)
        _checkPrivacyPermissions();
      }
      
      if (video != null && video.previewUrl != null) {
         _initializePlayer(video.previewUrl!, isLocal: video.localFilePath != null);
      }
      
      // Load Thai Mhung Gallery photos
      _loadThaiMhungPhotos();
      
      // Fetch GPS Tracks for the video
      final tracks = await ServiceLocator.instance.videoRepository.getGpsTracks(_currentVideoId!);
      if (tracks.isNotEmpty) {
          _dbGpsTracks = tracks;
          // Populate route points from existing tracks for initial camera focus
          if (mounted) {
            setState(() {
              _routePoints.clear();
              _routePoints.addAll(tracks.map((t) => LatLng(t.latitude, t.longitude)));
            });
            // Focus map on the incident
            _adjustMapBounds();
          }
      } else if (video != null && video.latitude != 0) {
          // Fallback if no tracks but video has a location
          if (mounted) {
            setState(() {
              _routePoints.clear();
              _routePoints.add(LatLng(video.latitude, video.longitude));
            });
            _adjustMapBounds();
          }
      }
    }

    // Trending videos are loaded in _loadTrendingVideos
    await _loadTrendingVideos();
    
    // Fetch responders if watching a video
    
    // Fetch responders if watching a video
    if (_currentVideoId != null) {
      _loadResponders();
    }
  }

  Future<void> _loadResponders() async {
    try {
      final responders = await ServiceLocator.instance.videoRepository.getIncidentResponders(_currentVideoId!);
      if (mounted) {
        setState(() {
          // Initialize simulated distance/time for display purposes
          double parseDouble(dynamic value) {
            if (value == null) return 0.0;
            if (value is num) return value.toDouble();
            if (value is String) return double.tryParse(value) ?? 0.0;
            return 0.0;
          }

          for (int i = 0; i < responders.length; i++) {
            var r = responders[i];
            r['currentLat'] = r['startLat'];
            r['currentLng'] = r['startLng'];
            
            // คำนวณระยะทางและเวลาเดินทางโดยประมาณ (ETA)
            if (r['startLat'] != null && r['startLng'] != null && _currentVideo != null) {
              final double distanceMeters = Geolocator.distanceBetween(
                parseDouble(r['startLat']),
                parseDouble(r['startLng']),
                _currentVideo!.latitude,
                _currentVideo!.longitude,
              );
              final double distanceKm = distanceMeters / 1000;
              r['distanceKm'] = distanceKm;
              
              // สมมติความเร็วเฉลี่ยรถกู้ชีพ/อาสาสมัครที่ 40 กม./ชม.
              final int mins = (distanceKm / 40 * 60).round().clamp(1, 120);
              r['estimatedMinutes'] = mins;
            } else {
              r['estimatedMinutes'] = 0;
              r['distanceKm'] = 0.0;
            }
            
            // Provide a default fallback speed if real gps tracking data isn't integrated yet.
            r['currentSpeed'] = 15.0; 
          }
          _responders = responders;
        });
        _adjustMapBounds();
      }
    } catch (e) {
      debugPrint('Error loading responders: $e');
    }
  }

  void _adjustMapBounds() {
    if (_mapController == null || !mounted) return;
    
    // If no specific incident route, center on user if possible
    if (_routePoints.isEmpty) {
      if (_currentVideoId == null && _userLocation != null) {
        try {
          _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_userLocation!, 15.0));
        } catch (_) {}
      }
      return;
    }

    if (_responders.isEmpty) {
      try {
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_routePoints.last, 17.0));
      } catch (_) {}
      return;
    }

    double minLat = _routePoints.last.latitude;
    double maxLat = _routePoints.last.latitude;
    double minLng = _routePoints.last.longitude;
    double maxLng = _routePoints.last.longitude;
    
    for (var r in _responders) {
      if (r['currentLat'] != null && r['currentLng'] != null) {
        if (r['currentLat'] < minLat) minLat = r['currentLat'];
        if (r['currentLat'] > maxLat) maxLat = r['currentLat'];
        if (r['currentLng'] < minLng) minLng = r['currentLng'];
        if (r['currentLng'] > maxLng) maxLng = r['currentLng'];
      }
    }
    
    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    
    try {
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60.0));
    } catch (e) {
      debugPrint("Error adjusting map bounds: $e");
    }
  }

  void _recordView() async {
    if (_currentVideoId == null) return;
    final userId = ServiceLocator.instance.currentUser?.id ?? 'anonymous';
    try {
      final interaction = VideoInteraction(
        id: '', // Supabase UUID default
        videoId: _currentVideoId!,
        userId: userId,
        type: 'view',
        createdAt: DateTime.now(),
      );
      await ServiceLocator.instance.videoRepository.addInteraction(interaction);
    } catch (e) {
      debugPrint('Error recording view: $e');
    }
  }

  Future<void> _loadTrendingVideos() async {
    try {
      final videos = await ServiceLocator.instance.videoRepository.getEmergencyVideos();
      if (mounted) {
        setState(() {
          _trendingVideos = videos;
          _isLoadingTrending = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading trending videos: $e');
      if (mounted) {
        setState(() => _isLoadingTrending = false);
      }
    }
  }

  Future<void> _checkPrivacyPermissions() async {
    if (_currentVideo == null) return;
    
    final currentUserId = AuthService.instance.userId;
    if (currentUserId == null) return;
    
    // Check ownership
    final isOwner = _currentVideo!.userId == currentUserId;
    
    if (mounted) {
      setState(() {
        _canViewUnblurred = false; // Reset first
        
        // 1. สิทธิเจ้าของหรือผู้แจ้งเหตุ
        if (isOwner) _canViewUnblurred = true;

        // 2. จิตอาสาที่ได้รับสิทธิ (ตรงตามหมวดหมู่) หรือผู้ที่รับงานแล้ว
        // เราเช็ค profession mapping ตรงๆ เพื่อความชัวร์ (เผื่อ _isEligibleResponder คืนค่า false เพราะรับงานแล้ว)
        final user = AuthService.instance.currentUser;
        if (user != null && _currentVideo != null) {
          final catId = _currentVideo!.categoryId;
          final category = _emergencyCategories.where((c) => c.id == catId).firstOrNull;
          
          if (category != null && category.volunteerProfessionIds.contains(user.professionId)) {
            debugPrint('EmergencyLivePage: Volunteer profession matches category -> Unblurred view');
            _canViewUnblurred = true;
          }
        }
        
        // 3. ถ้าเข้ารับความช่วยเหลืออยู่แล้ว
        if (_currentResponseId != null) _canViewUnblurred = true;
      });
    }

    if (isOwner) return;

    // Fetch victim's (video owner) profile to see allowed professions
    try {
      final victimProfile = await Supabase.instance.client
          .from('consumer_profiles')
          .select('unblurred_profession_ids')
          .eq('user_id', _currentVideo!.userId)
          .maybeSingle();
      
      if (victimProfile != null) {
        final List<dynamic> allowedIds = victimProfile['unblurred_profession_ids'] ?? [];
        final currentUser = AuthService.instance.currentUser; // My profile from session
        
        if (currentUser != null && currentUser.professionId != null) {
          if (allowedIds.map((id) => id.toString()).contains(currentUser.professionId)) {
            if (mounted) {
              setState(() => _canViewUnblurred = true);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('EmergencyLivePage: Privacy check error: $e');
    }
  }

  void _setupWebSocketStreams() {
    final ws = WebSocketService();
    
    // 1. Connection Status
    _connectionSub = ws.connectionStream.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });

    // 2. Video Interactions (Likes, Gifts, Views) Realtime
    if (_currentVideoId != null) {
      // Subscribe via WebSocket if still needed globally
      ws.joinVideoRoom(_currentVideoId!);
      _interactionSub = ws.videoInteractionStream.listen((data) {
        if (data['videoId'] == _currentVideoId) {
          if (mounted) {
            setState(() {
              if (data['type'] == 'like') _likeCount++;
              if (data['type'] == 'gift') _donationTotal += (data['value'] ?? 0);
              if (data['type'] == 'view') _viewerCount++;
            });
          }
        }
      });
      
      // Real-time table subscription via Supabase
      _supabaseInteractionSub = ServiceLocator.instance.videoRepository.subscribeToInteractions(_currentVideoId!, (payload) {
         if (mounted) {
            setState(() {
               if (payload['type'] == 'like') _likeCount++;
               if (payload['type'] == 'gift') _donationTotal += (payload['value'] ?? 0);
               if (payload['type'] == 'view') _viewerCount++;
            });
         }
      });
    }

    // 3. New Emergency Alerts (to refresh trending list immediately)
    _emergencySub = ws.emergencyNotificationStream.listen((data) {
      debugPrint('EmergencyLivePage: Received emergency notification, refreshing trending list...');
      _loadTrendingVideos();
      
      // Show snackbar for new alerts - EXCEPT for the reporter (Self-Reporter Exclusion)
      final currentUserId = AuthService.instance.userId?.toString();
      final reporterId = data['userId']?.toString() ?? data['senderId']?.toString();
      final bool isSelfReport = (reporterId != null && currentUserId != null) && 
                                (reporterId.trim() == currentUserId.trim());
      
      if (mounted && data['videoId'] != _currentVideoId && !isSelfReport) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🛑 เหตุฉุกเฉินใหม่: ${data['categoryName'] ?? "ไม่ระบุ"}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'ดูเหตุการณ์',
              textColor: Colors.white,
              onPressed: () => _switchVideo(data['videoId']),
            ),
          ),
        );
      }
    });

    // 4. Progress / GPS (Simulated move for demo, but wired to logic)
    _progressSub = ws.videoProgressStream.listen((data) {
      if (data['videoId'] == _currentVideoId && data['location'] != null) {
        final loc = data['location'];
        final point = LatLng(loc['lat'], loc['lng']);
        if (mounted) {
          setState(() {
            _routePoints.add(point);
          });
        }
      }
    });

    // 4. Rescue Incoming Status Feedback
    _rescueIncomingSub = ws.rescueIncomingStream.listen((data) {
      if (mounted) {
         final status = data['status'];
         String msg = '';
         if (status == 'accepted') {
           msg = 'กู้ภัยกำลังเดินทางมาหาคุณ...';
           _loadResponders(); // RELOAD responders list when new one accepts
         }
         else if (status == 'arrived') {
           msg = 'กู้ภัยเดินทางมาถึงที่เกิดเหตุแล้ว!';
         }
         else if (status == 'resolved') {
           msg = 'ภารกิจของกู้ภัยเสร็จสิ้น!';
         }
         
         if (msg.isNotEmpty) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
               content: Row(
                 children: [
                   const Icon(Icons.airport_shuttle, color: Colors.white),
                   const SizedBox(width: 8),
                   Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold))),
                 ],
               ),
               backgroundColor: status == 'resolved' ? Colors.green : Colors.orange.shade800,
               duration: const Duration(seconds: 5),
               behavior: SnackBarBehavior.floating,
             ),
           );
         }
      }
    });

    // 5. Real-time Responder Location Updates
    _locationSub = ws.locationStream.listen((data) {
      if (!mounted) return;
      
      final String? userId = data['userId'];
      if (userId == null) return;

      // Check if this location belongs to one of the responders we are tracking
      setState(() {
        bool found = false;
        for (int i = 0; i < _responders.length; i++) {
          if (_responders[i]['volunteer_id'] == userId || _responders[i]['id'] == userId) {
            _responders[i]['currentLat'] = data['latitude'];
            _responders[i]['currentLng'] = data['longitude'];
            if (data['speed'] != null) {
              _responders[i]['currentSpeed'] = data['speed'];
            }
            
            // Calculate distance and ETA
            if (_routePoints.isNotEmpty) {
              final incidentPoint = _routePoints.last;
              final distanceMeters = Geolocator.distanceBetween(
                data['latitude'], data['longitude'],
                incidentPoint.latitude, incidentPoint.longitude,
              );
              
              _responders[i]['distanceKm'] = distanceMeters / 1000.0;
              
              // Estimate minutes (based on speed or default 40km/h)
              double speedMps = data['speed'] ?? 11.1; // 40 km/h = 11.1 m/s
              if (speedMps < 2.0) speedMps = 11.1; // If stopped, use default for ETA
              
              _responders[i]['estimatedMinutes'] = (distanceMeters / speedMps / 60).round();
            }
            
            found = true;
          }
        }
        
        // If it's a new position for a tracked responder, adjust bounds occasionally
        if (found) {
           _adjustMapBounds();
        }
      });
    });

    // 5. Video Status Updates
    if (_currentVideoId != null) {
      _videoStatusSub = ws.videoStatusStream.listen((data) {
        if (data['videoId'] == _currentVideoId && data['status'] == 'ready') {
           final url = data['url'];
           if (url != null) {
             _initializePlayer(url);
           }
        }
      });
    }
  }

  // Navigation and Rescue Controls
  Future<void> _openInGoogleMaps() async {
    if (_currentVideo == null) return;
    final lat = _currentVideo!.latitude;
    final lng = _currentVideo!.longitude;
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _updateRescueStatus(String status) async {
    if (_currentResponseId == null || _currentVideoId == null) return;
    
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;

    // Send via WebSocket (as planned in server.js)
    final socket = WebSocketService().socket;
    if (socket != null && socket.connected) {
      socket.emit('rescue-status-update', {
        'videoId': _currentVideoId,
        'volunteerId': userId,
        'victimId': _currentVideo?.userId,
        'status': status,
        'responseId': _currentResponseId,
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('อัปเดตสถานะเป็น: ${status == 'arrived' ? 'มาถึงแล้ว' : 'เสร็จสิ้น'}')),
      );

      // If resolved, maybe close the page or show summary
      if (status == 'resolved') {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    }
  }

  /// ตรวจสอบว่าผู้ใช้ปัจจุบันมีสิทธิช่วยเหลือเหตุการณ์นี้หรือไม่
  bool _isEligibleResponder() {
    final user = AuthService.instance.currentUser;
    if (user == null || _currentVideo == null) {
      return false;
    }

    // ถ้าเข้ารับความช่วยเหลืออยู่แล้ว ไม่ต้องแสดงปุ่ม Accept อีก
    if (_currentResponseId != null) return false;

    // ✅ เจ้าของเหตุการณ์ไม่ต้องเห็นกล่องตอบรับการช่วยเหลือของตัวเอง
    final currentUserId = AuthService.instance.userId?.toString();
    final ownerId = _currentVideo?.userId?.toString();
    final authedUserId = user.id.toString();
    final isOwner = (ownerId != null) && 
                    (ownerId.trim() == authedUserId.trim() || 
                     (currentUserId != null && ownerId.trim() == currentUserId.trim()));
    if (isOwner) return false;

    // ตรวจสอบจากหมวดหมู่เหตุฉุกเฉิน
    final catId = _currentVideo?.categoryId;
    final category = _emergencyCategories.where((c) => c.id == catId).firstOrNull;

    if (category != null && category.volunteerProfessionIds.isNotEmpty) {
      // ✅ ให้สิทธิเฉพาะเมื่อ professionId ถูก map ไว้ใน category อย่างชัดเจน
      return category.volunteerProfessionIds.contains(user.professionId);
    }

    // ❌ ไม่มี Fallback — Policy: "No Professional Fallback"
    // ระบบจะไม่ให้สิทธิ 'รับแจ้งเหตุ' โดยอัตโนมัติ
    // หาก category ไม่ได้กำหนด volunteerProfessionIds ไว้ในฐานข้อมูล
    // → ต้องแก้ไขข้อมูล category ใน DB แทน ไม่ใช่ bypass ที่นี่
    debugPrint(
      '_isEligibleResponder: category "$catId" has no mapped professions → denied. '
      'user.professionId=${user.professionId}',
    );
    return false;
  }

  /// กดตอบรับการช่วยเหลือ 
  Future<void> _acceptRescue() async {
    if (_currentVideoId == null || !mounted) return;
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;

    try {
      // 1. สร้างใบงานการช่วยเหลือ (Incident Response) ในฐานข้อมูล
      final responseId = await ServiceLocator.instance.videoRepository.acceptIncident(
        videoId: _currentVideoId!,
        responderId: userId,
        latitude: _userLocation?.latitude,
        longitude: _userLocation?.longitude,
      );
      if (mounted) {
        setState(() {
          _currentResponseId = responseId;
          _checkPrivacyPermissions(); // ✅ ปลดล็อกวิดีโอทันทีเมื่อรับงาน
          _initCompass(); // ✅ เริ่มต้นเข็มทิศเมื่อเป็นผู้ช่วยเหลือแล้ว
        });
      }

          // 1.5 เพิ่มตัวเองลงในรายชื่อผู้ตอบรับทันทีเพื่อความรวดเร็วในการแสดงผล
          final user = AuthService.instance.currentUser;
          if (user != null && _userLocation != null) {
            _responders.add({
              'id': responseId,
              'volunteerId': userId,
              'status': 'accepted',
              'volunteerName': user.fullName,
              'professionName': 'อาสาสมัคร', // Default as professionName is not in UserModel
              'professionColor': '#FF3B30', // Default Red as professionColor is not in UserModel
              'currentLat': _userLocation!.latitude,
              'currentLng': _userLocation!.longitude,
              'distanceKm': 0.0,
              'estimatedMinutes': 0,
            });
          }
        
        // 2. บอก Server ผ่าน WebSocket ว่าเราตอบรับแล้ว
        final socket = WebSocketService().socket;
        if (socket != null && socket.connected) {
          socket.emit('rescue-status-update', {
            'videoId': _currentVideoId,
            'volunteerId': userId,
            'victimId': _currentVideo?.userId,
            'status': 'accepted',
            'responseId': _currentResponseId,
          });
        }

        // 3. เริ่มส่งพิกัด GPS อัตโนมัติ
        _startResponderTracking();
        _adjustMapBounds();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('คุณได้รับภารกิจช่วยเหลือแล้ว! กำลังนำทาง...'),
            backgroundColor: Colors.blue,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
      debugPrint('Error accepting rescue: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถตอบรับความช่วยเหลือได้ในขณะนี้')),
        );
      }
    }
  }

  void _switchVideo(String newVideoId) {
    if (_currentVideoId != null) {
      WebSocketService().leaveVideoRoom(_currentVideoId!);
    }
    
    _interactionSub?.cancel();
    _supabaseInteractionSub?.unsubscribe();
    _progressSub?.cancel();
    _rescueIncomingSub?.cancel();
    _videoStatusSub?.cancel();
    _emergencySub?.cancel();
    
    _videoPlayerController?.removeListener(_syncGpsWithVideo);
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
    _chewieController?.dispose();
    _chewieController = null;
    
    setState(() {
      _currentVideoId = newVideoId;
      _currentVideo = null;
      _dbGpsTracks.clear();
      _routePoints.clear();
      _responders.clear();
      _lastSyncedVideoTrack = null;
      _likeCount = 0;
      _donationTotal = 0.0;
    });

    _setupWebSocketStreams();
    _loadInitialData();
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
    if (_currentVideoId != null) {
      WebSocketService().leaveVideoRoom(_currentVideoId!);
    }
    if (_gpsTimer != null) _gpsTimer!.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (_cameraController != null) return;
    
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      
      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Error initializing camera: $e");
    }
  }

  // ===================== VIDEO RECORDING LOGIC =====================

  /// โหลด categories เมื่อสลับมาแท็บ "แจ้งเหตุ"
  Future<void> _loadEmergencyCategories() async {
    if (_emergencyCategories.isNotEmpty || _isLoadingCategories) return;
    setState(() => _isLoadingCategories = true);
    try {
      final cats = await ServiceLocator.instance.donationRepository.getEmergencyCategories();
      if (mounted) setState(() => _emergencyCategories = cats);
    } catch (e) {
      debugPrint('Error loading emergency categories: $e');
    } finally {
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  /// Long press → ตรวจสอบว่าเลือก category แล้ว → countdown → บันทึก
  void _onLongPressDownVideo() async {
    if (_isRecording || _prepCountdown > 0) return;

    // บังคับให้เลือก category ก่อน
    if (_selectedEmergencyCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาเลือกประเภทเหตุฉุกเฉินก่อนเริ่มบันทึก'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // เริ่มนับถอยหลัง
    setState(() => _prepCountdown = _prepSeconds);

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        if (_prepCountdown > 1) {
          _prepCountdown--;
        } else {
          _prepCountdown = 0;
          timer.cancel();
          _startEmergencyRecording();
        }
      });
    });
  }

  void _onLongPressEndCancelVideo() {
    // If released during prep, just cancel prep.
    if (_prepCountdown > 0) {
       _countdownTimer?.cancel();
       setState(() {
         _prepCountdown = 0;
       });
       return;
    }
    
    // If released while actively recording, stop and upload.
    if (_isRecording) {
      _stopEmergencyRecording();
    }
  }

  Future<void> _startEmergencyRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      await _initCamera();
    }
    
    if (_cameraController == null || _isRecording) return;

    try {
      await _cameraController!.startVideoRecording();
      _recordingStartTime = DateTime.now();
      _recordedGpsTracks = [];
      _isRecording = true;
      _recordingTimeLeft = SyncConfig.maxEmergencyRecordingSeconds;
      
      // Sample GPS immediately
      try {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        _recordedGpsTracks.add({
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'timestampOffset': 0,
        });
      } catch (e) {
        debugPrint("Initial GPS Sampling Error: $e");
      }
      
      // Start Duration Timer
      _durationTimer?.cancel();
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
         if (!mounted) {
           timer.cancel();
           return;
         }
         setState(() {
           if (_recordingTimeLeft > 0) {
             _recordingTimeLeft--;
           } else {
             // Maximum duration reached, force stop.
             _stopEmergencyRecording();
           }
         });
      });

      // Start GPS Sampling every 5 seconds
      _gpsTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        try {
          Position pos = await Geolocator.getCurrentPosition();
          int offset = DateTime.now().difference(_recordingStartTime!).inSeconds;
          _recordedGpsTracks.add({
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'timestampOffset': offset,
          });
          debugPrint("DEBUG: Sampled GPS at offset $offset");
        } catch (e) {
          debugPrint("GPS Sampling Error: $e");
        }
      });
      
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Error starting recording: $e");
    }
  }

  Future<void> _stopEmergencyRecording() async {
    _durationTimer?.cancel();
    if (_cameraController == null || !_isRecording) return;

    try {
      XFile videoFile = await _cameraController!.stopVideoRecording();
      if (_gpsTimer != null) _gpsTimer!.cancel();
      _isRecording = false;
      
      if (mounted) setState(() {});
      
      // Proceed to Upload
      _uploadIncident(File(videoFile.path));
    } catch (e) {
      debugPrint("Error stopping recording: $e");
    }
  }

  // ===================== PHOTO RECORDING LOGIC =====================

  Future<void> _takePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      await _initCamera();
    }
    
    if (_cameraController == null) return;
    
    if (_capturedPhotos.length >= VideoRepository.maxEmergencyPhotos) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ถ่ายรูปได้สูงสุด ${VideoRepository.maxEmergencyPhotos} รูป'), 
            backgroundColor: Colors.red
          ),
        );
      }
      return;
    }

    try {
      XFile photo = await _cameraController!.takePicture();
      setState(() {
        _capturedPhotos.add(photo);
      });
      // Capture exactly one GPS point for the photo immediately (if empty)
      if (_recordedGpsTracks.isEmpty) {
         try {
           Position pos = await Geolocator.getCurrentPosition();
           _recordedGpsTracks.add({
             'latitude': pos.latitude,
             'longitude': pos.longitude,
             'timestampOffset': 0,
           });
         } catch(e) {
           debugPrint("Photo GPS Capture Error: $e");
         }
      }
    } catch (e) {
      debugPrint("Error taking photo: $e");
    }
  }

  Future<void> _sendPhotos() async {
    if (_capturedPhotos.isEmpty) return;

    String? categoryId = _selectedEmergencyCategoryId;

    if (categoryId == null) {
      // Fallback only if somehow not selected
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      
      List<DonationCategory> categories = [];
      try {
        categories = await ServiceLocator.instance.donationRepository.getEmergencyCategories();
      } catch (e) {
        debugPrint("Error fetching emergency categories: $e");
      }
      
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (categories.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ยังไม่มีหมวดหมู่เหตุฉุกเฉินในระบบ กรุณาติดต่อผู้ดูแล'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      if (!mounted) return;
      final selectedCategory = await showModalBottomSheet<DonationCategory>(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('เลือกหมวดหมู่เหตุฉุกเฉิน', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final cat = categories[index];
                      return ListTile(
                        leading: const Icon(Icons.emergency, color: Colors.red),
                        title: Text(cat.name),
                        onTap: () => Navigator.pop(context, cat),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );

      if (selectedCategory == null) return;
      categoryId = selectedCategory.id;
    }

    // Show loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('กำลังอัปโหลดรูปภาพเหตุฉุกเฉิน...'),
          ],
        ),
      ),
    );

    try {
      final userId = ServiceLocator.instance.currentUser?.id;
      if (userId == null) throw Exception("User not logged in");

      List<File> filesToUpload = _capturedPhotos.map((x) => File(x.path)).toList();

      final videoId = await ServiceLocator.instance.videoRepository.uploadEmergencyPhotos(
        userId: userId,
        photoFiles: filesToUpload,
        gpsTracks: _recordedGpsTracks,
        categoryId: categoryId,
        isThaiMhung: _isThaiMhungReporting,
      );

      // Trigger Notification
      final ws = WebSocketService();
      debugPrint('EmergencyLivePage: About to sendEmergencyAlert. WS connected=${ws.isConnected}, videoId=$videoId, categoryId=$categoryId');
      if (!ws.isConnected) {
        debugPrint('EmergencyLivePage: ⚠️ WS NOT CONNECTED! Attempting reconnect...');
        await _ensureWebSocketConnected();
      }
      ws.sendEmergencyAlert(
        userId: userId,
        categoryId: categoryId,
        videoId: videoId,
        type: 'photo',
        isThaiMhungEnabled: true, // Enable Thai Mhung channel for all emergency reports
      );
      debugPrint('EmergencyLivePage: ✅ sendEmergencyAlert called for photos');

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('อัปโหลดรูปภาพฉุกเฉินสำเร็จ'), backgroundColor: Colors.green),
      );
      setState(() {
         _capturedPhotos.clear();
         _recordedGpsTracks.clear();
         _selectedTab = 0; // Switch to live view
      });
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ===================== VIDEO UPLOAD LOGIC =====================

  Future<void> _uploadIncident(File file) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('กำลังอัปโหลดข้อมูลเหตุฉุกเฉิน...'),
          ],
        ),
      ),
    );

    try {
      final userId = ServiceLocator.instance.currentUser?.id;
      if (userId == null) throw Exception("User not logged in");

      final videoId = await ServiceLocator.instance.videoRepository.uploadEmergencyVideo(
        userId: userId,
        videoFile: file,
        gpsTracks: _recordedGpsTracks,
        categoryId: _selectedEmergencyCategoryId,
      );

      // ✅ Immediate Preview: เพิ่มวิดีโอนี้ลงใน Feed ทันทีด้วย Local Path
      if (videoId != null && mounted) {
        final newVideo = Video(
          id: videoId,
          userId: userId,
          title: 'Emergency Incident',
          type: VideoType.emergency,
          status: VideoStatus.processing,
          latitude: _recordedGpsTracks.isNotEmpty ? _recordedGpsTracks.last['latitude'] : 0.0,
          longitude: _recordedGpsTracks.isNotEmpty ? _recordedGpsTracks.last['longitude'] : 0.0,
          createdAt: DateTime.now(),
          localFilePath: file.path, 
          categoryId: _selectedEmergencyCategoryId,
          categoryName: _selectedEmergencyCategory?.name ?? 'เหตุฉุกเฉิน',
        );
        
        setState(() {
          _trendingVideos.insert(0, newVideo);
          _currentVideoId = videoId;
          _currentVideo = newVideo;
        });

        // ✅ เรียกใช้งานฟังก์ชันที่จำเป็นทันทีโดยไม่ต้องรอ WebSocket หรือ API Sync
        _initializePlayer(file.path, isLocal: true);
        _checkPrivacyPermissions();
      }

      // Trigger Notification
      if (_selectedEmergencyCategoryId != null) {
        final ws = WebSocketService();
        debugPrint('EmergencyLivePage: About to sendEmergencyAlert for video. WS connected=${ws.isConnected}, videoId=$videoId, categoryId=$_selectedEmergencyCategoryId');
        if (!ws.isConnected) {
          debugPrint('EmergencyLivePage: ⚠️ WS NOT CONNECTED for video! Attempting reconnect...');
          await _ensureWebSocketConnected();
        }
        ws.sendEmergencyAlert(
        userId: userId,
        categoryId: _selectedEmergencyCategoryId ?? '',
        videoId: videoId,
        type: 'video',
        isThaiMhungEnabled: true, // Enable Thai Mhung channel for all emergency reports
      );
        debugPrint('EmergencyLivePage: ✅ sendEmergencyAlert called for video');
      }

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('อัปโหลดเหตุฉุกเฉินสำเร็จ ระบบกำลังประมวลผล'), backgroundColor: Colors.green),
      );
      setState(() => _selectedTab = 0); // Switch to live view
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
      );
    }
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
          MapBackgroundWidget(
            currentVideoId: _currentVideoId,
            currentVideo: _currentVideo,
            routePoints: _routePoints,
            userLocation: _userLocation,
            responders: _responders,
            selectedTab: _selectedTab,
            onMapCreated: (controller) {
              debugPrint("DEBUG: Google Map Created Successfully");
              _mapController = controller;
              Future.delayed(const Duration(milliseconds: 500), () {
                _adjustMapBounds();
              });
            },
            onTap: () {
              if (_selectedTab != 0 || _isThaiMhungReporting) {
                setState(() {
                  _selectedTab = 0;
                  _isThaiMhungReporting = false;
                });
              }
            },
          ),
          
          // === Layer 1.1: Responder Compass (Orientation pointer) ===
          if (_currentResponseId != null && _userLocation != null && (_routePoints.isNotEmpty || (_currentVideo?.latitude != null && _currentVideo?.longitude != null)))
            Positioned(
              top: 100,
              right: 16,
              child: ResponderCompassWidget(
                userLocation: _userLocation,
                destinationLocation: _routePoints.isNotEmpty 
                  ? _routePoints.last 
                  : LatLng(_currentVideo!.latitude, _currentVideo!.longitude),
                deviceHeading: _deviceHeading,
              ),
            ),

          // === Layer 1.5: Thai Mhung Gallery (On top of map) ===
          if (_selectedTab == 0 && !_isThaiMhungReporting && _thaiMhungPhotos.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 150, // Above bottom tabs
              child: ThaiMhungGalleryWidget(
                photos: _thaiMhungPhotos,
                onPhotoTap: _showPhotoDetail,
                canViewUnblurred: _canViewUnblurred,
              ),
            ),

          Positioned.fill(
            child: SafeArea(
              left: false,
              right: false,
              child: Column(
                children: [
                  if (!_isConnected) const OfflineIndicatorWidget(),
                  
                  // 2. Back Button (Green arrow)
                  const ControlBackButtonWidget(),

                  // 3. Main Split Content based on Tab (Index 0: Live, 1: Relation, 2: Report)
                  Expanded(
                    child: SingleChildScrollView(
                      child: _selectedTab == 0
                          ? (_isThaiMhungReporting 
                              ? IncidentReportWidget(
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
                                  onCategorySelected: (DonationCategory cat) => setState(() {
                                    _selectedEmergencyCategoryId = cat.id;
                                    _selectedEmergencyCategory = cat;
                                  }),
                                  onModeChanged: (photoMode) => setState(() => _isPhotoMode = photoMode),
                                  onLoadCategories: _loadEmergencyCategories,
                                  onYieldWay: _yieldWay,
                                  isThaiMhungMode: true,
                                )
                              : LiveViewWidget(
                                  chewieController: _chewieController,
                                  currentVideoId: _currentVideoId,
                                  currentVideo: _currentVideo,
                                  formattedViewerCount: _formatCount(_viewerCount),
                                  likeCountFormatted: _formatCount(_likeCount),
                                  donationTotalFormatted: '${_donationTotal.toStringAsFixed(0)}บ.',
                                  trendingVideos: _trendingVideos,
                                  isLoadingTrending: _isLoadingTrending,
                                  canViewUnblurred: _canViewUnblurred,
                                  onLike: () async {
                                    final userId = AuthService.instance.currentUser?.id ?? 'anonymous';
                                    if (_currentVideoId != null) {
                                      try {
                                        final interaction = VideoInteraction(
                                          id: '',
                                          videoId: _currentVideoId!,
                                          userId: userId,
                                          type: 'like',
                                          createdAt: DateTime.now(),
                                        );
                                        await ServiceLocator.instance.videoRepository.addInteraction(interaction);
                                      } catch (e) {
                                        debugPrint('Error sending like: $e');
                                      }
                                    }
                                  },
                                  onDonate: _showDonationSheet,
                                  onSwitchVideo: _switchVideo,
                                ))
                          : _selectedTab == 1
                              ? GestureDetector(
                                  onTap: () => setState(() {
                                    _selectedTab = 0;
                                    _isThaiMhungReporting = false;
                                  }),
                                  behavior: HitTestBehavior.translucent,
                                  child: const RelationshipViewWidget(),
                                )
                              : GestureDetector(
                                  onTap: () => setState(() {
                                    _selectedTab = 0;
                                    _isThaiMhungReporting = false;
                                  }),
                                  behavior: HitTestBehavior.translucent,
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
                                  onCategorySelected: (DonationCategory cat) => setState(() {
                                    _selectedEmergencyCategoryId = cat.id;
                                    _selectedEmergencyCategory = cat;
                                  }),
                                  onModeChanged: (photoMode) => setState(() => _isPhotoMode = photoMode),
                                  onLoadCategories: _loadEmergencyCategories,
                                  onYieldWay: () {}, // Not used in incident report tab
                                ),
                              ),
                    ),
                  ),

                  // 4. Rescue Control Panel (Only if viewing target video + has responseId)
                  if (_currentResponseId != null && _selectedTab == 0)
                     RescueControlPanelWidget(
                       onOpenInMaps: _openInGoogleMaps,
                       onUpdateStatus: _updateRescueStatus,
                     ),

                  // 4.5. Rescue Accept Panel (If eligible responder and not accepted yet)
                  if (_isEligibleResponder() && _selectedTab == 0)
                    RescueAcceptPanelWidget(
                      onAccept: _acceptRescue,
                    ),

                  BottomTabsWidget(
                    selectedTab: _selectedTab,
                    blinkAnimation: _liveBlinkController,
                    showThaiMhung: _currentVideoId != null, 
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
                      setState(() {
                        _selectedTab = 2;
                        _isThaiMhungReporting = false;
                      });
                      await _loadConfigFromDatabase();
                      if (_emergencyCategories.isEmpty) {
                        _loadEmergencyCategories();
                      }
                      _initCamera();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _initializePlayer(String url, {bool isLocal = false}) async {
    if (_videoPlayerController != null) {
      await _videoPlayerController!.dispose();
      _videoPlayerController = null;
    }

    if (isLocal) {
      _videoPlayerController = VideoPlayerController.file(File(url));
    } else {
      _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
    }
    
    await _videoPlayerController!.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      showControls: true,
      materialProgressColors: ChewieProgressColors(
        playedColor: Colors.red,
        handleColor: Colors.redAccent,
        backgroundColor: Colors.grey,
        bufferedColor: Colors.white,
      ),
    );

    _videoPlayerController!.addListener(_syncGpsWithVideo);

    if (mounted) {
      setState(() {});
    }
  }

  void _syncGpsWithVideo() {
    if (_videoPlayerController == null || !_videoPlayerController!.value.isPlaying) return;
    if (_dbGpsTracks.isEmpty) return;

    final currentPositionSeconds = _videoPlayerController!.value.position.inSeconds;

    List<LatLng> newRoute = [];
    VideoGpsTrack? lastTrack;
    
    for (var track in _dbGpsTracks) {
      if (track.timestampOffset <= currentPositionSeconds) {
        newRoute.add(LatLng(track.latitude, track.longitude));
        lastTrack = track;
      } else {
        break;
      }
    }

    if (lastTrack != null && lastTrack != _lastSyncedVideoTrack) {
      _lastSyncedVideoTrack = lastTrack;
      if (mounted) {
        setState(() {
          _routePoints.clear();
          _routePoints.addAll(newRoute);
        });
      }
    }
  }

  void _showDonationSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DonationSheetWidget(
          onDonate: (amount) async {
            final userId = AuthService.instance.currentUser?.id;
            if (_currentVideoId != null && userId != null) {
              try {
                WebSocketService().sendVideoInteraction(
                  _currentVideoId!,
                  userId,
                  'gift',
                  value: amount,
                );
                
                await ServiceLocator.instance.donationRepository.addContribution({
                  'user_id': userId,
                  'request_id': _currentVideo?.donationRequestId,
                  'amount': amount.toDouble(),
                  'status': 'pending',
                  'payment_method': 'app_transfer',
                });

                if (!context.mounted) return;
                
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'บันทึกคำขอบริจาค $amount บาท สำเร็จ และกำลังเข้าสู่ขั้นตอนชำระเงิน 🙏',
                      style: const TextStyle(fontFamily: 'SukhumvitSet'),
                    ),
                    backgroundColor: const Color(0xFF4CAF50),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
               } catch (e) {
                 if (!context.mounted) return;
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('เกิดข้อผิดพลาดในการบริจาค')),
                 );
               }
            } else {
              setState(() => _donationTotal += amount);
              Navigator.pop(context);
            }
          },
        );
      },
    );
  }

  void _onThaiMhungTabSelected() async {
    if (_currentVideo == null) {
      setState(() => _selectedTab = 0);
      return;
    }

    // 1. Check GPS enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กรุณาเปิดระบบระบุตำแหน่ง (GPS) เพื่อทำหน้าที่ไทยมุง')),
        );
      }
      return;
    }

    // 2. Check Distance
    if (_userLocation == null) {
       // Try to get location if null
       try {
         final pos = await Geolocator.getCurrentPosition();
         setState(() {
           _userLocation = LatLng(pos.latitude, pos.longitude);
         });
       } catch (e) {
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('ไม่สามารถดึงตำแหน่งปัจจุบันของคุณได้')),
           );
         }
         return;
       }
    }

    if (_userLocation != null && _currentVideo != null) {
      final double distanceInMeters = Geolocator.distanceBetween(
        _userLocation!.latitude,
        _userLocation!.longitude,
        _currentVideo!.latitude,
        _currentVideo!.longitude,
      );

      // ✅ ใช้ alertRadius จาก User Profile แทนค่า hardcoded
      // fallback = 500 เมตร เฉพาะกรณีที่ผู้ใช้ยังไม่ได้ login
      final int userAlertRadius = AuthService.instance.currentUser?.alertRadius ?? 500;

      if (distanceInMeters > userAlertRadius) {
        if (mounted) {
          final String radiusDisplay = userAlertRadius >= 1000
              ? '${(userAlertRadius / 1000).toStringAsFixed(1)} กม.'
              : '$userAlertRadius ม.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'คุณอยู่ไกลจากจุดเกิดเหตุเกินไปสำหรับการทำหน้าที่ไทยมุง '
                '(ห่าง ${distanceInMeters.toStringAsFixed(0)} เมตร, รัศมีของคุณ: $radiusDisplay)',
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    // 3. Success -> Go to Thai Mhung Mode
    setState(() {
      _selectedTab = 0;
      _isThaiMhungReporting = true;
      _isPhotoMode = true; // Always photo for Thai Mhung
    });
    
    // Trigger Camera for Thai Mhung
    await _loadConfigFromDatabase();
    if (_emergencyCategories.isEmpty) {
      await _loadEmergencyCategories();
    }
    _initCamera();
    _loadThaiMhungPhotos();
  }

  Future<void> _loadThaiMhungPhotos() async {
    if (_currentVideo == null || _currentVideo?.categoryId == null) return;
    
    try {
      final photos = await ServiceLocator.instance.videoRepository.getThaiMhungPhotos(_currentVideo!.categoryId!);
      setState(() {
        _thaiMhungPhotos = photos.map((v) => ThaiMhungPhoto(
          id: v.id,
          url: v.bunnyUrl ?? '',
          userName: v.userName,
        )).where((p) => p.url.isNotEmpty).toList();
      });
    } catch (e) {
      debugPrint("Error loading Thai Mhung photos: $e");
    }
  }

  /// ✅ ไทยมุงช่วยกดปุ่ม "ให้ทาง" (Yield Way Feedback System §4)
  Future<void> _yieldWay() async {
    if (_currentVideoId == null) return;
    
    final userId = AuthService.instance.currentUser?.id ?? 'anonymous';
    try {
      final interaction = VideoInteraction(
        id: '',
        videoId: _currentVideoId!,
        userId: userId,
        type: 'yield_way', // เป็น Interaction ประเภทใหม่ตามแผน
        createdAt: DateTime.now(),
      );
      
      await ServiceLocator.instance.videoRepository.addInteraction(interaction);
      
      // บอก Server ผ่าน WebSocket เผื่อเอาไปนับสถิติ Real-time แบบภาพรวม
      final socket = WebSocketService().socket;
      if (socket != null && socket.connected) {
        socket.emit('yield-way-click', {
          'videoId': _currentVideoId,
          'userId': userId,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ขอบคุณที่ช่วยเปิดทางให้รถฉุกเฉิน! 🚑💙'),
            backgroundColor: Colors.blue,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sending yield way: $e');
    }
  }

  void _showPhotoDetail(ThaiMhungPhoto photo) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(
                photo.url,
                fit: BoxFit.contain,
              ),
            ),
            if (photo.userName != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'โดย: ${photo.userName}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
