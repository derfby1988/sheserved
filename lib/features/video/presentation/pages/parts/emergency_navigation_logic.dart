part of '../emergency_live_page.dart';

extension EmergencyNavigationLogic on _EmergencyLivePageState {
  void _initCompass() {
    _compassSub?.cancel();
    _compassSub = null;
    if (_currentResponseId == null) return;
    _compassSub = FlutterCompass.events?.listen((event) {
      if (mounted && event.heading != null) {
        if (_deviceHeading == null ||
            (event.heading! - _deviceHeading!).abs() > 1.0) {
          setState(() => _deviceHeading = event.heading);
        }
      }
    });
  }

  Future<void> _startResponderTracking() async {
    if (_currentResponseId == null) return;
    final locService = LocationTrackingService();
    final isAlwaysGranted = await locService.isBackgroundPermissionGranted();
    if (!isAlwaysGranted) {
      if (mounted) {
        final shouldGoToSettings = await BackgroundPermissionDialog.show(
          context,
        );
        if (shouldGoToSettings) {
          await openAppSettings();
          return;
        }
      }
    }

    _myLocationStreamSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((Position position) {
          if (!mounted) return;
          setState(() {
            _userLocation = LatLng(position.latitude, position.longitude);
          });
          final userId = AuthService.instance.userId;
          if (userId != null && _isConnected) {
            final socket = WebSocketService().socket;
            if (socket != null && socket.connected) {
              socket.emit('location-update', {
                'userId': userId,
                'latitude': position.latitude,
                'longitude': position.longitude,
                'timestamp': AppConfig.currentUtc.toIso8601String(),
                'accuracy': position.accuracy,
                'speed': position.speed,
                'heading': position.heading,
              });
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
    if (_selectedTab != 0 || _currentVideoId == null)
      return MediaQuery.of(context).size.height * 0.2;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double videoWidth = (screenWidth - 32) * 0.45;
    double ar = 16 / 9;
    try {
      final controller = _chewieController;
      if (controller != null &&
          controller.videoPlayerController.value.isInitialized) {
        ar = controller.videoPlayerController.value.aspectRatio;
      }
    } catch (_) {
      ar = 16 / 9;
    }
    final double videoHeight = videoWidth / ar;
    final double totalUiHeight = videoHeight + 120;
    return totalUiHeight.clamp(
      MediaQuery.of(context).size.height * 0.2,
      MediaQuery.of(context).size.height * 0.5,
    );
  }

  Future<void> _checkPermissions() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever)
        return;
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (mounted) {
        setState(() {
          _userLocation = LatLng(position.latitude, position.longitude);
        });
        if (_currentVideoId == null)
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(_userLocation!, 15.0),
          );
      }
    } catch (_) {}
  }

  void _loadInitialData() async {
    _fetchProfessionName();
    await _loadEmergencyCategories();
    if (_currentVideoId != null) {
      // หมายเหตุ: ไม่เรียก _recordView() แล้ว เพราะ WebSocket Server นับ unique viewers ผ่าน room membership
      final summary = await ServiceLocator.instance.videoRepository
          .getInteractionSummary(_currentVideoId!);
      // หมายเหตุ: ไม่ตั้ง _viewerCount จาก summary เพราะ summary['views'] คือยอดสะสม (ทั้งหมดที่เคยดู)
      // ค่า _viewerCount ที่ถูกต้องจะมาจาก WebSocket viewer-count event (real-time unique viewers)
      setState(() {
        _likeCount = summary['likes'] ?? 0;
      });

      // ✅ [Support Analytics] Load like status for current user
      _loadLikeStatus();

      _checkPrivacyPermissions();
      final video = await ServiceLocator.instance.videoRepository.getVideoById(
        _currentVideoId!,
      );
      if (mounted) {
        setState(() {
          _currentVideo = video;
          if (video?.categoryId != null) {
            _selectedEmergencyCategoryId = video!.categoryId;
            if (_emergencyCategories.isNotEmpty)
              _selectedEmergencyCategory = _emergencyCategories.firstWhere(
                (c) => c.id == video.categoryId,
                orElse: () => DonationCategory(
                  id: video.categoryId!,
                  name: 'เหตุฉุกเฉิน',
                ),
              );
          }
        });
        _checkPrivacyPermissions();
      }
      if (video != null) {
        if (video.localFilePath != null &&
            File(video.localFilePath!).existsSync()) {
          _initializePlayer(video.localFilePath!, isLocal: true);
        } else if (video.bunnyUrl != null && video.bunnyUrl!.isNotEmpty) {
          _initializePlayer(
            ServiceLocator.instance.videoRepository.ensureFullUrl(
              video.bunnyUrl!,
            ),
            isLocal: false,
          );
        }
      }
      // หมายเหตุ: _loadGalleryPhotos() ทำหน้าที่ดึงภาพไทยมุงที่ด้านล่างแล้ว (line 109)
      // ไม่เรียก _loadThaiMhungPhotos() ซ้ำ เพื่อป้องกัน race condition (setState เขียนทับกัน)
      final tracks = await ServiceLocator.instance.videoRepository.getGpsTracks(
        _currentVideoId!,
      );
      if (tracks.isNotEmpty) {
        _dbGpsTracks = tracks;
        if (mounted) {
          setState(() {
            _routePoints.clear();
            _routePoints.addAll(
              tracks.map((t) => LatLng(t.latitude, t.longitude)),
            );
          });
          _adjustMapBounds();
        }
      } else if (video != null && video.latitude != 0) {
        if (mounted) {
          setState(() {
            _routePoints.clear();
            _routePoints.add(LatLng(video.latitude, video.longitude));
          });
          _adjustMapBounds();
        }
      }
    }
    await _loadTrendingVideos();
    if (_currentVideoId != null) {
      _loadResponders();
      _loadGalleryPhotos();
      _subscribeToPhotoBlurComplete();
      _subscribeToNewThaiMhungPhotos();
    }
  }

