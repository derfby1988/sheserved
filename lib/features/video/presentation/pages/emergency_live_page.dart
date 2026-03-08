import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/glassmorphism_button.dart';
import '../../../../config/app_config.dart';
import '../../../../services/websocket_service.dart';
import '../../../../services/service_locator.dart';
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
  bool _isConnected = true;
  late AnimationController _liveBlinkController;
  late AnimationController _pulseController;
  GoogleMapController? _mapController;
  
  StreamSubscription? _connectionSub;
  StreamSubscription? _interactionSub;
  StreamSubscription? _progressSub;
  StreamSubscription? _rescueIncomingSub;
  
  // Emergency Recording
  CameraController? _cameraController;
  bool _isRecording = false;
  Timer? _gpsTimer;
  DateTime? _recordingStartTime;
  List<Map<String, dynamic>> _recordedGpsTracks = [];
  String? _selectedEmergencyCategoryId;
  
  // Video Recording Limits & Timers
  static const int _maxRecordingSeconds = 60;
  static const int _prepSeconds = 3;
  int _prepCountdown = 0;
  int _recordingTimeLeft = _maxRecordingSeconds;
  Timer? _countdownTimer;
  Timer? _durationTimer;
  
  // Emergency Photos
  bool _isPhotoMode = false;
  List<XFile> _capturedPhotos = [];
  
  // Mock GPS Route - Sukhumvit, Bangkok Area
  final List<LatLng> _routePoints = [
    LatLng(13.7300, 100.5600),
    LatLng(13.7315, 100.5615),
    LatLng(13.7330, 100.5630),
    LatLng(13.7345, 100.5645),
    LatLng(13.7360, 100.5660),
    LatLng(13.7375, 100.5675),
    LatLng(13.7390, 100.5690),
  ];

  @override
  void initState() {
    super.initState();
    _liveBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    _requestPermissions();
    _setupWebSocketStreams();
    _loadInitialData();
  }

  Future<void> _requestPermissions() async {
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

      // Auto-center camera on real location
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (!mounted) return;

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude), 15.0),
      );
    } catch (e) {
      debugPrint("Error getting current location: $e");
    }
  }

  void _loadInitialData() async {
    if (widget.videoId != null) {
      final summary = await ServiceLocator.instance.videoRepository
          .getInteractionSummary(widget.videoId!);
      setState(() {
        _likeCount = summary['likes'] ?? 0;
        _donationTotal = summary['donations']?.toDouble() ?? 0.0;
      });
    }
  }

  void _setupWebSocketStreams() {
    final ws = WebSocketService();
    
    // 1. Connection Status
    _connectionSub = ws.connectionStream.listen((connected) {
      setState(() => _isConnected = connected);
    });

    // 2. Video Interactions (Likes, Gifts)
    if (widget.videoId != null) {
      ws.joinVideoRoom(widget.videoId!);
      _interactionSub = ws.videoInteractionStream.listen((data) {
        if (data['videoId'] == widget.videoId) {
          setState(() {
            if (data['type'] == 'like') _likeCount++;
            if (data['type'] == 'gift') _donationTotal += (data['value'] ?? 0);
          });
        }
      });
    }

    // 3. Progress / GPS (Simulated move for demo, but wired to logic)
    _progressSub = ws.videoProgressStream.listen((data) {
      if (data['videoId'] == widget.videoId && data['location'] != null) {
        final loc = data['location'];
        final point = LatLng(loc['lat'], loc['lng']);
        setState(() {
          _routePoints.add(point);
        });
        // Refinement 1: Map Auto-Center
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(point),
        );
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
  }

  @override
  void dispose() {
    _liveBlinkController.dispose();
    _pulseController.dispose();
    _connectionSub?.cancel();
    _interactionSub?.cancel();
    _progressSub?.cancel();
    _rescueIncomingSub?.cancel();
    _countdownTimer?.cancel();
    _durationTimer?.cancel();
    if (widget.videoId != null) {
      WebSocketService().leaveVideoRoom(widget.videoId!);
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

  void _onLongPressDownVideo() async {
    if (_isRecording || _prepCountdown > 0) return;

    // 1. Fetch Emergency Categories
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

    // 2. Show Modal Bottom Sheet for Category Selection
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

    if (selectedCategory == null) {
      // User cancelled selection
      return;
    }

    _selectedEmergencyCategoryId = selectedCategory.id;

    // 3. Start Preparation Countdown
    setState(() {
      _prepCountdown = _prepSeconds;
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
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
      _recordingTimeLeft = _maxRecordingSeconds;
      
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
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black38, // Light gray in draft
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
              const SizedBox(height: 15),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 10),
          // Toggle Mode
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _isPhotoMode = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: !_isPhotoMode ? Colors.red : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Live Video', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _isPhotoMode = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isPhotoMode ? Colors.red : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Photos', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Camera Preview Box
          Container(
            height: 300,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _isRecording ? Colors.red : Colors.white24, width: 2),
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _cameraController != null && _cameraController!.value.isInitialized
                      ? SizedBox.expand(child: CameraPreview(_cameraController!))
                      : const Center(child: Icon(Icons.camera_alt, color: Colors.white54, size: 40)),
                ),
                if (_prepCountdown > 0)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: Text(
                        '$_prepCountdown',
                        style: const TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                if (_isRecording)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.red, width: 2),
                      ),
                      child: Text(
                        '00:${_recordingTimeLeft.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                           color: Colors.white, 
                           fontWeight: FontWeight.bold,
                           fontFamily: 'monospace',
                           fontSize: 16,
                        ),
                      ),
                    )
                  )
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          if (_isPhotoMode && _capturedPhotos.isNotEmpty) ...[
             SizedBox(
               height: 60,
               child: ListView.builder(
                 scrollDirection: Axis.horizontal,
                 itemCount: _capturedPhotos.length,
                 itemBuilder: (context, index) {
                   return Container(
                     margin: const EdgeInsets.only(right: 8),
                     width: 60,
                     decoration: BoxDecoration(
                       borderRadius: BorderRadius.circular(8),
                       image: DecorationImage(
                         image: FileImage(File(_capturedPhotos[index].path)),
                         fit: BoxFit.cover,
                       )
                     ),
                     child: Align(
                       alignment: Alignment.topRight,
                       child: GestureDetector(
                         onTap: () {
                           setState(() {
                             _capturedPhotos.removeAt(index);
                           });
                         },
                         child: const Icon(Icons.cancel, color: Colors.white, size: 20),
                       )
                     ),
                   );
                 }
               )
             ),
             const SizedBox(height: 10),
          ],

          Text(
            _isRecording ? 'กำลังบันทึกเหตุการณ์...' : 'คุณต้องการแจ้งเหตุฉุกเฉินใช่หรือไม่?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'SukhumvitSet',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _isRecording ? Colors.red[700] : Colors.red[900],
            ),
          ),
          if (_isRecording) ...[
            const SizedBox(height: 8),
            FadeTransition(
              opacity: _liveBlinkController,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(Icons.circle, color: Colors.red, size: 12),
                   SizedBox(width: 8),
                   Text('Recording...', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            _isPhotoMode 
             ? 'คุณสามารถเพิ่มหลักฐานภาพถ่ายสูงสุด ${VideoRepository.maxEmergencyPhotos} รูป\nระบบจะส่งพิกัด GPS ปัจจุบันพร้อมรูปไปให้เจ้าหน้าที่'
             : 'เมื่อเริ่มบันทึก ระบบจะเก็บไฟล์วิดีโอและพิกัด GPS\nเพื่อส่งไปยังศูนย์รับแจ้งเหตุทันทีเมื่อหยุดบันทึก',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'SukhumvitSet',
              fontSize: 14,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 20),
          
          // Action Buttons
          if (_isPhotoMode) ...[
             Row(
               children: [
                 Expanded(
                   flex: 1,
                   child: GestureDetector(
                     onTap: _takePhoto,
                     child: Container(
                       padding: const EdgeInsets.symmetric(vertical: 20),
                       decoration: BoxDecoration(
                         color: Colors.white,
                         borderRadius: BorderRadius.circular(16),
                         border: Border.all(color: Colors.red, width: 2),
                       ),
                       child: const Center(
                         child: Icon(Icons.camera, color: Colors.red, size: 30),
                       ),
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
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF3B30), Color(0xFFFF2D55)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10)),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              'ส่งรูปภาพ (Send)',
                              style: TextStyle(
                                fontFamily: 'SukhumvitSet',
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                 ]
               ]
             )
          ] else ...[
            GestureDetector(
              onLongPressDown: (_) => _onLongPressDownVideo(),
              onLongPressEnd: (_) => _onLongPressEndCancelVideo(),
              onLongPressCancel: () => _onLongPressEndCancelVideo(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isRecording 
                      ? [Colors.black87, Colors.black] 
                      : [const Color(0xFFFF3B30), const Color(0xFFFF2D55)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: (_isRecording ? Colors.black : Colors.red).withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isRecording ? Icons.stop_circle : Icons.videocam, 
                      color: Colors.white, 
                      size: 30
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isRecording 
                         ? 'ปล่อยเพื่อหยุดและส่ง (Release to Stop)' 
                         : 'กดค้างเพื่อเริ่มบันทึกเหตุ (Hold to Record)',
                      style: const TextStyle(
                        fontFamily: 'SukhumvitSet',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ]
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
    return GoogleMap(
      onMapCreated: (controller) {
        debugPrint("DEBUG: Google Map Created Successfully");
        _mapController = controller;
      },
      initialCameraPosition: CameraPosition(
        target: _routePoints.isNotEmpty
            ? _routePoints[_routePoints.length ~/ 2]
            : const LatLng(13.7367, 100.5604),
        zoom: 15.0,
      ),
      zoomControlsEnabled: false,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      trafficEnabled: true,
      compassEnabled: false,
      mapToolbarEnabled: false,
      polylines: {
        Polyline(
          polylineId: const PolylineId('emergency_route'),
          points: _routePoints,
          color: const Color(0xFF7B2FF7),
          width: 5,
        ),
      },
      markers: {
        if (_routePoints.isNotEmpty)
          Marker(
            markerId: const MarkerId('current_location'),
            position: _routePoints.last,
            // TODO: Use custom marker icon with pulse effect if possible, 
            // or stick to default marker for simplicity in Google Maps.
            // Google Maps doesn't support custom widget markers out-of-the-box like flutter_map.
            // We'll use the default marker for now, tinted purple.
            icon: BitmapDescriptor.defaultMarkerWithHue(270.0), // Purple hue
          ),
      },
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
        image: const DecorationImage(
          image: NetworkImage('https://i.pravatar.cc/150'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildDriverNameAndTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'MAHDIFAKHR',
          style: TextStyle(
            fontFamily: 'SukhumvitSet',
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF6A0D91), // Purple in draft
            letterSpacing: 1.2,
          ),
        ),
        Text(
          'DRIVER',
          style: TextStyle(
            fontFamily: 'SukhumvitSet',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFC084FC), // Lighter purple
            letterSpacing: 2.0,
          ),
        ),
      ],
    );
  }

  Widget _buildVideoPlayer() {
    return Container(
      width: double.infinity,
      height: 180,
      margin: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(4), // Slightly rounded but sharp in draft
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: Icon(Icons.play_arrow, color: Colors.white54, size: 50),
      ),
    );
  }

  Widget _buildTrendingPanel() {
    return Container(
      width: 140,
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
            onTap: () {
              final userId = ServiceLocator.instance.currentUser?.id;
              if (userId != null && widget.videoId != null) {
                WebSocketService().sendVideoInteraction(widget.videoId!, userId, 'like');
              } else {
                setState(() => _likeCount++);
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
              onTap: () {
                debugPrint("DEBUG: Switching to Report Incident Tab (2)");
                _initCamera();
                setState(() => _selectedTab = 2);
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
                          if (widget.videoId != null && userId != null) {
                            try {
                              WebSocketService().sendVideoInteraction(
                                widget.videoId!,
                                userId,
                                'gift',
                                value: amount,
                              );
                              
                              // แจ้งเตือนความสำเร็จ
                              if (mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'ส่งของขวัญ $amount บาท สำเร็จ! 🙏',
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
