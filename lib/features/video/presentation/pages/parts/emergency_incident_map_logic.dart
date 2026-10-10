part of '../emergency_live_page.dart';

/// ═══════════════════════════════════════════════════════════════════
/// Phase 22 — แผนที่เกิดเหตุ (Category-specific Incident Overview Map)
/// VIDEO_SYSTEM_PLAN.md §22.3 — mode/state machine และ UI invariants
/// ═══════════════════════════════════════════════════════════════════

/// โหมดพื้นผิวของหน้า — แยกจาก `_selectedTab` และ `_isThaiMhungReporting`
/// (§22.3 ข้อ 2: ห้ามใช้ Navigator.pop ปิดโหมดแผนที่)
enum EmergencySurfaceMode { live, incidentMap }

/// สถานะข้อมูลแผนที่ (§22.3.3)
enum IncidentMapUiState { loading, ready, empty, error, degraded }

/// Session ของโหมดแผนที่ — เก็บทุกอย่างที่ต้องคืนเมื่อกลับมา (§22.3 ข้อ 3)
class IncidentMapSession {
  final String categoryId;
  final String categoryName;

  /// การ์ดที่เลือกจากแผนที่ (ปักบนสุดของกล่องยอดนิยมพร้อมป้าย — §22.1)
  String? pinnedVideoId;

  /// เหตุที่ map-playback ต้องโฟกัสเมื่อ Back กลับมาแผนที่ พร้อม zoom ที่
  /// เปิด preview cards ของอัลบั้มได้ (§22.14)
  IncidentMapCameraFocus? returnFocus;

  /// ภาพที่รอเปิด overlay หลังสลับการ์ดเสร็จ (§22.3 ข้อ 5)
  String? pendingOverlayPhotoId;
  String? pendingOverlayPhotoUrl;
  int photoHandoffGeneration = 0;

  /// สถานะ playback ก่อนเข้าโหมดแผนที่ — resume เฉพาะเมื่อก่อนหน้าเล่นอยู่
  bool wasPlayingBeforeMap = false;
  Duration? playbackPositionBeforeMap;

  /// viewport cache ล่าสุด — ใช้คืนทันทีเมื่อย้อนจาก map-playback กลับแผนที่
  IncidentMapResponse? lastResponse;
  int? lastFetchedZoom;
  IncidentMapBounds? lastFetchedBounds;

  /// camera ล่าสุด — บันทึกทุก settle (ไม่ใช่เฉพาะตอน refetch) เพื่อคืน
  /// ตำแหน่ง/ซูมเดิมเมื่อกลับเข้าโหมดแผนที่ (§22.11 fix 2)
  IncidentMapBounds? lastCameraBounds;
  double? lastCameraZoom;
  bool refreshOnNextCameraSettle = false;

  IncidentMapSession({required this.categoryId, required this.categoryName});
}

extension EmergencyIncidentMapLogic on _EmergencyLivePageState {
  // ──────────────────────────────────────────────────────────────
  // Feature gate (§22.6 — server-driven via map-config)
  // ──────────────────────────────────────────────────────────────

  /// โหลด config ครั้งเดียวตอนเปิดหน้า — gate ปิด = ไม่มีปุ่มใน sheet
  Future<void> _loadIncidentMapGate() async {
    try {
      final snapshot = await MapConfigService().load();
      if (!mounted) return;
      final platform = PlatformService.mapPlatform;
      final target = snapshot.config.resolveTarget(
        MapFeature.emergency,
        platform,
      );
      final tileSource = target.renderer == MapRendererKind.osm
          ? snapshot.registry[target.tileSourceId]
          : null;
      setState(() {
        _incidentOverviewMapEnabled =
            snapshot.config.incidentOverviewMapEnabled;
        _incidentMapAvailability = IncidentMapAvailability(
          enabled: target.enabled,
          renderer: target.renderer,
          tileSource: tileSource,
          isAppDefault: snapshot.isAppDefault,
        );
      });
    } catch (e) {
      debugPrint('[IncidentMap] gate load failed: $e');
      if (!mounted) return;
      // fail-closed: โหลด config ไม่ได้ = ถือว่าปิด (§22.5 ห้าม silent fallback)
      setState(() => _incidentOverviewMapEnabled = false);
    }
  }