  /// Phase 6.12: รับ event เมื่อ background face blur เสร็จ → รีเฟรช gallery
  void _subscribeToPhotoBlurComplete() {
    _photoBlurSub?.cancel();
    _photoBlurSub = WebSocketService().photoBlurCompleteStream.listen((data) {
      final incidentId =
          data['incidentId']?.toString() ??
          data['incident_id']?.toString() ??
          '';
      if (incidentId != _currentVideoId) return;
      final photoId =
          data['photoId']?.toString() ?? data['photo_id']?.toString() ?? '';
      final url = data['url']?.toString() ?? '';
      if (photoId.isEmpty || url.isEmpty) return;
      if (mounted) {
        setState(() {
          final idx = _thaiMhungPhotos.indexWhere((p) => p.id == photoId);
          if (idx >= 0) {
            _thaiMhungPhotos[idx] = ThaiMhungPhoto(
              id: _thaiMhungPhotos[idx].id,
              url: url,
              userName: _thaiMhungPhotos[idx].userName,
              blurStatus: 'completed',
            );
          }
        });
      }
    });
  }

  /// Phase 6.12: รับ event ภาพไทยมุงใหม่เข้ามาแบบ Real-time → เพิ่มเข้า gallery ทันที
  void _subscribeToNewThaiMhungPhotos() {
    _thaiMhungPhotoSub?.cancel();
    _thaiMhungPhotoSub = WebSocketService().thaiMhungPhotoStream.listen((data) {
      final incidentId =
          data['incidentId']?.toString() ?? data['video_id']?.toString() ?? '';
      if (incidentId != _currentVideoId) return;
      final photoId =
          data['photoId']?.toString() ?? data['photo_id']?.toString() ?? '';
      final photoUrl = data['photo_url']?.toString() ?? '';
      final userId = data['user_id']?.toString();
      if (photoId.isEmpty || photoUrl.isEmpty) return;
      if (mounted) {
        setState(() {
          // Avoid duplicate
          if (_thaiMhungPhotos.any((p) => p.id == photoId)) return;
          final normalizedUrl = ServiceLocator.instance.videoRepository
              .ensureFullUrl(photoUrl);
          _thaiMhungPhotos.insert(
            0,
            ThaiMhungPhoto(
              id: photoId,
              url: normalizedUrl,
              userName: userId,
              blurStatus: 'blurring',
            ),
          );
        });
      }
    });
  }

  Future<void> _loadGalleryPhotos() async {
    if (_currentVideoId == null) return;
    _subscribeToPhotoBlurComplete();
    _subscribeToNewThaiMhungPhotos();
    try {
      _galleryPage = 1;
      _hasMoreGallery = true;
      final results = await ServiceLocator.instance.videoRepository
          .getThaiMhungGalleryPhotos(
            _currentVideoId!,
            page: _galleryPage,
            limit: 20,
          );
      debugPrint('[Gallery] Raw results count: ${results.length}');

      if (mounted) {
        final photos = results
            .map(
              (e) => ThaiMhungPhoto(
                id: e['id']?.toString() ?? '',
                url: e['photo_url']?.toString() ?? '',
                userName: e['user_id']?.toString(),
                blurStatus: e['blur_status']?.toString() ?? 'completed',
              ),
            )
            .where((p) => p.id.isNotEmpty)
            .toList();

        debugPrint('[Gallery] Valid photos after filter: ${photos.length}');
        for (var p in photos) {
          debugPrint(
            '[Gallery] API photo: id=${p.id}, blurStatus=${p.blurStatus}',
          );
        }
        setState(() {
          // Phase 6.12: Merge API results with local blurring photos not yet in DB
          final apiIds = photos.map((p) => p.id).toSet();
          final localBlurring = _thaiMhungPhotos
              .where(
                (p) => p.blurStatus == 'blurring' && !apiIds.contains(p.id),
              )
              .toList();
          debugPrint(
            '[Gallery] Local blurring photos to preserve: ${localBlurring.length}',
          );
          _thaiMhungPhotos = [...localBlurring, ...photos];
          debugPrint(
            '[Gallery] Final merged count: ${_thaiMhungPhotos.length}',
          );
          if (photos.length < 20) _hasMoreGallery = false;
        });
      }
    } catch (e) {
      debugPrint('[Gallery] Error loading gallery photos: $e');
    }
  }

