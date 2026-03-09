import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/glassmorphism_button.dart';
import '../../../../config/app_config.dart';
import '../../../../config/sync_config.dart';
import '../../../../services/websocket_service.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../data/repositories/video_repository.dart';
import '../../../donation/models/donation_models.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:intl/intl.dart';
import '../../models/video_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  int _viewerCount = 0;
  int _likeCount = 0;
  double _donationTotal = 0.0;
  RealtimeChannel? _supabaseInteractionSub;
  LatLng? _userLocation;
  bool _isConnected = true;
  String? _currentVideoId;
  late AnimationController _liveBlinkController;
  late AnimationController _pulseController;
  GoogleMapController? _mapController;
  
  StreamSubscription? _connectionSub;
  StreamSubscription? _interactionSub;
  StreamSubscription? _progressSub;
  StreamSubscription? _rescueIncomingSub;
  StreamSubscription? _videoStatusSub;
  
  // Video Player & Map Sync
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  List<VideoGpsTrack> _dbGpsTracks = [];
  
  // Custom logic to avoid resetting polyline too often
  VideoGpsTrack? _lastSyncedVideoTrack;
  
  // Responders data
  List<Map<String, dynamic>> _responders = [];

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
  List<XFile> _capturedPhotos = [];
  
  // GPS Route Points for the currently watched video
  final List<LatLng> _routePoints = [];

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

    _liveBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    _checkPermissions();
    _setupWebSocketStreams();
    _loadInitialData();
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
    if (_currentVideoId != null) {
      final summary = await ServiceLocator.instance.videoRepository
          .getInteractionSummary(_currentVideoId!);
      setState(() {
        _likeCount = summary['likes'] ?? 0;
        _donationTotal = summary['donations']?.toDouble() ?? 0.0;
        _viewerCount = summary['views'] ?? 0;
      });
      
      _recordView();

      // Fetch Video and handle reproduction
      final video = await ServiceLocator.instance.videoRepository.getVideoById(_currentVideoId!);
      if (video != null && video.bunnyUrl != null) {
         _initializePlayer(video.bunnyUrl!);
      }
      
      // Fetch GPS Tracks for the video
      final tracks = await ServiceLocator.instance.videoRepository.getGpsTracks(_currentVideoId!);
      if (tracks.isNotEmpty) {
          _dbGpsTracks = tracks;
      }
    }

    // Fetch trending videos
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
        setState(() {
          _isLoadingTrending = false;
        });
      }
    }
    
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
          for (int i = 0; i < responders.length; i++) {
            var r = responders[i];
            r['currentLat'] = r['startLat'];
            r['currentLng'] = r['startLng'];
            // If they don't have a start location, their progress won't be drawn.
            r['estimatedMinutes'] = 0;
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

  void _setupWebSocketStreams() {
    final ws = WebSocketService();
    
    // 1. Connection Status
    _connectionSub = ws.connectionStream.listen((connected) {
      setState(() => _isConnected = connected);
    });

    // 2. Video Interactions (Likes, Gifts, Views) Realtime
    if (_currentVideoId != null) {
      // Subscribe via WebSocket if still needed globally
      ws.joinVideoRoom(_currentVideoId!);
      _interactionSub = ws.videoInteractionStream.listen((data) {
        if (data['videoId'] == _currentVideoId) {
          setState(() {
            if (data['type'] == 'like') _likeCount++;
            if (data['type'] == 'gift') _donationTotal += (data['value'] ?? 0);
          });
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

    // 3. Progress / GPS (Simulated move for demo, but wired to logic)
    _progressSub = ws.videoProgressStream.listen((data) {
      if (data['videoId'] == _currentVideoId && data['location'] != null) {
        final loc = data['location'];
        final point = LatLng(loc['lat'], loc['lng']);
        setState(() {
          _routePoints.add(point);
        });
      }
    });

    // 4. Rescue Incoming Status Feedback
    _rescueIncomingSub = ws.rescueIncomingStream.listen((data) {
      if (mounted) {
         final status = data['status'];
         String msg = '';
         if (status == 'accepted') msg = 'กู้ภัยกำลังเดินทางมาหาคุณ...';
         else if (status == 'arrived') msg = 'กู้ภัยเดินทางมาถึงที่เกิดเหตุแล้ว!';
         else if (status == 'resolved') msg = 'ภารกิจของกู้ภัยเสร็จสิ้น!';
         
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

  void _switchVideo(String newVideoId) {
    if (_currentVideoId != null) {
      WebSocketService().leaveVideoRoom(_currentVideoId!);
    }
    
    _interactionSub?.cancel();
    _supabaseInteractionSub?.unsubscribe();
    _progressSub?.cancel();
    _rescueIncomingSub?.cancel();
    _videoStatusSub?.cancel();
    
    _videoPlayerController?.removeListener(_syncGpsWithVideo);
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
    _chewieController?.dispose();
    _chewieController = null;
    
    setState(() {
      _currentVideoId = newVideoId;
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

    // Show category selection first
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
    
    if (mounted) Navigator.pop(context); // Close loading dialog

    if (categories.isEmpty) {
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('ยังไม่มีหมวดหมู่เหตุฉุกเฉินในระบบ กรุณาติดต่อผู้ดูแล'), backgroundColor: Colors.red),
         );
       }
       return;
    }

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
    String categoryId = selectedCategory.id;

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
            Text('กำลังอัปโหลดรูปภาพเหตุฉุกเฉิน...'),
          ],
        ),
      ),
    );

    try {
      final userId = ServiceLocator.instance.currentUser?.id;
      if (userId == null) throw Exception("User not logged in");

      List<File> filesToUpload = _capturedPhotos.map((x) => File(x.path)).toList();

      await ServiceLocator.instance.videoRepository.uploadEmergencyPhotos(
        userId: userId,
        photoFiles: filesToUpload,
        gpsTracks: _recordedGpsTracks,
        categoryId: categoryId,
      );

      // Trigger Notification
      WebSocketService().sendEmergencyAlert(
        userId: userId,
        categoryId: categoryId,
        type: 'photo',
      );

      if (mounted) Navigator.pop(context); // Close loading

      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปโหลดรูปภาพฉุกเฉินสำเร็จ'), backgroundColor: Colors.green),
        );
        setState(() {
           _capturedPhotos.clear();
           _recordedGpsTracks.clear();
           _selectedTab = 0; // Switch to live view
        });
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
        );
      }
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

      await ServiceLocator.instance.videoRepository.uploadEmergencyVideo(
        userId: userId,
        videoFile: file,
        gpsTracks: _recordedGpsTracks,
        categoryId: _selectedEmergencyCategoryId,
      );

      // Trigger Notification
      if (_selectedEmergencyCategoryId != null) {
        WebSocketService().sendEmergencyAlert(
          userId: userId,
          categoryId: _selectedEmergencyCategoryId!,
          type: 'video',
        );
      }

      if (mounted) Navigator.pop(context); // Close loading

      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปโหลดเหตุฉุกเฉินสำเร็จ ระบบกำลังประมวลผล'), backgroundColor: Colors.green),
        );
        setState(() => _selectedTab = 0); // Switch to live view
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
        );
      }
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
          _buildMapBackground(),

          // === Layer 2: All Overlays ===
          SafeArea(
            left: false,
            right: false,
            child: Column(
              children: [
                if (!_isConnected) _buildOfflineIndicator(),
                
                // 1. "Emergency" Header
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Emergency',
                      style: TextStyle(
                        fontFamily: 'SukhumvitSet',
                        fontSize: 22, // Increased size
                        fontWeight: FontWeight.w900, // Bolder
                        color: Colors.black87, // Darker
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // 2. Driver Info Row (Avatar Left, Name Right)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDriverAvatar(),
                      const Spacer(),
                      _buildDriverNameAndTitle(),
                    ],
                  ),
                ),

                // 3. Main Split Content based on Tab (Index 0: Live, 1: Relation, 2: Report)
                Expanded(
                  child: _selectedTab == 0
                      ? _buildLiveView()
                      : _selectedTab == 1
                          ? _buildRelationshipView()
                          : _buildIncidentReportView(),
                ),

                // Bottom Tabs (Live, ความสัมพันธ์, แจ้งเหตุ)
                _buildBottomTabs(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveView() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Left Column ---
        Expanded(
          flex: 11,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              // Back Arrow (Green in draft)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(Icons.arrow_back, color: Colors.green[700], size: 28),
                ),
              ),
              const SizedBox(height: 15),
              _buildVideoPlayer(),
              const SizedBox(height: 8),
              _buildStatusBar(),
              const SizedBox(height: 8),
              _buildViewerCount(),
              const SizedBox(height: 20),
              _buildActionButtons(),
            ],
          ),
        ),
        // --- Right Column ---
        Expanded(
          flex: 9,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(height: 10),
              _buildTrendingPanel(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRelationshipView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_alt_outlined, size: 80, color: Colors.purple[200]),
          const SizedBox(height: 16),
          Text(
            'ความสัมพันธ์ในพื้นที่',
            style: TextStyle(
              fontFamily: 'SukhumvitSet',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.purple[900],
            ),
          ),
          const SizedBox(height: 8),
          const Text('ข้อมูลอาสาสมัครและเครือข่ายความช่วยเหลือ'),
        ],
      ),
    );
  }

  Widget _buildIncidentReportView() {
    final bool categorySelected = _selectedEmergencyCategoryId != null;
    final bool canRecord = categorySelected && !_isLoadingCategories;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),

          // ─── Camera Preview + Category Overlay ─────────────────────
          Container(
            height: 280,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isRecording ? Colors.red : (categorySelected ? Colors.green : Colors.white24),
                width: _isRecording ? 2.5 : 1.5,
              ),
            ),
            child: Stack(
              children: [
                // Camera view
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _cameraController != null && _cameraController!.value.isInitialized
                      ? SizedBox.expand(child: CameraPreview(_cameraController!))
                      : const Center(child: Icon(Icons.camera_alt, color: Colors.white38, size: 48)),
                ),

                // ─── Category chips overlay (bottom of camera) ─────
                if (!_isRecording && _prepCountdown == 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black.withOpacity(0.85), Colors.transparent],
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(14),
                          bottomRight: Radius.circular(14),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Label row
                          Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: categorySelected ? Colors.green : Colors.red.shade700,
                                ),
                                child: Center(
                                  child: categorySelected
                                      ? const Icon(Icons.check, color: Colors.white, size: 13)
                                      : const Text('!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                categorySelected
                                    ? 'ประเภท: ${_selectedEmergencyCategory?.name ?? ""}'
                                    : 'เลือกประเภทเหตุฉุกเฉิน',
                                style: TextStyle(
                                  color: categorySelected ? Colors.greenAccent : Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Chips
                          if (_isLoadingCategories)
                            const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          else if (_emergencyCategories.isEmpty)
                            GestureDetector(
                              onTap: _loadEmergencyCategories,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh, color: Colors.white, size: 14),
                                    SizedBox(width: 6),
                                    Text('โหลดใหม่', style: TextStyle(color: Colors.white, fontSize: 12)),
                                  ],
                                ),
                              ),
                            )
                          else
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _emergencyCategories.map((cat) {
                                  final selected = _selectedEmergencyCategoryId == cat.id;
                                  return GestureDetector(
                                    onTap: () => setState(() {
                                      _selectedEmergencyCategoryId = cat.id;
                                      _selectedEmergencyCategory = cat;
                                    }),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: selected ? Colors.red : Colors.black54,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: selected ? Colors.red.shade300 : Colors.white38,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Text(
                                        cat.name,
                                        style: TextStyle(
                                          color: selected ? Colors.white : Colors.white70,
                                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                // ─── Mode toggle (top-right corner) ────────────────
                if (!_isRecording && _prepCountdown == 0)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _isPhotoMode = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: !_isPhotoMode ? Colors.red : Colors.transparent,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: const Text('Video', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _isPhotoMode = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _isPhotoMode ? Colors.red : Colors.transparent,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: const Text('Photo', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ─── Countdown overlay ──────────────────────────────
                if (_prepCountdown > 0)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_prepCountdown',
                            style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const Text('กำลังเริ่มบันทึก...', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        ],
                      ),
                    ),
                  ),

                // ─── Recording badge (top-left) ─────────────────────
                if (_isRecording)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.red, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(_recordingTimeLeft ~/ 60).toString().padLeft(2, '0')}:${(_recordingTimeLeft % 60).toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),


          // ─── Photo Thumbnails ────────────────────────────────────────
          if (_isPhotoMode && _capturedPhotos.isNotEmpty) ...[
            SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _capturedPhotos.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      image: DecorationImage(
                        image: FileImage(File(_capturedPhotos[index].path)),
                        fit: BoxFit.cover,
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        onTap: () => setState(() => _capturedPhotos.removeAt(index)),
                        child: const Icon(Icons.cancel, color: Colors.white, size: 20),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ─── Step 2: ปุ่มบันทึก ─────────────────────────────────────
          Opacity(
            opacity: canRecord ? 1.0 : 0.45,
            child: _isPhotoMode
                ? Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: GestureDetector(
                          onTap: canRecord ? _takePhoto : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.red, width: 2),
                            ),
                            child: const Center(child: Icon(Icons.camera_alt, color: Colors.red, size: 30)),
                          ),
                        ),
                      ),
                      if (_capturedPhotos.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            onTap: _sendPhotos,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFFFF3B30), Color(0xFFFF2D55)]),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: Text(
                                  'ส่งรูปภาพ',
                                  style: TextStyle(fontFamily: 'SukhumvitSet', fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                // ─── Video Hold-to-Record Button ─────────────────────
                : GestureDetector(
                    onLongPressDown: canRecord ? (_) => _onLongPressDownVideo() : null,
                    onLongPressEnd: (_) => _onLongPressEndCancelVideo(),
                    onLongPressCancel: () => _onLongPressEndCancelVideo(),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isRecording
                              ? [Colors.black87, Colors.black]
                              : canRecord
                                  ? [const Color(0xFFFF3B30), const Color(0xFFFF2D55)]
                                  : [Colors.grey.shade700, Colors.grey.shade800],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording ? Colors.black : canRecord ? Colors.red : Colors.grey)
                                .withOpacity(0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isRecording ? Icons.stop_circle : Icons.videocam,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _isRecording
                                ? 'ปล่อยเพื่อหยุดและส่ง'
                                : canRecord
                                    ? 'กดค้างเพื่อเริ่มบันทึก'
                                    : 'เลือกประเภทเหตุก่อน',
                            style: const TextStyle(
                              fontFamily: 'SukhumvitSet',
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _simulateStartLiveRecording() {
    // Show a dialog simulating camera start
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('กำลังเริ่มต้นการถ่ายทอดสด...'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.red),
            SizedBox(height: 20),
            Text('เชื่อมต่อกับเซิร์ฟเวอร์ Bunny.net และส่งพิกัด GPS...'),
          ],
        ),
      ),
    );
    
    // After 2 seconds, switch back to Live tab with a mock "Sending" state
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context); // Close dialog
        setState(() {
          _selectedTab = 0; // Switch to Live View
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เริ่มการแจ้งเหตุสำเร็จ! ระบบกำลังบันทึกวิดีโอและตำแหน่งของคุณ'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  Widget _buildMapBackground() {
    Set<Marker> mapMarkers = {};
    
    // 1. Incident Marker
    if (_currentVideoId != null && _routePoints.isNotEmpty) {
      mapMarkers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: _routePoints.last,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'จุดเกิดเหตุ'),
        )
      );
    }
    
    // 2. Responders Markers
    int responderIndex = 0;
    if (_currentVideoId != null) {
      for (var r in _responders) {
        if (r['currentLat'] != null && r['currentLng'] != null) {
        // Build subtitle string
        int mins = r['estimatedMinutes'] as int? ?? 0;
        double speedKmh = (r['currentSpeed'] as double? ?? 0) * 3.6;
        String subtitle = mins == 0 
           ? 'ถึงที่เกิดเหตุแล้ว' 
           : 'อีก $mins นาที (${speedKmh.toStringAsFixed(0)} กม./ชม.)';
           
        // กำหนดสีหมุดตามสีของอาชีพ (Profession colorHex) หรือ Rainbow Mode หากไม่ระบุสี
        double fallbackHue;
        switch (responderIndex % 6) {
          case 0: fallbackHue = BitmapDescriptor.hueRed; break;
          case 1: fallbackHue = BitmapDescriptor.hueOrange; break;
          case 2: fallbackHue = BitmapDescriptor.hueYellow; break;
          case 3: fallbackHue = BitmapDescriptor.hueGreen; break;
          case 4: fallbackHue = BitmapDescriptor.hueBlue; break;
          case 5: fallbackHue = BitmapDescriptor.hueViolet; break;
          default: fallbackHue = BitmapDescriptor.hueOrange;
        }

        double markerHue = fallbackHue;
        if (r['professionColor'] != null) {
          try {
            final hex = (r['professionColor'] as String).replaceAll('#', '');
            if (hex.length == 6) {
              final color = Color(int.parse('FF$hex', radix: 16));
              markerHue = HSVColor.fromColor(color).hue;
            }
          } catch (_) {}
        }

        mapMarkers.add(
          Marker(
            markerId: MarkerId('responder_${r['id']}'),
            position: LatLng(r['currentLat'], r['currentLng']),
            icon: BitmapDescriptor.defaultMarkerWithHue(markerHue), 
            infoWindow: InfoWindow(
               title: '${r['professionName']} - ${r['volunteerName']}',
               snippet: subtitle,
            ),
          )
        );
        responderIndex++;
      }
    }
  }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Layer 1: Google Map (native platform view)
        GoogleMap(
          key: ValueKey(_currentVideoId),
          onMapCreated: (controller) {
            debugPrint("DEBUG: Google Map Created Successfully");
            _mapController = controller;
            
            // Adjust camera if we have responders to show a wider view using bounds
            Future.delayed(const Duration(milliseconds: 500), () {
               _adjustMapBounds();
            });
          },
          initialCameraPosition: CameraPosition(
            target: _routePoints.isNotEmpty
                ? _routePoints.last
                : (_userLocation ?? const LatLng(13.7367, 100.5604)),
            zoom: 15.0,
          ),
          zoomControlsEnabled: false,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          trafficEnabled: true,
          compassEnabled: false,
          mapToolbarEnabled: false,
          polylines: _currentVideoId == null ? {} : {
            Polyline(
              polylineId: const PolylineId('emergency_route'),
              points: _routePoints,
              color: const Color(0xFF7B2FF7),
              width: 5,
            ),
          },
          markers: mapMarkers,
        ),
        // Layer 2: BackdropFilter blur — เฉพาะ Tab แจ้งเหตุ (tab 2)
        if (_selectedTab == 2)
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
            child: Container(
              color: Colors.black.withOpacity(0.15),
            ),
          ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Icon(Icons.arrow_back_ios_new, color: Colors.black87, size: 20),
            ),
          ),
          Text(
            'Emergency',
            style: TextStyle(
              fontFamily: 'SukhumvitSet',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.red[600],
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

  Widget _buildDriverAvatar() {
    final user = AuthService.instance.currentUser;
    final avatarUrl = user?.profileImageUrl ?? 'https://i.pravatar.cc/150';

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[300],
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        image: DecorationImage(
          image: NetworkImage(avatarUrl),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildDriverNameAndTitle() {
    final user = AuthService.instance.currentUser;
    final displayName = user?.fullName?.toUpperCase() ?? 'GUEST USER';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85), // Glassmorphism-style solid bg
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            displayName,
            style: TextStyle(
              fontFamily: 'SukhumvitSet',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF6A0D91), // Purple in draft
              letterSpacing: 1.2,
            ),
          ),
          Text(
            'START LIVE',
            style: TextStyle(
              fontFamily: 'SukhumvitSet',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFC084FC), // Lighter purple
              letterSpacing: 2.0,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _initializePlayer(String url) async {
    if (_videoPlayerController != null) return;

    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
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

  Widget _buildVideoPlayer() {
    if (_currentVideoId == null) {
      return Container(
        width: double.infinity,
        height: 220,
        margin: const EdgeInsets.only(left: 16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.dashboard_customize_rounded, color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              Text(
                'กรุณาเลือกเหตุการณ์จากแผงยอดนิยมด้านขวา\nเพื่อแสดงระบบศูนย์สั่งการและรับชมวิดีโอ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'SukhumvitSet',
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 220,
      margin: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _chewieController != null &&
               _chewieController!.videoPlayerController.value.isInitialized
            ? Chewie(controller: _chewieController!)
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.red),
                    const SizedBox(height: 12),
                    Text(
                      'กำลังเชื่อมต่อสัญญาณภาพ...',
                      style: TextStyle(
                        fontFamily: 'SukhumvitSet',
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStatusBar() {
    if (_currentVideoId == null) return const SizedBox.shrink();

    String statusText = 'รอหน่วยงานเข้าให้ความช่วยเหลือ';
    Color badgeColor = Colors.red;
    IconData statusIcon = Icons.warning_amber_rounded;

    if (_responders.isNotEmpty) {
      bool someArrived = _responders.any((r) => r['estimatedMinutes'] == 0);
      if (someArrived) {
        statusText = 'เจ้าหน้าที่ถึงที่เกิดเหตุแล้ว';
        badgeColor = Colors.green;
        statusIcon = Icons.check_circle_outline;
      } else {
        statusText = 'รถพยาบาล/กู้ภัย ${_responders.length} คัน กำลังเดินทาง';
        badgeColor = Colors.orange;
        statusIcon = Icons.airport_shuttle;
      }
    }

    return Container(
      margin: const EdgeInsets.only(left: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, color: badgeColor, size: 18),
          const SizedBox(width: 8),
          Text(
            'สถานะ:',
            style: TextStyle(
              fontFamily: 'SukhumvitSet',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                fontFamily: 'SukhumvitSet',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: badgeColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendingPanel() {
    return Container(
      width: 200,
      height: 380, // Tall vertical panel
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.6), width: 4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Text(
            'ยอดนิยม',
            style: TextStyle(
              fontFamily: 'SukhumvitSet',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '10 อันดับแรก',
              style: TextStyle(
                fontFamily: 'SukhumvitSet',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoadingTrending
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B35)))
                : _trendingVideos.isEmpty
                    ? const Center(
                        child: Text(
                          'ไม่มีข้อมูล',
                          style: TextStyle(fontFamily: 'SukhumvitSet', color: Colors.black54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _trendingVideos.length,
                        itemBuilder: (context, index) {
                          final video = _trendingVideos[index];
                          
                          // จัดรูปแบบเวลา วัน/เดือน/ปี เวลา
                          final timeFormat = DateFormat('dd/MM/yyyy HH:mm').format(video.createdAt);
                          
                          // สร้างชื่อวิดีโอ (ถ้ามี category ใน title ก็ใช้ ถ้าไม่มีก็เติม)
                          // รูปแบบ: ประเภทเหตุ - วันเวลา - (ตำแหน่งถ้ามี)
                          String displayTitle = video.title;
                          if (!displayTitle.contains(timeFormat)) {
                             displayTitle = '${video.description ?? 'เหตุฉุกเฉิน'} $timeFormat';
                          }

                          return GestureDetector(
                            onTap: () {
                              if (video.id != _currentVideoId) {
                                _switchVideo(video.id);
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              height: 100, // เพิ่มความสูงเพื่อใส่ชื่อ
                              decoration: BoxDecoration(
                                color: Colors.blueGrey[900],
                                borderRadius: BorderRadius.circular(12),
                                image: video.thumbnailUrl != null
                                    ? DecorationImage(
                                        image: NetworkImage(video.thumbnailUrl!),
                                        fit: BoxFit.cover,
                                        colorFilter: ColorFilter.mode(
                                            Colors.black.withOpacity(0.4), BlendMode.darken), // มืดลงหน่อยให้อ่านง่าย
                                      )
                                    : null,
                              ),
                              child: Stack(
                                children: [
                                  // Rank Badge
                                  Positioned(
                                    top: 4, left: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text('#${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    )
                                  ),
                                  // Title text at bottom
                                  Positioned(
                                    bottom: 6, left: 6, right: 6,
                                    child: Text(
                                      displayTitle,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'SukhumvitSet',
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildViewerCount() {
    return Padding(
      padding: const EdgeInsets.only(left: 30), // Offset to align with draft
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'กำลังรับชม',
            style: TextStyle(
              fontFamily: 'SukhumvitSet',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFFF6B35),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_formatCount(_viewerCount)} ราย',
              style: TextStyle(
                fontFamily: 'SukhumvitSet',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInteractionButtonRow(
            value: _formatCount(_likeCount),
            label: 'ส่งกำลังใจ',
            onTap: () async {
              final userId = ServiceLocator.instance.currentUser?.id ?? 'anonymous';
              if (_currentVideoId != null) {
                // อัปเดตผ่าน Realtime Stream เท่านั้นเพื่อกันนับเบิ้ล
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
          ),
          const SizedBox(height: 10),
          _buildInteractionButtonRow(
            value: '20%',
            label: 'ให้ทาง',
            onTap: () {},
          ),
          const SizedBox(height: 10),
          _buildInteractionButtonRow(
            value: '${_donationTotal.toStringAsFixed(0)}บ.',
            label: 'บริจาค',
            onTap: () => _showDonationSheet(),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionButtonRow({
    required String value,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Value Box (Grayish/Blured)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                width: 60,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Center(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontFamily: 'SukhumvitSet',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Label Box (Orange)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withOpacity(0.9),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B35).withOpacity(0.3),
                  blurRadius: 8,
                )
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'SukhumvitSet',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
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
              onTap: () {
                debugPrint("DEBUG: Switching to Live Tab (0)");
                setState(() => _selectedTab = 0);
              },
            ),
          ),
          const SizedBox(width: 8),
          // ความสัมพันธ์ Tab
          Expanded(
            child: GlassTabButton(
              label: 'ความสัมพันธ์',
              isActive: _selectedTab == 1,
              onTap: () {
                debugPrint("DEBUG: Switching to Relationship Tab (1)");
                setState(() => _selectedTab = 1);
              },
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
              onTap: () async {
                setState(() {
                  _selectedTab = 2;
                });
                
                // Fetch fresh settings and categories when tapping the report tab
                await _loadConfigFromDatabase();
                if (_emergencyCategories.isEmpty) {
                  _loadEmergencyCategories();
                }
                _initCamera(); // Keep camera init here
              },
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildOfflineIndicator() {
    return Container(
      width: double.infinity,
      color: Colors.red.withOpacity(0.8),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 14, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'การเชื่อมต่อขัดข้อง - กำลังพยายามเชื่อมต่อใหม่...',
              style: TextStyle(
                fontFamily: 'SukhumvitSet',
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
                        onTap: () async {
                          // Refinement 4: Real Donation Integration
                          final userId = ServiceLocator.instance.currentUser?.id;
                          if (_currentVideoId != null && userId != null) {
                            try {
                              WebSocketService().sendVideoInteraction(
                                _currentVideoId!,
                                userId,
                                'gift',
                                value: amount,
                              );
                              
                              // Save to DonationRepository to start payment flow process
                              await ServiceLocator.instance.donationRepository.addContribution({
                                'user_id': userId,
                                'amount': amount,
                                'status': 'pending', // Will be updated when payment completes
                                'payment_method': 'app_transfer',
                              });

                              // แจ้งเตือนความสำเร็จ
                              if (mounted) {
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
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('เกิดข้อผิดพลาดในการบริจาค')),
                                );
                              }
                            }
                          } else {
                            // Demo mode behavior
                            setState(() => _donationTotal += amount);
                            Navigator.pop(context);
                          }
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