  /// เงื่อนไขแสดงปุ่มใน sheet = gate เปิด + เงื่อนไขเดียวกับปุ่มตัวกรอง
  bool get _canShowIncidentMapEntry =>
      _incidentOverviewMapEnabled && _canShowTrendingCategoryFilter;

  IncidentMapRepository get _incidentMapRepo =>
      _incidentMapRepository ??= IncidentMapRepository(
        normalizeUrl: ServiceLocator.instance.videoRepository.ensureFullUrl,
      );

  // ──────────────────────────────────────────────────────────────
  // Realtime (§22.3.6) — pill "มีเหตุใหม่" ไม่เลื่อน marker/camera เอง
  // ──────────────────────────────────────────────────────────────

  void _subscribeIncidentMapRealtime() {
    _incidentMapRealtimeSub?.cancel();
    _incidentMapRealtimeSub = WebSocketService().emergencyNotificationStream
        .listen((data) {
          if (!mounted || !_isIncidentMapMode) return;
          final session = _incidentMapSession;
          if (session == null) return;
          final categoryId = data['categoryId']?.toString();
          if (categoryId == null || categoryId.isEmpty) return;
          if (categoryId != session.categoryId) return;
          // ผู้แจ้งเป็นตัวเอง → หน้าปกติจัดการอยู่แล้ว ไม่นับซ้ำใน pill
          final currentUserId = AuthService.instance.userId?.toString();
          final reporterId =
              data['userId']?.toString() ?? data['senderId']?.toString();
          final isSelfReport =
              (reporterId != null && currentUserId != null) &&
              (reporterId.trim() == currentUserId.trim());
          if (isSelfReport) return;
          debugPrint(
            '[IncidentMap] new-incident event → count '
            '${_incidentMapNewCount + 1}',
          );
          setState(() => _incidentMapNewCount++);
        });

    // §22.19: ภาพไทยมุงผ่าน blur แล้ว — แผนที่ไม่ได้ join video room จึงต้อง
    // ใช้ global event นี้เพื่อ reload preview ของเหตุที่แสดงอยู่
    _incidentMapPhotoSub?.cancel();
    _incidentMapPhotoSub = WebSocketService().incidentMapPhotoReadyStream
        .listen((data) {
          final incidentId = data['incidentId']?.toString() ?? '';
          if (incidentId.isEmpty) return;
          _scheduleIncidentMapPhotoRefresh(incidentId);
        });
  }

  /// หน่วงการ reload เมื่อมีหลายภาพเสร็จพร้อมกัน (blur ทำงานเป็นชุด)
  void _scheduleIncidentMapPhotoRefresh(String incidentId) {
    if (!mounted || !_isIncidentMapMode) return;
    _incidentMapPhotoRefreshDebounce?.cancel();
    _incidentMapPhotoRefreshDebounce = Timer(
      const Duration(milliseconds: 700),
      () {
        if (mounted) _refreshIncidentMapForPhotoCompletion(incidentId);
      },
    );
  }

  /// ยังมีภาพของเหตุบนแผนที่ที่รอ blur อยู่หรือไม่ (§22.19)
  bool get _incidentMapHasPendingPhotos =>
      _incidentMapData?.items.any(
        (item) =>
            item is IncidentMapPointItem &&
            item.photos.any((photo) => photo.isPending),
      ) ??
      false;

  void _stopIncidentMapPendingPolling() {
    _incidentMapPendingPollTimer?.cancel();
    _incidentMapPendingPollTimer = null;
    _incidentMapPendingPollAttempts = 0;
    _incidentMapPhotoRefreshDebounce?.cancel();
    _incidentMapPhotoRefreshDebounce = null;
  }