  Future<void> _loadMoreGalleryPhotos() async {
    if (_currentVideoId == null || !_hasMoreGallery || _isLoadingMoreGallery)
      return;
    if (mounted) setState(() => _isLoadingMoreGallery = true);
    try {
      _galleryPage++;
      final results = await ServiceLocator.instance.videoRepository
          .getThaiMhungGalleryPhotos(
            _currentVideoId!,
            page: _galleryPage,
            limit: 20,
          );

      if (mounted) {
        final photos = results
            .map(
              (e) => ThaiMhungPhoto(
                id: e['id']?.toString() ?? '',
                url: e['photo_url']?.toString() ?? '',
                userName: e['user_id']?.toString(),
                blurStatus: e['blur_status']?.toString() ?? 'completed',
              ),
            )
            .where((p) => p.id.isNotEmpty)
            .toList();

        setState(() {
          // Phase 6.12: Deduplicate when loading more pages
          final existingIds = _thaiMhungPhotos.map((p) => p.id).toSet();
          final newPhotos = photos
              .where((p) => !existingIds.contains(p.id))
              .toList();
          _thaiMhungPhotos.addAll(newPhotos);
          _isLoadingMoreGallery = false;
          if (photos.length < 20) _hasMoreGallery = false;
        });
      }
    } catch (e) {
      debugPrint('[Gallery] Error loading more gallery photos: $e');
      if (mounted) setState(() => _isLoadingMoreGallery = false);
    }
  }

