part of '../emergency_live_page.dart';

extension EmergencyReportingLogic on _EmergencyLivePageState {
  Future<void> _initCamera() async {
    if (_cameraController != null) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      _cameraController = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: true);
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Error initializing camera: $e");
    }
  }

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

  void _onLongPressDownVideo() async {
    if (_isRecording || _prepCountdown > 0) return;
    if (_selectedEmergencyCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาเลือกประเภทเหตุฉุกเฉินก่อนเริ่มบันทึก'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _prepCountdown = 3);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        if (_prepCountdown > 1) _prepCountdown--;
        else { _prepCountdown = 0; timer.cancel(); _startEmergencyRecording(); }
      });
    });
  }

  void _onLongPressEndCancelVideo() {
    if (_prepCountdown > 0) { _countdownTimer?.cancel(); setState(() => _prepCountdown = 0); return; }
    if (_isRecording) _stopEmergencyRecording();
  }

  Future<void> _startEmergencyRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) await _initCamera();
    if (_cameraController == null || _isRecording) return;

    try {
      await _cameraController!.startVideoRecording();
      _recordingStartTime = DateTime.now();
      _recordedGpsTracks = [];
      _isRecording = true;
      _recordingTimeLeft = SyncConfig.maxEmergencyRecordingSeconds;
      
      try {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        _recordedGpsTracks.add({'latitude': pos.latitude, 'longitude': pos.longitude, 'timestampOffset': 0});
      } catch (_) {}
      
      _durationTimer?.cancel();
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
         if (!mounted) { timer.cancel(); return; }
         setState(() {
           if (_recordingTimeLeft > 0) _recordingTimeLeft--;
           else _stopEmergencyRecording();
         });
      });

      _gpsTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        try {
          Position pos = await Geolocator.getCurrentPosition();
          int offset = DateTime.now().difference(_recordingStartTime!).inSeconds;
          _recordedGpsTracks.add({'latitude': pos.latitude, 'longitude': pos.longitude, 'timestampOffset': offset});
        } catch (_) {}
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
      _uploadIncident(File(videoFile.path));
    } catch (e) {
      debugPrint("Error stopping recording: $e");
    }
  }

  Future<void> _takePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) await _initCamera();
    if (_cameraController == null) return;
    if (_capturedPhotos.length >= 3) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ถ่ายรูปได้สูงสุด 3 รูป'), backgroundColor: Colors.red));
      return;
    }
    try {
      XFile photo = await _cameraController!.takePicture();
      setState(() => _capturedPhotos.add(photo));
      if (_recordedGpsTracks.isEmpty) {
         try {
           Position pos = await Geolocator.getCurrentPosition();
           _recordedGpsTracks.add({'latitude': pos.latitude, 'longitude': pos.longitude, 'timestampOffset': 0});
         } catch (_) {}
      }
    } catch (e) {
      debugPrint("Error taking photo: $e");
    }
  }

  Future<void> _sendPhotos() async {
    if (_capturedPhotos.isEmpty) return;
    String? categoryId = _isThaiMhungReporting ? _currentVideo?.categoryId : _selectedEmergencyCategoryId;
    if (categoryId == null && !_isThaiMhungReporting) return;

    showDialog(context: context, barrierDismissible: false, builder: (context) => const AlertDialog(content: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('กำลังอัปโหลดรูปภาพเหตุฉุกเฉิน...')])));

    try {
      final userId = AuthService.instance.userId;
      if (userId == null) throw Exception("User not logged in");
      List<File> filesToUpload = _capturedPhotos.map((x) => File(x.path)).toList();
      final videoId = await ServiceLocator.instance.videoRepository.uploadEmergencyPhotos(
        userId: userId, 
        photoFiles: filesToUpload, 
        gpsTracks: _recordedGpsTracks, 
        categoryId: categoryId, 
        isThaiMhung: _isThaiMhungReporting,
        incidentId: _isThaiMhungReporting ? _currentVideoId : null,
      );
      final ws = WebSocketService();
      ws.sendEmergencyAlert(
        userId: userId, 
        categoryId: categoryId ?? 'thai_mhung', 
        videoId: videoId, 
        type: 'photo', 
        isThaiMhungEnabled: true,
        incidentId: _currentVideoId, // ✅ เชื่อมโยงกับเหตุการณ์หลัก
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('อัปโหลดรูปภาพฉุกเฉินสำเร็จ'), backgroundColor: Colors.green));
      setState(() { 
        _capturedPhotos.clear(); 
        _recordedGpsTracks.clear(); 
        _selectedTab = 0; 
        _isThaiMhungReporting = false; // กลับสู่หน้า Emergency หลัก
      });
      // ✅ โหลดข้อมูลภาพแกลลอรี่ใหม่ทันทีหลังอัปโหลด
      _loadGalleryPhotos();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _uploadIncident(File file) async {
    showDialog(context: context, barrierDismissible: false, builder: (context) => const AlertDialog(content: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('กำลังอัปโหลดข้อมูลเหตุฉุกเฉิน...')])));
    try {
      final userId = AuthService.instance.userId;
      if (userId == null) throw Exception("User not logged in");
      final videoId = await ServiceLocator.instance.videoRepository.uploadEmergencyVideo(userId: userId, videoFile: file, gpsTracks: _recordedGpsTracks, categoryId: _selectedEmergencyCategoryId);
      final ws = WebSocketService();
      if (videoId != null && mounted) {
        final newVideo = Video(id: videoId, userId: userId, title: 'Emergency Incident', type: VideoType.emergency, status: VideoStatus.processing, latitude: _recordedGpsTracks.isNotEmpty ? _recordedGpsTracks.last['latitude'] : 0.0, longitude: _recordedGpsTracks.isNotEmpty ? _recordedGpsTracks.last['longitude'] : 0.0, createdAt: AppConfig.currentUtc, localFilePath: file.path, categoryId: _selectedEmergencyCategoryId, categoryName: _selectedEmergencyCategory?.name ?? 'เหตุฉุกเฉิน');
        setState(() { _trendingVideos.insert(0, newVideo); _currentVideoId = videoId; _currentVideo = newVideo; });
        _initializePlayer(file.path, isLocal: true);
        _checkPrivacyPermissions();
        
        // OWNER MUST JOIN ROOM TO BE COUNTED AS VIEWER
        if (!ws.isConnected) { await ws.connect(userId: userId); }
        if (ws.isConnected) _subscribeToVideoEvents(videoId);
      }
      if (_selectedEmergencyCategoryId != null) {
        ws.sendEmergencyAlert(userId: userId, categoryId: _selectedEmergencyCategoryId ?? '', videoId: videoId, type: 'video', isThaiMhungEnabled: true);
      }

      if (videoId != null) {
        await _maybeStartEmergencyHealthReleaseSession(videoId: videoId);
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('อัปโหลดเหตุฉุกเฉินสำเร็จ ระบบกำลังประมวลผล'), backgroundColor: Colors.green));
      setState(() => _selectedTab = 0);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red));
    }
  }
}