  /// Poll สำรองระหว่างรอ blur — กันกรณี WebSocket หลุดแล้วไม่ได้ global event
  /// (หยุดเองเมื่อไม่มีภาพค้าง หรือครบ ~2 นาที)
  void _ensureIncidentMapPendingPolling() {
    if (!_incidentMapHasPendingPhotos) {
      _incidentMapPendingPollAttempts = 0;
      _incidentMapPendingPollTimer?.cancel();
      _incidentMapPendingPollTimer = null;
      return;
    }
    if (_incidentMapPendingPollTimer != null) return;
    _incidentMapPendingPollTimer = Timer.periodic(const Duration(seconds: 8), (
      timer,
    ) {
      if (!mounted || !_isIncidentMapMode) {
        timer.cancel();
        _incidentMapPendingPollTimer = null;
        return;
      }
      if (!_incidentMapHasPendingPhotos ||
          _incidentMapPendingPollAttempts >= 15) {
        timer.cancel();
        _incidentMapPendingPollTimer = null;
        _incidentMapPendingPollAttempts = 0;
        return;
      }
      _incidentMapPendingPollAttempts++;
      final session = _incidentMapSession;
      _fetchIncidentMapData(
        bounds: session?.lastCameraBounds,
        zoom: session?.lastCameraZoom?.toInt(),
      );
    });
  }

  void _refreshIncidentMapFromPill() {
    final session = _incidentMapSession;
    debugPrint(
      '[IncidentMap] pill tapped → refetch '
      '(newCount=$_incidentMapNewCount, '
      'zoom=${session?.lastCameraZoom}, '
      'bounds=${session?.lastCameraBounds})',
    );
    setState(() {
      _incidentMapNewCount = 0;
      // แสดง spinner ระหว่าง refresh ที่ผู้ใช้กดเอง — เดิม fetch เงียบ
      // ทั้งหมดจึงดูเหมือนไม่มีอะไรเกิดขึ้น (ข้อมูลเดิมยังแสดงอยู่ใต้ spinner)
      if (_incidentMapData != null) {
        _incidentMapUiState = IncidentMapUiState.loading;
      }
    });
    _fetchIncidentMapData(
      bounds: session?.lastCameraBounds,
      zoom: session?.lastCameraZoom?.toInt(),
    );
  }

  void _refreshIncidentMapForPhotoCompletion(String incidentId) {
    final session = _incidentMapSession;
    if (!mounted || session == null || !_isIncidentMapMode) return;
    final isOnCurrentMap =
        session.pinnedVideoId == incidentId ||
        (_incidentMapData?.items.any(
              (item) =>
                  item is IncidentMapPointItem &&
                  item.id == incidentId &&
                  item.categoryId == session.categoryId,
            ) ??
            false);
    if (!isOnCurrentMap) return;
    _fetchIncidentMapData(
      bounds: session.lastCameraBounds,
      zoom: session.lastCameraZoom?.toInt(),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Entry / exit (§22.3.1 transition table)
  // ──────────────────────────────────────────────────────────────

  /// จาก sheet: sheet ปิดตัวเองแล้ว (ไม่ commit draft) — ที่นี่เข้าโหมดแผนที่ต่อ
  void _openIncidentMapForCategory(DonationCategory category) {
    _enterIncidentMapMode(category);
  }

  Future<void> _enterIncidentMapMode(DonationCategory category) async {
    if (_missionFilterSuspended) return; // §22.3 ข้อ 7
    _stopIncidentMapFetchRetry();
    final isNewCategory = _incidentMapSession?.categoryId != category.id;
    setState(() {
      _isChatVisible = false; // §22.3.2
      _isUiVisible = true;
      _incidentMapNewCount = 0;
      if (isNewCategory || _incidentMapSession == null) {
        _incidentMapSession = IncidentMapSession(
          categoryId: category.id,
          categoryName: category.name,
        );
        _incidentMapData = null;
        _incidentMapHighlightedBucket = null;
      }
      _surfaceMode = EmergencySurfaceMode.incidentMap;
      _incidentMapUiState = IncidentMapUiState.loading;
    });
    _pausePlayerForMap();
    await _fetchIncidentMapData();
  }

  /// pause player และจำสถานะเดิม — resume เฉพาะเมื่อก่อนหน้าเล่นอยู่ (§22.3 ข้อ 3)
  void _pausePlayerForMap() {
    final controller = _videoPlayerController;
    if (controller == null) return;
    try {
      final value = controller.value;
      if (_incidentMapSession != null &&
          _surfaceMode != EmergencySurfaceMode.incidentMap) {
        _incidentMapSession!.wasPlayingBeforeMap = value.isPlaying;
        _incidentMapSession!.playbackPositionBeforeMap = value.position;
      }
      if (value.isPlaying) controller.pause();
    } catch (_) {}
  }

  void _resumePlayerFromMap() {
    final session = _incidentMapSession;
    final controller = _videoPlayerController;
    if (session == null || controller == null) return;
    try {
      if (session.wasPlayingBeforeMap) {
        if (session.playbackPositionBeforeMap != null) {
          controller.seekTo(session.playbackPositionBeforeMap!);
        }
        controller.play();
      }
    } catch (_) {}
    session.wasPlayingBeforeMap = false;
  }

  /// คืนจาก incident map surface ไปยัง Emergency surface โดยไม่ pop หน้า
  void _exitIncidentMapMode() {
    setState(() => _surfaceMode = EmergencySurfaceMode.live);
    _stopIncidentMapPendingPolling();
    _stopIncidentMapFetchRetry();
    _resumePlayerFromMap();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _adjustMapBounds();
    });
  }