  Future<void> _loadResponders() async {
    try {
      final responders = await ServiceLocator.instance.videoRepository
          .getIncidentResponders(_currentVideoId!);
      if (mounted) {
        setState(() {
          double parseDouble(dynamic value) {
            if (value == null) return 0.0;
            if (value is num) return value.toDouble();
            if (value is String) return double.tryParse(value) ?? 0.0;
            return 0.0;
          }

          final String? myUserId = AuthService.instance.userId;

          for (int i = 0; i < responders.length; i++) {
            var r = responders[i];
            r['currentLat'] = r['startLat'];
            r['currentLng'] = r['startLng'];

            // Check if user is already a responder
            if (myUserId != null && r['volunteerId'] == myUserId) {
              _currentResponseId = r['id']?.toString();
            }

            if (r['startLat'] != null &&
                r['startLng'] != null &&
                _currentVideo != null) {
              final double distanceMeters = Geolocator.distanceBetween(
                parseDouble(r['startLat']),
                parseDouble(r['startLng']),
                _currentVideo!.latitude,
                _currentVideo!.longitude,
              );
              final double distanceKm = distanceMeters / 1000;
              r['distanceKm'] = distanceKm;
              final int mins = (distanceKm / 40 * 60).round().clamp(1, 120);
              r['estimatedMinutes'] = mins;
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
    if (_routePoints.isEmpty) {
      if (_currentVideoId == null && _userLocation != null)
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(_userLocation!, 15.0),
        );
      return;
    }
    if (_responders.isEmpty) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_routePoints.last, 17.0),
      );
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
    } catch (_) {}
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
      _trendingPage = 1;
      _hasMoreTrending = true;
      final videos = await ServiceLocator.instance.videoRepository
          .getEmergencyVideos(page: _trendingPage, limit: 20);
      if (mounted) {
        setState(() {
          _trendingVideos = videos;
          _isLoadingTrending = false;
          if (videos.length < 20) _hasMoreTrending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingTrending = false);
        ErrorHandler.showErrorSnackBar(
          context,
          e,
          onRetry: _loadTrendingVideos,
        );
      }
    }
  }

  Future<void> _loadMoreTrendingVideos() async {
    if (!_hasMoreTrending || _isLoadingMoreTrending) return;
    if (mounted) setState(() => _isLoadingMoreTrending = true);
    try {
      _trendingPage++;
      final videos = await ServiceLocator.instance.videoRepository
          .getEmergencyVideos(page: _trendingPage, limit: 20);
      if (mounted) {
        setState(() {
          _trendingVideos.addAll(videos);
          _isLoadingMoreTrending = false;
          if (videos.length < 20) _hasMoreTrending = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMoreTrending = false);
    }
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
          final category = _emergencyCategories
              .where((c) => c.id == catId)
              .firstOrNull;
          if (category != null &&
              category.volunteerProfessionIds.contains(user.professionId))
            _canViewUnblurred = true;
        }
        if (_currentResponseId != null) _canViewUnblurred = true;
      });
    }
    if (isOwner) return;
    try {
      final victimProfile = await Supabase.instance.client
          .from('consumer_profiles')
          .select('unblurred_profession_ids')
          .eq('user_id', _currentVideo!.userId)
          .maybeSingle();
      if (victimProfile != null) {
        final List<dynamic> allowedIds =
            victimProfile['unblurred_profession_ids'] ?? [];
        final currentUser = AuthService.instance.currentUser;
        if (currentUser != null && currentUser.professionId != null) {
          if (allowedIds
              .map((id) => id.toString())
              .contains(currentUser.professionId)) {
            if (mounted) setState(() => _canViewUnblurred = true);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _openInGoogleMaps() async {
    if (_currentVideo == null) return;
    final lat = _currentVideo!.latitude;
    final lng = _currentVideo!.longitude;
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    if (await canLaunchUrl(Uri.parse(url)))
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _updateRescueStatus(String status) async {
    if (_currentResponseId == null || _currentVideoId == null) return;
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;
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
        SnackBar(
          content: Text(
            'อัปเดตสถานะเป็น: ${status == 'arrived' ? 'มาถึงแล้ว' : 'เสร็จสิ้น'}',
          ),
        ),
      );
      if (status == 'resolved')
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).pop();
        });
    }
  }

  /// ตรวจสอบว่าผู้ใช้มีสิทธิ์รับงานช่วยเหลือเหตุการณ์นี้หรือไม่
  /// Rule 1: ปฏิเสธแล้ว (_hasRejected) → ไม่มีสิทธิ์
  /// Rule 2: รับงานไปแล้ว (_currentResponseId != null) → ไม่มีสิทธิ์
  /// Rule 3: เจ้าของวิดีโอ (Reporter) → ไม่มีสิทธิ์
  /// Rule 4: อาชีพต้องตรงกับ volunteerProfessionIds ของหมวดหมู่เหตุการณ์
  /// Rule 5: Profession De-duplication — ถ้ามีคนอาชีพเดียวกันรับงานแล้ว → ไม่มีสิทธิ์
  bool _isEligibleResponder() {
    // Rule 1: ปฏิเสธไปแล้ว
    if (_hasRejected) return false;

    final user = AuthService.instance.currentUser;
    if (user == null || _currentVideo == null) return false;

    // Rule 2: รับงานอยู่แล้ว
    if (_currentResponseId != null) return false;

    final currentUserId = AuthService.instance.userId?.toString();
    final ownerId = _currentVideo?.userId?.toString();
    final authedUserId = user.id.toString();

    // Rule 3: เจ้าของวิดีโอ (Reporter) ไม่สามารถรับงานของตัวเองได้
    final isOwner =
        (ownerId != null) &&
        (ownerId.trim() == authedUserId.trim() ||
            (currentUserId != null && ownerId.trim() == currentUserId.trim()));
    if (isOwner) return false;

    // Rule 4: Category/Profession Match
    final catId = _currentVideo?.categoryId;
    final category = _emergencyCategories
        .where((c) => c.id == catId)
        .firstOrNull;
    if (category == null || category.volunteerProfessionIds.isEmpty)
      return false;

    final userProfId = user.professionId;
    if (!category.volunteerProfessionIds.contains(userProfId)) return false;

    // Rule 5: Profession-based De-duplication
    // ถ้ามีคนอาชีพเดียวกันรับงานอยู่แล้ว (ไม่ใช่ cancelled) → บล็อก
    for (final responder in _responders) {
      if (responder['professionId'] == userProfId &&
          responder['status'] != 'cancelled') {
        return false;
      }
    }

    return true;
  }

  Future<void> _acceptRescue() async {
    if (_currentVideoId == null || !mounted) return;
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;

    // ✅ เพิ่ม Dialog ยืนยันเข้าช่วยเหลือ (Confirmation Dialog) ตามแผน
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.directions_car, color: Colors.blue),
            SizedBox(width: 8),
            Text(
              'ยืนยันเข้าช่วยเหลือ',
              style: TextStyle(
                fontFamily: 'SukhumvitSet',
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          'คุณพร้อมที่จะเดินทางไปช่วยเหลือเหตุการณ์นี้ใช่หรือไม่?\n\nระบบจะเริ่มนำทางและแชร์ตำแหน่งของคุณไปยังผู้แจ้งเหตุทันที',
          style: TextStyle(fontFamily: 'SukhumvitSet'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'ยกเลิก',
              style: TextStyle(color: Colors.grey, fontFamily: 'SukhumvitSet'),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'ยืนยัน',
              style: TextStyle(color: Colors.white, fontFamily: 'SukhumvitSet'),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // 🔍 Debug: ตรวจสอบเงื่อนไขก่อนรับงาน
    debugPrint('🔍 _acceptRescue: videoId=$_currentVideoId, userId=$userId');
    debugPrint(
      '🔍 _acceptRescue: professionId=${AuthService.instance.currentUser?.professionId}',
    );
    debugPrint('🔍 _acceptRescue: userLocation=$_userLocation');
    try {
      final responseId = await ServiceLocator.instance.videoRepository
          .acceptIncident(
            videoId: _currentVideoId!,
            responderId: userId,
            latitude: _userLocation?.latitude,
            longitude: _userLocation?.longitude,
          );
      debugPrint('🔍 _acceptRescue: responseId=$responseId');
      if (responseId == null)
        throw Exception('ไม่สามารถบันทึกการเข้ารับงานได้ (responseId is null)');

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
          'estimatedMinutes': 0,
        });
      }

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

      // Auto-dismiss alert card on Home Page after accept
      try {
        final repo = ServiceLocator.instance.userRepository;
        final saved = await repo.getUiPreference(
          userId,
          'dismissed_emergency_alert_ids',
        );
        final list = saved != null && saved.isNotEmpty
            ? saved.split(',').toList()
            : <String>[];
        if (!list.contains(_currentVideoId!)) {
          list.add(_currentVideoId!);
          await repo.saveUiPreference(
            userId,
            'dismissed_emergency_alert_ids',
            list.join(','),
          );
        }
      } catch (e) {
        debugPrint('Error auto-dismissing alert on accept: $e');
      }

      // ✅ [Phase 3a] Subscribe to emergency health access tokens for this incident
      _subscribeToEmergencyHealthTokens();
    } catch (e, stackTrace) {
      debugPrint('❌ _acceptRescue FAILED: $e');
      debugPrint('❌ StackTrace: $stackTrace');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถตอบรับความช่วยเหลือได้: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  void _switchVideo(String newVideoId) {
    if (_currentVideoId != null)
      WebSocketService().leaveVideoRoom(_currentVideoId!);
    _interactionSub?.cancel();
    _supabaseInteractionSub?.unsubscribe();
    _progressSub?.cancel();
    _rescueIncomingSub?.cancel();
    _videoStatusSub?.cancel();
    _emergencySub?.cancel();
    _photoBlurSub?.cancel();
    _thaiMhungPhotoSub?.cancel();
    _videoPlayerController?.removeListener(_syncGpsWithVideo);
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
    _chewieController?.dispose();
    _chewieController = null;
    setState(() {
      _currentVideoId = newVideoId;
      _highlightVideoId = null;
      _currentVideo = null;
      _dbGpsTracks.clear();
      _routePoints.clear();
      _responders.clear();
      _lastSyncedVideoTrack = null;
      _likeCount = 0;
      _viewerCount = 0;
      // ✅ Reset รายการคำร้องบริจาคเมื่อสลับวิดีโอ
      _activeDonationRequests = [];
      _requestTotals = {};
      _activeRequestIndex = 0;
      _capturedPhotos.clear(); // ✅ เคลียร์รูปภาพไทยมุงที่ถ่ายค้างไว้
    });
    _setupWebSocketStreams();
    _loadInitialData();
    _loadDonationRequests(); // ✅ โหลดคำร้องใหม่สำหรับวิดีโอใหม่
  }

  /// เปิด Fullscreen Video Viewer ตามแผน VIDEO_SYSTEM_PLAN.md ส่วน 3.1
  /// - ใช้ route แยก ไม่ทับ LiveViewWidget เดิม
  /// - ส่ง currentVideoId กลับเมื่อปิด fullscreen เพื่อคงการ์ดล่าสุด
  void _openFullscreen() {
    // เงื่อนไข: ต้องมีการ์ดเหตุการณ์ปัจจุบัน และไม่มี overlay รูปจาก gallery
    if (_currentVideoId == null || _isOverlayVisible) return;
    if (_trendingVideos.isEmpty) return;

    // หา index ของการ์ดปัจจุบันในรายการ trending
    int initialIndex = _trendingVideos.indexWhere(
      (v) => v.id == _currentVideoId,
    );
    if (initialIndex < 0) initialIndex = 0;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, animation, secondaryAnimation) =>
            FullscreenVideoViewer(
              videos: _trendingVideos,
              initialIndex: initialIndex,
              hasMore: _hasMoreTrending,
              onLoadMore: () async {
                await _loadMoreTrendingVideos();
              },
              onVideoChanged: (video) {
                // sync ข้อมูลเบื้องต้นเมื่อเปลี่ยนการ์ดใน fullscreen
                // (ใช้สำหรับ update state ภายใน fullscreen เท่านั้น)
              },
              onDismissed: (currentVideoId) {
                // คงการ์ดเหตุการณ์ล่าสุดที่ดูใน fullscreen
                if (currentVideoId != _currentVideoId) {
                  _switchVideo(currentVideoId);
                }
              },
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void _onThaiMhungTabSelected() async {
    if (_currentVideo == null) {
      setState(() => _selectedTab = 0);
      return;
    }
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'กรุณาเปิดระบบระบุตำแหน่ง (GPS) เพื่อทำหน้าที่ไทยมุง',
            ),
          ),
        );
      return;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied)
      perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPS ถูกปฏิเสธถาวร กรุณาเปิดในตั้งค่า')),
        );
      return;
    }
    setState(() {
      _selectedTab = 0;
      _isThaiMhungReporting = true;
      _isPhotoMode = true; // บังคับโหมดภาพถ่ายสำหรับไทยมุง
      _loadInitialData();
    });
    _initCamera();
  }

  void _initializePlayer(String url, {bool isLocal = false}) {
    // Dispose old controller first
    final oldController = _videoPlayerController;
    _chewieController?.dispose();
    _chewieController = null;
    if (oldController != null) {
      oldController.removeListener(_syncGpsWithVideo);
      oldController.dispose();
    }
    _videoPlayerController = null;

    // Auto-correct local IP changes in URLs from database
    if (!isLocal &&
        url.contains(':3000') &&
        !url.startsWith(AppConfig.localApiUrl)) {
      url = url.replaceAll(
        RegExp(r'http://[0-9\.]+:\d+'),
        AppConfig.localApiUrl,
      );
    }

    final lowerUrl = url.toLowerCase();
    if (lowerUrl.endsWith('.jpg') ||
        lowerUrl.endsWith('.jpeg') ||
        lowerUrl.endsWith('.png') ||
        lowerUrl.endsWith('.webp') ||
        lowerUrl.endsWith('.gif')) {
      // เป็นภาพ ไม่ใช่วิดีโอ ข้ามการโหลด VideoPlayer (UI จะจัดการแสดงภาพแทน)
      return;
    }

    final controller = isLocal
        ? VideoPlayerController.file(File(url))
        : VideoPlayerController.networkUrl(Uri.parse(url));
    _videoPlayerController = controller;

    controller
        .initialize()
        .then((_) {
          // ✅ Guard: ตรวจสอบว่า widget ยังมีชีวิต และ controller ยังไม่ถูก dispose
          // (อาจถูก dispose ก่อน then() ทำงาน หากผู้ใช้เปลี่ยนหน้าหรือ switch วิดีโอ)
          if (!mounted || _videoPlayerController != controller) {
            controller.dispose();
            return;
          }
          final aspectRatio = controller.value.aspectRatio;
          if (!mounted || _videoPlayerController != controller) {
            controller.dispose();
            return;
          }
          setState(() {
            _chewieController = ChewieController(
              videoPlayerController: controller,
              aspectRatio: aspectRatio,
              autoPlay: true,
              looping: false,
              showControls: false,
              placeholder: Container(color: Colors.black),
              errorBuilder: (context, errorMessage) => Center(
                child: Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            );
          });

          // EXPLICIT PLAY FOR IOS AUTO-PLAY IMPROVEMENT
          controller.setVolume(1.0);
          controller.play();

          controller.addListener(_syncGpsWithVideo);
          _adjustMapBounds();
        })
        .catchError((e) {
          // ✅ Guard: จัดการ error อย่างเงียบๆ เพื่อป้องกัน "Bad state: No active player"
          debugPrint('[VideoPlayer] initialize error (may be disposed): $e');
          if (_videoPlayerController == controller) {
            _videoPlayerController = null;
          }
          controller.dispose();
        });
  }

  void _syncGpsWithVideo() {
    if (_videoPlayerController == null ||
        !_videoPlayerController!.value.isInitialized ||
        _dbGpsTracks.isEmpty)
      return;
    final int currentOffset = _videoPlayerController!.value.position.inSeconds;
    final track = _dbGpsTracks.firstWhere(
      (t) => t.timestampOffset >= currentOffset,
      orElse: () => _dbGpsTracks.last,
    );
    if (track != _lastSyncedVideoTrack) {
      _lastSyncedVideoTrack = track;
      if (mounted)
        setState(() {
          _routePoints.add(LatLng(track.latitude, track.longitude));
        });
    }
  }

  /// ✅ ตรวจสอบว่าผู้ใช้คนนี้มีสิทธิ์สร้างคำร้องบริจาคแบบ Inline (ในหน้า Live) หรือไม่
  /// - Reporter: เจ้าของวิดีโอ (ผู้แจ้งเหตุเอง)
  ///   → แผน: ต้องมีผู้ช่วยเหลือ (Responder) เดินทางมาถึงจุดเกิดเหตุแล้ว (status="arrived") อย่างน้อย 1 คน
  ///   เพื่อให้มีพยานว่าเกิดเหตุการณ์นั้นจริง
  /// - Responder: มี _currentResponseId และอาชีพอยู่ใน volunteer_profession_ids
  bool _canCreateDonationRequest() {
    final user = AuthService.instance.currentUser;
    if (user == null || _currentVideo == null) return false;

    final currentUserId = user.id?.toString();
    final ownerId = _currentVideo?.userId?.toString();

    // Reporter: เจ้าของวิดีโอ (ผู้แจ้งเหตุเอง)
    // เงื่อนไขเพิ่มเติม: ต้องมี responder คนใดคนหนึ่งที่ status = 'arrived' ก่อน
    if (ownerId != null &&
        currentUserId != null &&
        ownerId.trim() == currentUserId.trim()) {
      final hasArrivedResponder = _responders.any(
        (r) => r['status'] == 'arrived',
      );
      return hasArrivedResponder;
    }

    // Responder: รับงานช่วยเหลือแล้ว และอาชีพตรงกับหมวดหมู่
    if (_currentResponseId != null) {
      final catId = _currentVideo?.categoryId;
      final category = _emergencyCategories
          .where((c) => c.id == catId)
          .firstOrNull;
      final userProfId = user.professionId;
      if (category != null &&
          userProfId != null &&
          category.volunteerProfessionIds.contains(userProfId)) {
        return true;
      }
    }
    return false;
  }

  /// ✅ ตรวจสอบว่าผู้ใช้ปัจจุบันเป็น Reporter (เจ้าของวิดีโอ/ผู้แจ้งเหตุ) หรือไม่
  bool _isCurrentUserReporter() {
    final user = AuthService.instance.currentUser;
    if (user == null || _currentVideo == null) return false;
    final currentUserId = user.id?.toString();
    final ownerId = _currentVideo?.userId?.toString();
    return ownerId != null &&
        currentUserId != null &&
        ownerId.trim() == currentUserId.trim();
  }

  void _showDonationSheet() {
    if (_currentVideoId == null) return;

    if (_canCreateDonationRequest()) {
      // ✅ โหมด Reporter/Responder: เปิด Sheet สร้างคำร้องบริจาคใหม่
      _showCreateDonationRequestSheet();
    } else {
      // ✅ โหมด Viewer/ThaiMhung: เปิด Sheet เลือก/บริจาคคำร้องที่มีอยู่
      if (_activeDonationRequests.isEmpty)
        return; // ซ่อนโดยไม่ไปถึงทั้งนี้เพราะปุ่มซ่อนอยู่เมื่อไม่มีคำร้อง
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DonationSheetWidget(
          videoId: _currentVideoId!,
          preloadedRequests: _activeDonationRequests,
          onDonate: (amount, requestId) {
            setState(() {
              if (requestId != null) {
                _requestTotals[requestId] =
                    (_requestTotals[requestId] ?? 0) + amount;
              }
            });
            final userId =
                ServiceLocator.instance.currentUser?.id ?? 'anonymous';
            final socket = WebSocketService().socket;
            if (socket != null && socket.connected && _currentVideoId != null) {
              socket.emit('video-interaction', {
                'videoId': _currentVideoId,
                'userId': userId,
                'type': 'gift',
                'value': amount,
                if (requestId != null) 'requestId': requestId,
              });
            }

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ขอบคุณที่สนับสนุนจำนวน ฿${NumberFormat('#,##0').format(amount)}',
                          style: const TextStyle(
                            fontFamily: 'SukhumvitSet',
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.green.shade600,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          },
        ),
      );
    }
  }

  /// ✅ เปิดหน้าสร้างคำร้องบริจาคสำหรับ Reporter/Responder
  /// ทั้ง Reporter และ Responder เปลี่ยนหมวดหมู่ได้ เพียงแต่ไม่รวมหมวดฉุกเฉิน (is_emergency=true)
  void _showCreateDonationRequestSheet() {
    if (_currentVideoId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DonationCreatePage(
          videoId: _currentVideoId,
          defaultCategoryId: _currentVideo?.categoryId,
        ),
      ),
    ).then((newRequestId) async {
      // Reload active requests when returning
      await _loadDonationRequests();

      // เลือกคำร้องที่เพิ่งสร้างขึ้นมาใหม่หากถูก return กลับมา
      if (newRequestId is String && mounted) {
        final index = _activeDonationRequests.indexWhere(
          (r) => r.id == newRequestId,
        );
        if (index != -1) {
          setState(() {
            _activeRequestIndex = index;
          });
        }
      }
    });
  }

  /// ✅ ดึงรายการคำร้องบริจาคที่เปิดใช้งานสำหรับวิดีโอนี้
  Future<void> _loadDonationRequests() async {
    if (_currentVideoId == null) return;
    try {
      final repo = DonationRepository(Supabase.instance.client);
      final requests = await repo.getRequestsByVideoId(
        _currentVideoId!,
        activeOnly: true,
      );
      if (mounted) {
        setState(() {
          _activeDonationRequests = requests;
          _activeRequestIndex = 0;
          for (final r in requests) {
            if (r.id != null) {
              _requestTotals[r.id!] = r.currentAmount ?? 0.0;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('[EmergencyLivePage] Failed to load donation requests: $e');
    }
  }

  Future<void> _reportThaiMhungEmergency(String description) async {
    final userId = AuthService.instance.userId;
    if (userId == null || _capturedPhotos.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      List<File> files = _capturedPhotos.map((x) => File(x.path)).toList();
      final uploadResult = await ServiceLocator.instance.videoRepository
          .uploadEmergencyPhotos(
            userId: userId,
            photoFiles: files,
            gpsTracks: _recordedGpsTracks,
            categoryId: _selectedEmergencyCategoryId,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ส่งข้อมูลไทยมุงสำเร็จ กำลังปกป้องสิทธิ์ส่วนบุคคล...',
            ),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _capturedPhotos.clear();
          _selectedTab = 0;
          _isThaiMhungReporting = false;
        });
        // Phase 6.12: Immediately add placeholder photos with blurStatus='blurring'
        final photoIds = uploadResult?['photoIds'] as List<dynamic>?;
        final photoUrls = uploadResult?['photo_urls'] as List<dynamic>?;
        if (photoIds != null &&
            photoUrls != null &&
            photoIds.length == photoUrls.length) {
          setState(() {
            for (int i = 0; i < photoIds.length; i++) {
              final photoId = photoIds[i].toString();
              final photoUrl = photoUrls[i].toString();
              if (photoId.isNotEmpty && photoUrl.isNotEmpty) {
                final normalizedUrl = ServiceLocator.instance.videoRepository
                    .ensureFullUrl(photoUrl);
                _thaiMhungPhotos.insert(
                  0,
                  ThaiMhungPhoto(
                    id: photoId,
                    url: normalizedUrl,
                    userName: userId,
                    blurStatus: 'blurring',
                  ),
                );
              }
            }
          });
        }
        _loadGalleryPhotos();
      }
    } catch (_) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดในการส่งข้อมูล')),
        );
      }
    }
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      final k = count / 1000;
      return k == k.roundToDouble()
          ? '${k.round()}K'
          : '${k.toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  /// ✅ [Support Analytics] Toggle Like via DB Unique constraint
  /// - HTTP POST → Server checks existing row → DELETE (unlike) or INSERT (like)
  /// - Updates _hasLiked + _likeCount from response
  /// - Emits 'like-toggled' socket event for real-time broadcast to room
  Future<void> _onLike() async {
    final userId = AuthService.instance.currentUser?.id ?? 'anonymous';
    if (_currentVideoId == null) return;
    try {
      final result = await ServiceLocator.instance.videoRepository.toggleLike(
        _currentVideoId!,
        userId,
      );
      final liked = result['liked'] as bool? ?? !_hasLiked;
      final count = result['count'] as int? ?? _likeCount;
      if (mounted) {
        setState(() {
          _hasLiked = liked;
          _likeCount = count;
          _likeTrigger++; // force chart refresh
        });
      }
      // Broadcast to room via WebSocket so other viewers see updated count
      final socket = WebSocketService().socket;
      if (socket != null && socket.connected) {
        socket.emit('like-toggled', {
          'videoId': _currentVideoId,
          'userId': userId,
          'liked': liked,
          'count': count,
        });
      }
    } catch (e) {
      debugPrint('_onLike: toggle failed — $e');
    }
  }

  /// ✅ [Support Analytics] Check initial like status when video loads
  Future<void> _loadLikeStatus() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || _currentVideoId == null) return;
    try {
      final liked = await ServiceLocator.instance.videoRepository.getLikeStatus(
        _currentVideoId!,
        userId,
      );
      if (mounted) setState(() => _hasLiked = liked);
    } catch (_) {}
  }

  Future<void> _loadThaiMhungPhotos() async {
    if (_currentVideo?.categoryId == null) return;
    try {
      final photos = await ServiceLocator.instance.videoRepository
          .getThaiMhungPhotos(_currentVideo!.categoryId!);
      setState(() {
        _thaiMhungPhotos = photos
            .map(
              (v) => ThaiMhungPhoto(
                id: v.id,
                url: v.bunnyUrl ?? '',
                userName: v.userName,
              ),
            )
            .where((p) => p.url.isNotEmpty)
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _yieldWay() async {
    if (_currentVideoId == null) return;
    final userId = AuthService.instance.currentUser?.id ?? 'anonymous';
    try {
      final interaction = VideoInteraction(
        id: '',
        videoId: _currentVideoId!,
        userId: userId,
        type: 'yield-way',
        createdAt: AppConfig.currentUtc,
      );
      await ServiceLocator.instance.videoRepository.addInteraction(interaction);
      // ✅ Emit via WebSocket for real-time update
      WebSocketService().sendVideoInteraction(
        _currentVideoId!,
        userId,
        'yield-way',
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ขอบคุณที่ช่วยเปิดทางให้รถฉุกเฉิน! 🚑💙'),
            backgroundColor: Colors.blue,
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {}
  }

  void _showPhotoDetail(ThaiMhungPhoto photo) {
    if (photo.blurStatus == 'blurring') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ภาพกำลังถูกปกป้องสิทธิ์ส่วนบุคคล กรุณารอสักครู่'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
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
              child: Image.network(photo.url, fit: BoxFit.contain),
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

  Future<void> _loadConfigFromDatabase() async {
    try {
      final config = await Supabase.instance.client
          .from('app_config')
          .select()
          .maybeSingle();
      if (config != null) {
        // อัปเดต AppConfig โค้ดกลาง
      }
    } catch (_) {}
  }
}
