part of '../emergency_live_page.dart';

extension EmergencyNavigationLogic on _EmergencyLivePageState {
  void _initCompass() {
    _compassSub?.cancel();
    _compassSub = null;
    if (_currentResponseId == null) return;
    _compassSub = FlutterCompass.events?.listen((event) {
      if (mounted && event.heading != null) {
        if (_deviceHeading == null || (event.heading! - _deviceHeading!).abs() > 1.0) { setState(() => _deviceHeading = event.heading); }
      }
    });
  }

  Future<void> _startResponderTracking() async {
    if (_currentResponseId == null) return;
    final locService = LocationTrackingService();
    final isAlwaysGranted = await locService.isBackgroundPermissionGranted();
    if (!isAlwaysGranted) { if (mounted) { final shouldGoToSettings = await BackgroundPermissionDialog.show(context); if (shouldGoToSettings) { await openAppSettings(); return; } } }
    
    _myLocationStreamSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)).listen((Position position) {
      if (!mounted) return;
      setState(() { _userLocation = LatLng(position.latitude, position.longitude); });
      final userId = AuthService.instance.userId;
      if (userId != null && _isConnected) {
        final socket = WebSocketService().socket;
        if (socket != null && socket.connected) {
          socket.emit('location-update', { 'userId': userId, 'latitude': position.latitude, 'longitude': position.longitude, 'timestamp': AppConfig.currentUtc.toIso8601String(), 'accuracy': position.accuracy, 'speed': position.speed, 'heading': position.heading });
        }
      }
    });
  }

  void _toggleUiVisibility() {
    setState(() => _isUiVisible = !_isUiVisible);
    Future.delayed(const Duration(milliseconds: 300), () => _adjustMapBounds());
  }

  double _calculateMapTopPadding() {
    if (!_isUiVisible) return 40.0;
    if (_selectedTab != 0 || _currentVideoId == null) return MediaQuery.of(context).size.height * 0.2;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double videoWidth = (screenWidth - 32) * 0.45;
    double ar = 16 / 9;
    if (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized) {
      ar = _chewieController!.videoPlayerController.value.aspectRatio;
    }
    final double videoHeight = videoWidth / ar;
    final double totalUiHeight = videoHeight + 120;
    return totalUiHeight.clamp(MediaQuery.of(context).size.height * 0.2, MediaQuery.of(context).size.height * 0.5);
  }

  Future<void> _checkPermissions() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (mounted) {
        setState(() { _userLocation = LatLng(position.latitude, position.longitude); });
        if (_currentVideoId == null) _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_userLocation!, 15.0));
      }
    } catch (_) {}
  }

  void _loadInitialData() async {
    await _loadEmergencyCategories();
    if (_currentVideoId != null) {
      // หมายเหตุ: ไม่เรียก _recordView() แล้ว เพราะ WebSocket Server นับ unique viewers ผ่าน room membership
      final summary = await ServiceLocator.instance.videoRepository.getInteractionSummary(_currentVideoId!);
      // หมายเหตุ: ไม่ตั้ง _viewerCount จาก summary เพราะ summary['views'] คือยอดสะสม (ทั้งหมดที่เคยดู)
      // ค่า _viewerCount ที่ถูกต้องจะมาจาก WebSocket viewer-count event (real-time unique viewers)
      setState(() { _likeCount = summary['likes'] ?? 0; _donationTotal = summary['donations']?.toDouble() ?? 0.0; });
      _checkPrivacyPermissions();
      final video = await ServiceLocator.instance.videoRepository.getVideoById(_currentVideoId!);
      if (mounted) {
        setState(() {
          _currentVideo = video;
          if (video?.categoryId != null) {
            _selectedEmergencyCategoryId = video!.categoryId;
            if (_emergencyCategories.isNotEmpty) _selectedEmergencyCategory = _emergencyCategories.firstWhere((c) => c.id == video.categoryId, orElse: () => DonationCategory(id: video.categoryId!, name: 'เหตุฉุกเฉิน'));
          }
        });
        _checkPrivacyPermissions();
      }
      if (video != null) {
        if (video.localFilePath != null && File(video.localFilePath!).existsSync()) {
          _initializePlayer(video.localFilePath!, isLocal: true);
        } else if (video.bunnyUrl != null && video.bunnyUrl!.isNotEmpty) {
          _initializePlayer(video.bunnyUrl!, isLocal: false);
        }
      }
      _loadThaiMhungPhotos();
      final tracks = await ServiceLocator.instance.videoRepository.getGpsTracks(_currentVideoId!);
      if (tracks.isNotEmpty) {
          _dbGpsTracks = tracks;
          if (mounted) { setState(() { _routePoints.clear(); _routePoints.addAll(tracks.map((t) => LatLng(t.latitude, t.longitude))); }); _adjustMapBounds(); }
      } else if (video != null && video.latitude != 0) {
          if (mounted) { setState(() { _routePoints.clear(); _routePoints.add(LatLng(video.latitude, video.longitude)); }); _adjustMapBounds(); }
      }
    }
    await _loadTrendingVideos();
    if (_currentVideoId != null) _loadResponders();
  }

  Future<void> _loadResponders() async {
    try {
      final responders = await ServiceLocator.instance.videoRepository.getIncidentResponders(_currentVideoId!);
      if (mounted) {
        setState(() {
          double parseDouble(dynamic value) { if (value == null) return 0.0; if (value is num) return value.toDouble(); if (value is String) return double.tryParse(value) ?? 0.0; return 0.0; }
          final String? myUserId = AuthService.instance.userId;
          
          for (int i = 0; i < responders.length; i++) {
            var r = responders[i]; 
            r['currentLat'] = r['startLat']; 
            r['currentLng'] = r['startLng'];
            
            // Check if user is already a responder
            if (myUserId != null && r['volunteerId'] == myUserId) {
              _currentResponseId = r['id']?.toString();
            }
            
            if (r['startLat'] != null && r['startLng'] != null && _currentVideo != null) {
              final double distanceMeters = Geolocator.distanceBetween(parseDouble(r['startLat']), parseDouble(r['startLng']), _currentVideo!.latitude, _currentVideo!.longitude);
              final double distanceKm = distanceMeters / 1000; r['distanceKm'] = distanceKm;
              final int mins = (distanceKm / 40 * 60).round().clamp(1, 120); r['estimatedMinutes'] = mins;
            } else { 
              r['estimatedMinutes'] = 0; 
              r['distanceKm'] = 0.0; 
            }
            r['currentSpeed'] = 15.0; 
          }
          _responders = responders;
        });
        _adjustMapBounds();
      }
    } catch (_) {}
  }

  void _adjustMapBounds() {
    if (_mapController == null || !mounted) return;
    if (_routePoints.isEmpty) { if (_currentVideoId == null && _userLocation != null) _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_userLocation!, 15.0)); return; }
    if (_responders.isEmpty) { _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_routePoints.last, 17.0)); return; }
    double minLat = _routePoints.last.latitude; double maxLat = _routePoints.last.latitude; double minLng = _routePoints.last.longitude; double maxLng = _routePoints.last.longitude;
    for (var r in _responders) { if (r['currentLat'] != null && r['currentLng'] != null) { if (r['currentLat'] < minLat) minLat = r['currentLat']; if (r['currentLat'] > maxLat) maxLat = r['currentLat']; if (r['currentLng'] < minLng) minLng = r['currentLng']; if (r['currentLng'] > maxLng) maxLng = r['currentLng']; } }
    LatLngBounds bounds = LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
    try { _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60.0)); } catch (_) {}
  }

  // _recordView ถูกปิดการใช้งานแล้ว — WebSocket Server นับ unique viewers ผ่าน room จัดการที่ Server โดยตรง
  // หากต้องการเก็บสถิติ historical views ให้แยกระบบนับสถิติ (analytics) ออกจาก "กำลังรับชม" (real-time viewers)
  // Future<void> _recordView() async {
  //   if (_currentVideoId == null) return;
  //   final userId = ServiceLocator.instance.currentUser?.id ?? 'anonymous';
  //   try { final interaction = VideoInteraction(id: '', videoId: _currentVideoId!, userId: userId, type: 'view', createdAt: AppConfig.currentUtc); await ServiceLocator.instance.videoRepository.addInteraction(interaction); } catch (_) {}
  // }

  Future<void> _loadTrendingVideos() async {
    try {
      final videos = await ServiceLocator.instance.videoRepository.getEmergencyVideos();
      if (mounted) { setState(() { _trendingVideos = videos; _isLoadingTrending = false; }); }
    } catch (_) { if (mounted) setState(() => _isLoadingTrending = false); }
  }

  Future<void> _checkPrivacyPermissions() async {
    if (_currentVideo == null) return;
    final currentUserId = AuthService.instance.userId;
    if (currentUserId == null) return;
    final isOwner = _currentVideo!.userId == currentUserId;
    if (mounted) {
      setState(() {
        _canViewUnblurred = false;
        if (isOwner) _canViewUnblurred = true;
        final user = AuthService.instance.currentUser;
        if (user != null && _currentVideo != null) {
          final catId = _currentVideo!.categoryId;
          final category = _emergencyCategories.where((c) => c.id == catId).firstOrNull;
          if (category != null && category.volunteerProfessionIds.contains(user.professionId)) _canViewUnblurred = true;
        }
        if (_currentResponseId != null) _canViewUnblurred = true;
      });
    }
    if (isOwner) return;
    try {
      final victimProfile = await Supabase.instance.client.from('consumer_profiles').select('unblurred_profession_ids').eq('user_id', _currentVideo!.userId).maybeSingle();
      if (victimProfile != null) {
        final List<dynamic> allowedIds = victimProfile['unblurred_profession_ids'] ?? [];
        final currentUser = AuthService.instance.currentUser;
        if (currentUser != null && currentUser.professionId != null) { if (allowedIds.map((id) => id.toString()).contains(currentUser.professionId)) { if (mounted) setState(() => _canViewUnblurred = true); } }
      }
    } catch (_) {}
  }

  Future<void> _openInGoogleMaps() async {
    if (_currentVideo == null) return;
    final lat = _currentVideo!.latitude;
    final lng = _currentVideo!.longitude;
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _updateRescueStatus(String status) async {
    if (_currentResponseId == null || _currentVideoId == null) return;
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;
    final socket = WebSocketService().socket;
    if (socket != null && socket.connected) {
      socket.emit('rescue-status-update', { 'videoId': _currentVideoId, 'volunteerId': userId, 'victimId': _currentVideo?.userId, 'status': status, 'responseId': _currentResponseId });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('อัปเดตสถานะเป็น: ${status == 'arrived' ? 'มาถึงแล้ว' : 'เสร็จสิ้น'}')));
      if (status == 'resolved') Future.delayed(const Duration(seconds: 2), () { if (mounted) Navigator.of(context).pop(); });
    }
  }

  bool _isEligibleResponder() {
    final user = AuthService.instance.currentUser;
    if (user == null || _currentVideo == null) return false;
    if (_currentResponseId != null) return false;
    final currentUserId = AuthService.instance.userId?.toString();
    final ownerId = _currentVideo?.userId?.toString();
    final authedUserId = user.id.toString();
    final isOwner = (ownerId != null) && (ownerId.trim() == authedUserId.trim() || (currentUserId != null && ownerId.trim() == currentUserId.trim()));
    if (isOwner) return false;
    final catId = _currentVideo?.categoryId;
    final category = _emergencyCategories.where((c) => c.id == catId).firstOrNull;
    if (category != null && category.volunteerProfessionIds.isNotEmpty) return category.volunteerProfessionIds.contains(user.professionId);
    return false;
  }

  Future<void> _acceptRescue() async {
    if (_currentVideoId == null || !mounted) return;
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;
    try {
      final responseId = await ServiceLocator.instance.videoRepository.acceptIncident(
        videoId: _currentVideoId!, 
        responderId: userId, 
        latitude: _userLocation?.latitude, 
        longitude: _userLocation?.longitude
      );
      if (responseId == null) throw Exception('ไม่สามารถบันทึกการเข้ารับงานได้');
      
      if (mounted) {
        setState(() { 
          _currentResponseId = responseId; 
          _checkPrivacyPermissions(); 
          _initCompass(); 
        });
      }
      
      final user = AuthService.instance.currentUser;
      if (user != null && _userLocation != null) {
        _responders.add({ 
          'id': responseId, 
          'volunteerId': userId, 
          'status': 'accepted', 
          'volunteerName': user.fullName, 
          'professionName': 'อาสาสมัคร', 
          'professionColor': '#FF3B30', 
          'currentLat': _userLocation!.latitude, 
          'currentLng': _userLocation!.longitude, 
          'distanceKm': 0.0, 
          'estimatedMinutes': 0 
        });
      }
      
      final socket = WebSocketService().socket;
      if (socket != null && socket.connected) {
        socket.emit('rescue-status-update', { 
          'videoId': _currentVideoId, 
          'volunteerId': userId, 
          'victimId': _currentVideo?.userId, 
          'status': 'accepted', 
          'responseId': _currentResponseId 
        });
      }
      
      _startResponderTracking(); 
      _adjustMapBounds();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คุณได้รับภารกิจช่วยเหลือแล้ว! กำลังนำทาง...'), backgroundColor: Colors.blue, behavior: SnackBarBehavior.floating));
      
      // Auto-dismiss alert card on Home Page after accept
      try {
        final repo = ServiceLocator.instance.userRepository;
        final saved = await repo.getUiPreference(userId, 'dismissed_emergency_alert_ids');
        final list = saved != null && saved.isNotEmpty ? saved.split(',').toList() : <String>[];
        if (!list.contains(_currentVideoId!)) {
          list.add(_currentVideoId!);
          await repo.saveUiPreference(userId, 'dismissed_emergency_alert_ids', list.join(','));
        }
      } catch (e) {
        debugPrint('Error auto-dismissing alert on accept: $e');
      }
    } catch (_) { 
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ไม่สามารถตอบรับความช่วยเหลือได้ในขณะนี้'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating)); 
    }
  }

  void _switchVideo(String newVideoId) {
    if (_currentVideoId != null) WebSocketService().leaveVideoRoom(_currentVideoId!);
    _interactionSub?.cancel(); _supabaseInteractionSub?.unsubscribe(); _progressSub?.cancel(); _rescueIncomingSub?.cancel(); _videoStatusSub?.cancel(); _emergencySub?.cancel();
    _videoPlayerController?.removeListener(_syncGpsWithVideo); _videoPlayerController?.dispose(); _videoPlayerController = null;
    _chewieController?.dispose(); _chewieController = null;
    setState(() { _currentVideoId = newVideoId; _highlightVideoId = null; _currentVideo = null; _dbGpsTracks.clear(); _routePoints.clear(); _responders.clear(); _lastSyncedVideoTrack = null; _likeCount = 0; _donationTotal = 0.0; _viewerCount = 0; });
    _setupWebSocketStreams(); _loadInitialData();
  }

  void _onThaiMhungTabSelected() async {
    if (_currentVideo == null) { setState(() => _selectedTab = 0); return; }
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาเปิดระบบระบุตำแหน่ง (GPS) เพื่อทำหน้าที่ไทยมุง'))); return; }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GPS ถูกปฏิเสธถาวร กรุณาเปิดในตั้งค่า'))); return; }
    setState(() { _selectedTab = 0; _isThaiMhungReporting = true; _loadInitialData(); });
    _initCamera();
  }

  void _initializePlayer(String url, {bool isLocal = false}) {
    if (_videoPlayerController != null) { _videoPlayerController!.removeListener(_syncGpsWithVideo); _videoPlayerController!.dispose(); }
    
    // Auto-correct local IP changes in URLs from database
    if (!isLocal && url.contains(':3000') && !url.startsWith(AppConfig.localApiUrl)) {
      url = url.replaceAll(RegExp(r'http://[0-9\.]+:\d+'), AppConfig.localApiUrl);
    }
    
    _videoPlayerController = isLocal ? VideoPlayerController.file(File(url)) : VideoPlayerController.networkUrl(Uri.parse(url));
    _videoPlayerController!.initialize().then((_) {
      if (mounted) {
        setState(() { 
          _chewieController = ChewieController(
            videoPlayerController: _videoPlayerController!, 
            aspectRatio: _videoPlayerController!.value.aspectRatio, 
            autoPlay: true, 
            looping: false, 
            showControls: true, 
            placeholder: Container(color: Colors.black), 
            errorBuilder: (context, errorMessage) => Center(child: Text(errorMessage, style: const TextStyle(color: Colors.white)) ),
          ); 
        });
        
        // EXPLICIT PLAY FOR IOS AUTO-PALY IMPROVEMENT
        _videoPlayerController!.setVolume(1.0);
        _videoPlayerController!.play();
        
        _videoPlayerController!.addListener(_syncGpsWithVideo);
        _adjustMapBounds();
      }
    });
  }

  void _syncGpsWithVideo() {
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized || _dbGpsTracks.isEmpty) return;
    final int currentOffset = _videoPlayerController!.value.position.inSeconds;
    final track = _dbGpsTracks.firstWhere((t) => t.timestampOffset >= currentOffset, orElse: () => _dbGpsTracks.last);
    if (track != _lastSyncedVideoTrack) {
       _lastSyncedVideoTrack = track;
       if (mounted) setState(() { _routePoints.add(LatLng(track.latitude, track.longitude)); });
    }
  }

  void _showDonationSheet() {
    if (_currentVideoId == null) return;
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => DonationSheetWidget(videoId: _currentVideoId!, onDonate: (amount) => setState(() => _donationTotal += amount) ));
  }

  Future<void> _reportThaiMhungEmergency(String description) async {
    final userId = AuthService.instance.userId;
    if (userId == null || _capturedPhotos.isEmpty) return;
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
    try {
      List<File> files = _capturedPhotos.map((x) => File(x.path)).toList();
      final videoId = await ServiceLocator.instance.videoRepository.uploadEmergencyPhotos(userId: userId, photoFiles: files, gpsTracks: _recordedGpsTracks, categoryId: _selectedEmergencyCategoryId);
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ส่งข้อมูลไทยมุงสำเร็จ ขอบคุณที่ร่วมช่วยสังคม!'), backgroundColor: Colors.green)); setState(() { _capturedPhotos.clear(); _selectedTab = 0; _isThaiMhungReporting = false; }); }
    } catch (_) { if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เกิดข้อผิดพลาดในการส่งข้อมูล'))); } }
  }

  String _formatCount(int count) {
    if (count >= 1000) { final k = count / 1000; return k == k.roundToDouble() ? '${k.round()}K' : '${k.toStringAsFixed(1)}K'; }
    return count.toString();
  }

  Future<void> _onLike() async {
    final userId = AuthService.instance.currentUser?.id ?? 'anonymous';
    if (_currentVideoId != null) {
      try {
        final interaction = VideoInteraction(id: '', videoId: _currentVideoId!, userId: userId, type: 'like', createdAt: AppConfig.currentUtc);
        await ServiceLocator.instance.videoRepository.addInteraction(interaction);
      } catch (_) {}
    }
  }

  Future<void> _loadThaiMhungPhotos() async {
    if (_currentVideo?.categoryId == null) return;
    try {
      final photos = await ServiceLocator.instance.videoRepository.getThaiMhungPhotos(_currentVideo!.categoryId!);
      setState(() { _thaiMhungPhotos = photos.map((v) => ThaiMhungPhoto(id: v.id, url: v.bunnyUrl ?? '', userName: v.userName)).where((p) => p.url.isNotEmpty).toList(); });
    } catch (_) {}
  }

  Future<void> _yieldWay() async {
    if (_currentVideoId == null) return;
    final userId = AuthService.instance.currentUser?.id ?? 'anonymous';
    try {
      final interaction = VideoInteraction(id: '', videoId: _currentVideoId!, userId: userId, type: 'yield_way', createdAt: AppConfig.currentUtc);
      await ServiceLocator.instance.videoRepository.addInteraction(interaction);
      final socket = WebSocketService().socket;
      if (socket != null && socket.connected) socket.emit('yield-way-click', { 'videoId': _currentVideoId, 'userId': userId });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ขอบคุณที่ช่วยเปิดทางให้รถฉุกเฉิน! 🚑💙'), backgroundColor: Colors.blue, behavior: SnackBarBehavior.floating));
    } catch (_) {}
  }

  void _showPhotoDetail(ThaiMhungPhoto photo) {
    showDialog(context: context, builder: (context) => Dialog(backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.all(10), child: Column(mainAxisSize: MainAxisSize.min, children: [Align(alignment: Alignment.topRight, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context))), ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.network(photo.url, fit: BoxFit.contain)), if (photo.userName != null) Padding(padding: const EdgeInsets.all(8.0), child: Text('โดย: ${photo.userName}', style: const TextStyle(color: Colors.white70, fontSize: 14))) ])));
  }

  Future<void> _loadConfigFromDatabase() async {
    try {
      final config = await Supabase.instance.client.from('app_config').select().maybeSingle();
      if (config != null) {
        // อัปเดต AppConfig โค้ดกลาง
      }
    } catch (_) {}
  }
}