  /// เปลี่ยนจากแผนที่ไปยังหน้าเล่นวิดีโอ พร้อมเปิด feed ชั่วคราวของหมวดแผนที่
  /// (ทุก incident ในหมวดนั้น; ไม่เปลี่ยนตัวกรองที่ commit จาก sheet)
  void _showIncidentMapCategoryFeed() {
    final session = _incidentMapSession;
    if (session == null) return;
    setState(() {
      _surfaceMode = EmergencySurfaceMode.live;
      _isLoadingTrending = true;
      _isLoadingMoreTrending = false;
      _trendingFilterResetToken++;
    });
    unawaited(
      _loadTrendingVideos(
        forceRefresh: true,
        categoryIdsOverride: {session.categoryId},
      ).then<void>((_) {}),
    );
  }

  /// แตะหมุด → กลับมาเล่นการ์ดเหตุการณ์นั้น และแสดงการ์ดทั้งหมดในหมวดแผนที่
  void _selectIncidentFromMap(IncidentMapPointItem point) {
    final session = _incidentMapSession;
    if (session == null || point.categoryId != session.categoryId) return;
    session.pinnedVideoId = point.id;
    session.returnFocus = IncidentMapCameraFocus.forPoint(point);
    session.photoHandoffGeneration++;
    session.pendingOverlayPhotoId = null;
    session.pendingOverlayPhotoUrl = null;
    _showIncidentMapCategoryFeed();
    _switchVideo(point.id, refreshTrending: false);
  }

  void _updateIncidentMapReturnFocusForVideo(
    String videoId, {
    String? categoryId,
    double? latitude,
    double? longitude,
  }) {
    final session = _incidentMapSession;
    if (!_hasIncidentMapPlaybackContext || session == null) return;
    if (categoryId != null && categoryId != session.categoryId) return;

    for (final item in _incidentMapData?.items ?? const <IncidentMapItem>[]) {
      if (item is IncidentMapPointItem &&
          item.id == videoId &&
          item.categoryId == session.categoryId) {
        session.pinnedVideoId = item.id;
        session.returnFocus = IncidentMapCameraFocus.forPoint(item);
        return;
      }
    }

    bool validCoordinates(double? lat, double? lng) =>
        lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        !(lat == 0 && lng == 0) &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;

    var resolvedCategoryId = categoryId;
    var resolvedLatitude = latitude;
    var resolvedLongitude = longitude;
    for (final video in _trendingVideos) {
      if (video.id != videoId) continue;
      resolvedCategoryId ??= video.categoryId;
      if (!validCoordinates(resolvedLatitude, resolvedLongitude) &&
          validCoordinates(video.latitude, video.longitude)) {
        resolvedLatitude = video.latitude;
        resolvedLongitude = video.longitude;
      }
      break;
    }
    if (resolvedCategoryId != session.categoryId ||
        !validCoordinates(resolvedLatitude, resolvedLongitude)) {
      return;
    }
    session.pinnedVideoId = videoId;
    session.returnFocus = IncidentMapCameraFocus(
      incidentId: videoId,
      latitude: resolvedLatitude!,
      longitude: resolvedLongitude!,
      zoom: IncidentMapZoomPolicy.photoOverviewZoom,
    );
  }

