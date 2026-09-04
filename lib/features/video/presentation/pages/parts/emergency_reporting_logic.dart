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
    // ✅ Reporter Mission Lock: ห้ามแจ้งเหตุซ้อนหากยังมีเหตุการณ์ของตนเอง
    // ที่มีภารกิจยังไม่จบ — ต้องรอให้ภารกิจเดิมจบก่อน
    final userId = AuthService.instance.userId;
    if (userId != null) {
      try {
        final active = await ServiceLocator.instance.videoRepository
            .getReporterActiveIncidentVideoIds(userId);
        if (!mounted) return;
        if (active.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'คุณมีเหตุการณ์ที่ภารกิจยังไม่จบ — ต้องรอให้ภารกิจเดิมจบก่อนจึงจะแจ้งเหตุใหม่ได้',
                style: TextStyle(
                  fontFamily: 'SukhumvitSet',
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
          // เด้งไปเหตุการณ์ที่ภารกิจค้างล่าสุด + สลับกลับหน้า Live
          final firstActive = active.first;
          if (firstActive.isNotEmpty) {
            _switchVideo(firstActive);
            setState(() => _selectedTab = 0);
          }
          return;
        }
      } catch (e) {
        debugPrint('[ReporterLock] active mission check failed: $e');
      }
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
    if (_isSendingThaiMhungPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ภาพกำลังถูกปกป้องสิทธิ์ส่วนบุคคล กรุณารอสักครู่'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    // ✅ Reporter Mission Lock: ห้ามแจ้งเหตุซ้อน (โหมดภาพถ่าย)
    // ยกเว้น: โหมดไทยมุงที่แนบภาพเข้าเหตุการณ์เดิม (_isThaiMhungReporting)
    if (!_isThaiMhungReporting) {
      final userId = AuthService.instance.userId;
      if (userId != null) {
        try {
          final active = await ServiceLocator.instance.videoRepository
              .getReporterActiveIncidentVideoIds(userId);
          if (!mounted) return;
          if (active.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'คุณมีเหตุการณ์ที่ภารกิจยังไม่จบ — ต้องรอให้ภารกิจเดิมจบก่อนจึงจะแจ้งเหตุใหม่ได้',
                  style: TextStyle(
                    fontFamily: 'SukhumvitSet',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
              ),
            );
            final firstActive = active.first;
            if (firstActive.isNotEmpty) {
              _switchVideo(firstActive);
              setState(() => _selectedTab = 0);
            }
            return;
          }
        } catch (e) {
          debugPrint('[ReporterLock] active mission check failed: $e');
        }
      }
    }
    String? categoryId = _isThaiMhungReporting ? _currentVideo?.categoryId : _selectedEmergencyCategoryId;
    if (categoryId == null && !_isThaiMhungReporting) return;

    setState(() => _isSendingThaiMhungPhotos = true);

    final loadingText = _isThaiMhungReporting
        ? 'กำลังอัปโหลด...'
        : 'กำลังอัปโหลดรูปภาพเหตุฉุกเฉิน...';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(loadingText, textAlign: TextAlign.center),
          ],
        ),
      ),
    );

    try {
      final userId = AuthService.instance.userId;
      if (userId == null) throw Exception("User not logged in");
      List<File> filesToUpload = _capturedPhotos.map((x) => File(x.path)).toList();
      final uploadResult = await ServiceLocator.instance.videoRepository.uploadEmergencyPhotos(
        userId: userId,
        photoFiles: filesToUpload,
        gpsTracks: _recordedGpsTracks,
        categoryId: categoryId,
        isThaiMhung: _isThaiMhungReporting,
        incidentId: _isThaiMhungReporting ? _currentVideoId : null,
      );
      final videoId = uploadResult?['videoId']?.toString();
      final ws = WebSocketService();
      ws.sendEmergencyAlert(
        userId: userId,
        categoryId: categoryId ?? 'thai_mhung',
        videoId: videoId,
        type: 'photo',
        isThaiMhungEnabled: true,
        incidentId: _currentVideoId,
      );
      if (!mounted) return;
      Navigator.pop(context);
      final successText = _isThaiMhungReporting
          ? 'ส่งภาพไทยมุงสำเร็จ กำลังปกป้องสิทธิ์ส่วนบุคคล...'
          : 'อัปโหลดรูปภาพฉุกเฉินสำเร็จ';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successText), backgroundColor: Colors.green));
      setState(() {
        _capturedPhotos.clear();
        _recordedGpsTracks.clear();
        _selectedTab = 0;
        _isThaiMhungReporting = false;
        _isSendingThaiMhungPhotos = false;
      });
      // Phase 6.12: Immediately add placeholder photos with blurStatus='blurring'
      final photoIds = uploadResult?['photoIds'] as List<dynamic>?;
      final photoUrls = uploadResult?['photo_urls'] as List<dynamic>?;
      debugPrint('[ThaiMhung Upload] photoIds: $photoIds');
      debugPrint('[ThaiMhung Upload] photoUrls: $photoUrls');
      if (photoIds != null && photoUrls != null && photoIds.length == photoUrls.length) {
        setState(() {
          for (int i = 0; i < photoIds.length; i++) {
            final photoId = photoIds[i].toString();
            final photoUrl = photoUrls[i].toString();
            if (photoId.isNotEmpty && photoUrl.isNotEmpty) {
              final normalizedUrl = ServiceLocator.instance.videoRepository.ensureFullUrl(photoUrl);
              debugPrint('[ThaiMhung Upload] Adding placeholder: id=$photoId, url=$normalizedUrl, blurStatus=blurring');
              _thaiMhungPhotos.insert(0, ThaiMhungPhoto(
                id: photoId,
                url: normalizedUrl,
                userName: userId,
                blurStatus: 'blurring',
              ));
            }
          }
          debugPrint('[ThaiMhung Upload] Total photos in gallery after insertion: ${_thaiMhungPhotos.length}');
        });
      } else {
        debugPrint('[ThaiMhung Upload] photoIds or photoUrls is null or length mismatch');
      }
      _loadGalleryPhotos();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red));
      setState(() => _isSendingThaiMhungPhotos = false);
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