  /// ปุ่มย้อนกลับใน video map-return context → คืนแผนที่เดิมพร้อม camera/cache
  void _returnToIncidentMap() {
    if (_missionFilterSuspended) return; // §22.3 ข้อ 7
    final session = _incidentMapSession;
    if (session == null) return;
    final playingVideo = _currentVideo;
    final playingVideoId = _currentVideoId;
    if (playingVideoId != null) {
      _updateIncidentMapReturnFocusForVideo(
        playingVideoId,
        categoryId: playingVideo?.categoryId,
        latitude: playingVideo?.latitude,
        longitude: playingVideo?.longitude,
      );
    }
    final waitForCameraSettle = session.returnFocus != null;
    session.refreshOnNextCameraSettle = waitForCameraSettle;
    _stopIncidentMapFetchRetry();
    setState(() {
      _isChatVisible = false;
      _isUiVisible = true;
      _surfaceMode = EmergencySurfaceMode.incidentMap;
      _incidentMapUiState = IncidentMapUiState.loading;
    });
    _pausePlayerForMap();
    if (!waitForCameraSettle) {
      _fetchIncidentMapData(
        bounds: session.lastCameraBounds,
        zoom: session.lastCameraZoom?.toInt(),
      );
    } else {
      // Fallback: ถ้ากล้องคืนไปที่ตำแหน่งเดิมแล้ว platform ไม่ยิง settle
      // event (ไม่มีการขยับ → onCameraIdle เงียบ) refresh จะค้างตลอดจน
      // ผู้ใช้ขยับเอง — ภาพที่เพิ่งอัปโหลด/เปลี่ยน blur จะไม่โหลดขึ้นมา
      Timer(const Duration(milliseconds: 1200), () {
        final s = _incidentMapSession;
        if (!mounted ||
            s == null ||
            !identical(s, session) ||
            !_isIncidentMapMode ||
            !s.refreshOnNextCameraSettle) {
          return;
        }
        s.refreshOnNextCameraSettle = false;
        _fetchIncidentMapData(
          bounds: s.lastCameraBounds ?? s.lastFetchedBounds,
          zoom: (s.lastCameraZoom ?? s.lastFetchedZoom?.toDouble())?.toInt(),
        );
      });
    }
  }

  /// ปุ่ม "ปิด" ใน map-playback หรือปุ่มปิดแผนที่ → กลับ Emergency ปกติ
  /// และคืน category scope ที่ commit ไว้ใน Trending sheet (ไม่เอา map scope
  /// ไปเขียนทับตัวกรองเดิม)
  Future<void> _closeIncidentMapContext() async {
    final session = _incidentMapSession;
    final currentVideoIdAtClose = _currentVideoId;
    if (_isIncidentMapMode) {
      _exitIncidentMapMode();
    } else {
      setState(() {
        _isChatVisible = false;
        _isUiVisible = true;
      });
    }
    if (session != null) {
      session.photoHandoffGeneration++;
      session.pinnedVideoId = null;
      session.pendingOverlayPhotoId = null;
      session.pendingOverlayPhotoUrl = null;
    }
    _stopIncidentMapPendingPolling();
    _stopIncidentMapFetchRetry();
    setState(() {
      _incidentMapSession = null;
      _incidentMapData = null;
      _incidentMapNewCount = 0;
      _isLoadingTrending = true;
      _isLoadingMoreTrending = false;
      _trendingFilterResetToken++;
    });
    final loaded = await _loadTrendingVideos(forceRefresh: true);
    if (!loaded || !mounted) return;
    _autoSwitchForTrendingCategoryFilter(
      currentVideoIdAtApply: currentVideoIdAtClose,
      selectedCategoryIds: _selectedTrendingCategoryIds,
    );
  }

  /// ปุ่ม "เปลี่ยนประเภทเหตุ" ในโหมดแผนที่ (§22.13) — เปิด glass dialog ที่
  /// ลิสต์ปุ่มประเภทเหตุฉุกเฉินจากตารางจริง (ลำดับเดียวกับ sheet ตัวกรอง)
  /// เลือกแล้วสลับหมวดของแผนที่ทันที — ไม่แตะตัวกรองยอดนิยมที่ commit อยู่
  Future<void> _openIncidentMapCategoryPicker() async {
    if (_missionFilterSuspended) return; // §22.3 ข้อ 7
    final picked = await IncidentCategoryPickerDialog.show(
      context,
      categories: _emergencyCategories,
      currentCategoryId: _incidentMapSession?.categoryId,
    );
    if (!mounted || picked == null) return;
    await _enterIncidentMapMode(picked);
  }

  // ──────────────────────────────────────────────────────────────
  // Data fetch (§22.4.3 — viewport + generation guard)
  // ──────────────────────────────────────────────────────────────

  Future<void> _fetchIncidentMapData({
    IncidentMapBounds? bounds,
    int? zoom,
  }) async {
    final session = _incidentMapSession;
    if (session == null) return;
    final generation = ++_incidentMapFetchGeneration;
    final fetchBounds = bounds ?? IncidentMapBounds.thailand;
    final fetchZoom = zoom ?? 5;
    try {
      final response = await _incidentMapRepo.getIncidentMap(
        categoryId: session.categoryId,
        bounds: fetchBounds,
        zoom: fetchZoom,
      );
      debugPrint(
        '[IncidentMap] fetch ok items=${response.items.length} '
        'zoom=$fetchZoom',
      );
      if (!mounted || generation != _incidentMapFetchGeneration) return;
      session.lastResponse = response;
      session.lastFetchedZoom = fetchZoom;
      session.lastFetchedBounds = fetchBounds;
      _incidentMapFetchRetryCount = 0;
      _incidentMapFetchRetryTimer?.cancel();
      _incidentMapFetchRetryTimer = null;
      setState(() {
        _incidentMapData = response;
        _incidentMapUiState = response.items.isEmpty
            ? IncidentMapUiState.empty
            : IncidentMapUiState.ready;
      });
      // มีภาพค้างเบลอบนแผนที่ → เฝ้า poll สำรองจนกว่าจะครบ (§22.19)
      _ensureIncidentMapPendingPolling();
    } catch (e) {
      debugPrint('[IncidentMap] fetch failed: $e');
      if (!mounted || generation != _incidentMapFetchGeneration) return;
      // §22.20 — มีข้อมูลอยู่แล้ว: เก็บ marker/วงภาพเดิมไว้ + indicator เล็ก
      // (degraded) แทนการ์ดเต็มจอ; การ์ด error เหลือเฉพาะตอนยังไม่มีข้อมูล
      setState(() {
        _incidentMapUiState = _incidentMapData != null
            ? IncidentMapUiState.degraded
            : IncidentMapUiState.error;
      });
      _scheduleIncidentMapFetchRetry(generation);
    }
  }

  /// Auto-retry ด้วย backoff หลัง fetch พลาด — transient (429/timeout/5xx)
  /// หายเองโดยผู้ใช้ไม่ต้องขยับกล้อง (§22.20); หยุดหลัง retry ครบแล้ว
  /// รอให้ผู้ใช้กดเองผ่าน chip/การ์ด
  void _scheduleIncidentMapFetchRetry(int generation) {
    const delays = [
      Duration(milliseconds: 1500),
      Duration(milliseconds: 3000),
    ];
    if (_incidentMapFetchRetryCount >= delays.length) return;
    _incidentMapFetchRetryTimer?.cancel();
    final delay = delays[_incidentMapFetchRetryCount];
    _incidentMapFetchRetryCount++;
    _incidentMapFetchRetryTimer = Timer(delay, () {
      _incidentMapFetchRetryTimer = null;
      final session = _incidentMapSession;
      if (!mounted ||
          session == null ||
          !_isIncidentMapMode ||
          generation != _incidentMapFetchGeneration) {
        return;
      }
      _fetchIncidentMapData(
        bounds: session.lastCameraBounds ?? session.lastFetchedBounds,
        zoom: (session.lastCameraZoom ?? session.lastFetchedZoom?.toDouble())
            ?.toInt(),
      );
    });
  }

  void _stopIncidentMapFetchRetry() {
    _incidentMapFetchRetryTimer?.cancel();
    _incidentMapFetchRetryTimer = null;
    _incidentMapFetchRetryCount = 0;
  }

  /// Retry จากการกดปุ่ม/chip — ใช้ viewport ล่าสุดของ session ไม่ใช่
  /// Thailand default (§22.20 ข้อ 6)
  void _retryIncidentMapFetch() {
    final session = _incidentMapSession;
    _incidentMapFetchRetryCount = 0;
    _fetchIncidentMapData(
      bounds: session?.lastCameraBounds ?? session?.lastFetchedBounds,
      zoom: (session?.lastCameraZoom ?? session?.lastFetchedZoom?.toDouble())
          ?.toInt(),
    );
  }

  /// camera settled → refetch เมื่อ viewport เปลี่ยนพอสมควร (§22.4.3)
  void _onIncidentMapCameraSettled(double zoom, IncidentMapBounds bounds) {
    final session = _incidentMapSession;
    if (session == null || _surfaceMode != EmergencySurfaceMode.incidentMap) {
      return;
    }
    session.lastCameraBounds = bounds;
    session.lastCameraZoom = zoom;
    if (session.refreshOnNextCameraSettle) {
      session.refreshOnNextCameraSettle = false;
      _fetchIncidentMapData(bounds: bounds, zoom: zoom.toInt());
      return;
    }
    final lastZoom = session.lastFetchedZoom;
    final lastBounds = session.lastFetchedBounds;
    final zoomChanged = lastZoom == null || zoom.toInt() != lastZoom;
    final boundsChanged =
        lastBounds == null || !_boundsSimilar(bounds, lastBounds);
    if (zoomChanged || boundsChanged) {
      _fetchIncidentMapData(bounds: bounds, zoom: zoom.toInt());
    }
  }

  static bool _boundsSimilar(IncidentMapBounds a, IncidentMapBounds b) {
    bool close(double x, double y) => (x - y).abs() < 0.05;
    return close(a.south, b.south) &&
        close(a.west, b.west) &&
        close(a.north, b.north) &&
        close(a.east, b.east);
  }

  // ──────────────────────────────────────────────────────────────
  // Photo tap → การ์ดหยุดอยู่เบื้องหลัง + overlay ภาพ (§22.3 ข้อ 5)
  // ──────────────────────────────────────────────────────────────

  void _openIncidentPhotoFromMap(
    IncidentMapPointItem point,
    IncidentMapPhoto photo,
  ) {
    final session = _incidentMapSession;
    if (session == null || point.categoryId != session.categoryId) return;
    final handoffGeneration = ++session.photoHandoffGeneration;
    session.pinnedVideoId = point.id;
    session.returnFocus = IncidentMapCameraFocus.forPoint(point);
    session.pendingOverlayPhotoId = photo.id;
    session.pendingOverlayPhotoUrl = photo.url;
    _showIncidentMapCategoryFeed();
    if (_currentVideoId == point.id) {
      // การ์ดเดียวกันอยู่แล้ว — เปิด overlay ได้ทันที
      _consumePendingOverlayPhoto(handoffGeneration);
    } else {
      _switchVideo(point.id, refreshTrending: false);
      // overlay ต้องตั้งหลัง frame ที่ LiveViewWidget ได้ videoId ใหม่แล้ว
      // (didUpdateWidget ของ overlay จะเคลียร์ overlay เมื่อ videoId เปลี่ยน)
      _consumePendingOverlayPhoto(handoffGeneration);
    }
  }

  /// เรียกหลังการ์ดโหลด — ส่งภาพที่แตะเข้า overlay ของ LiveViewWidget
  void _consumePendingOverlayPhoto(int handoffGeneration) {
    final session = _incidentMapSession;
    final photoId = session?.pendingOverlayPhotoId;
    final url = session?.pendingOverlayPhotoUrl;
    if (session == null ||
        photoId == null ||
        url == null ||
        handoffGeneration != session.photoHandoffGeneration) {
      return;
    }
    session.pendingOverlayPhotoId = null;
    session.pendingOverlayPhotoUrl = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(_incidentMapSession, session) ||
          _surfaceMode != EmergencySurfaceMode.live ||
          handoffGeneration != session.photoHandoffGeneration ||
          _currentVideoId != session.pinnedVideoId) {
        return;
      }
      _liveViewKey.currentState?.showOverlayPhoto(
        photoId: photoId,
        photoUrl: url,
      );
    });
  }

  // ──────────────────────────────────────────────────────────────
  // Layer build (§22.3.2 — แทรกระหว่าง UI overlay กับแถวปุ่ม)
  // ──────────────────────────────────────────────────────────────

  Widget _buildIncidentMapLayer() {
    final session = _incidentMapSession;
    if (session == null) return const SizedBox.shrink();
    final availability = _incidentMapAvailability;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (availability == null)
            IncidentMapStateCard(
              icon: Icons.map_outlined,
              title: 'กำลังโหลดแผนที่เหตุการณ์…',
            )
          else if (!availability.enabled ||
              (availability.renderer == MapRendererKind.osm &&
                  availability.tileSource == null))
            IncidentMapStateCard(
              icon: Icons.map_outlined,
              title: 'แผนที่ถูกปิดใช้งานสำหรับแพลตฟอร์มนี้',
              subtitle: availability.isAppDefault
                  ? 'เชื่อมต่อ server ไม่ได้ — ใช้ค่า default ที่ฝังในแอป'
                  : null,
              actionLabel: 'ปิดแผนที่',
              onAction: _closeIncidentMapContext,
            )
          else ...[
            IncidentMapSurface(
              availability: availability,
              initialBounds:
                  session.lastCameraBounds ?? IncidentMapBounds.thailand,
              initialFocus: session.returnFocus,
              items: _incidentMapData?.items ?? const [],
              highlightedBucket: _incidentMapHighlightedBucket,
              onPointTap: _selectIncidentFromMap,
              onPhotoTap: _openIncidentPhotoFromMap,
              onCameraSettled: _onIncidentMapCameraSettled,
            ),
            if (_incidentMapUiState == IncidentMapUiState.loading)
              const Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
                  ),
                ),
              ),
            if (_incidentMapUiState == IncidentMapUiState.empty)
              IncidentMapStateCard(
                icon: Icons.location_off_outlined,
                title: 'ไม่พบเหตุในหมวดนี้',
                subtitle: 'เหตุในหมวดนี้ยังไม่มีพิกัดที่แสดงได้',
                actionLabel: 'ปิดแผนที่',
                onAction: _closeIncidentMapContext,
              ),
            if (_incidentMapUiState == IncidentMapUiState.error)
              IncidentMapStateCard(
                icon: Icons.cloud_off_outlined,
                title: 'โหลดแผนที่ไม่สำเร็จ',
                actionLabel: 'ลองอีกครั้ง',
                onAction: _retryIncidentMapFetch,
              ),
            // Legend (§22.3.4) — แตะช่วง = เน้น/หรี่ client-side
            // right:16 บังคับ Wrap ตัดบรรทัด (§22.11 fix 1 — เดิมล้นจอ)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: _incidentMapData != null
                  ? IncidentMapLegendBar(
                      legend: _incidentMapData!.legend,
                      highlighted: _incidentMapHighlightedBucket,
                      onHighlight: (bucket) => setState(
                        () => _incidentMapHighlightedBucket = bucket,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // Partial chip (§22.3.3) + realtime pill (§22.3.6) — ชิดขวา
            // เรียงแนวตั้งในคอลัมน์เดียวกันล้นทับกันเมื่อแสดงพร้อมกัน
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // §22.20: fetch พลาดแต่ยังมีข้อมูลเดิม → chip เล็ก ๆ แทน
                  // การ์ดเต็มจอ (แตะเพื่อ retry ทันที)
                  if (_incidentMapUiState == IncidentMapUiState.degraded)
                    GestureDetector(
                      onTap: _retryIncidentMapFetch,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off_outlined,
                              size: 13,
                              color: Colors.white70,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'เชื่อมต่อไม่ได้ — แตะเพื่อลองใหม่',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_incidentMapData != null &&
                      _incidentMapData!.excluded.total > 0) ...[
                    if (_incidentMapUiState == IncidentMapUiState.degraded)
                      const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        'แสดงเฉพาะเหตุที่มีพิกัด (ตัดออก ${_incidentMapData!.excluded.total})',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                  if (_incidentMapNewCount > 0) ...[
                    if (_incidentMapUiState == IncidentMapUiState.degraded ||
                        (_incidentMapData != null &&
                            _incidentMapData!.excluded.total > 0))
                      const SizedBox(height: 8),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _refreshIncidentMapFromPill,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFF6B35,
                          ).withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.new_releases_outlined,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'มีเหตุใหม่ $_incidentMapNewCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

}
