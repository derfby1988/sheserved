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

  /// ภาพที่รอเปิด overlay หลังสลับการ์ดเสร็จ (§22.3 ข้อ 5)
  String? pendingOverlayPhotoId;
  String? pendingOverlayPhotoUrl;
  int photoHandoffGeneration = 0;

  /// สถานะ playback ก่อนเข้าโหมดแผนที่ — resume เฉพาะเมื่อก่อนหน้าเล่นอยู่
  bool wasPlayingBeforeMap = false;
  Duration? playbackPositionBeforeMap;

  /// viewport cache ล่าสุด — ใช้คืนทันทีเมื่อกด "เลือกเหตุการณ์อื่น"
  IncidentMapResponse? lastResponse;
  int? lastFetchedZoom;
  IncidentMapBounds? lastFetchedBounds;

  /// camera ล่าสุด — บันทึกทุก settle (ไม่ใช่เฉพาะตอน refetch) เพื่อคืน
  /// ตำแหน่ง/ซูมเดิมเมื่อกลับเข้าโหมดแผนที่ (§22.11 fix 2)
  IncidentMapBounds? lastCameraBounds;
  double? lastCameraZoom;

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
      final platform = kIsWeb
          ? MapPlatform.web
          : (PlatformService.isIOS ? MapPlatform.ios : MapPlatform.android);
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
          setState(() => _incidentMapNewCount++);
        });
  }

  void _refreshIncidentMapFromPill() {
    final session = _incidentMapSession;
    setState(() => _incidentMapNewCount = 0);
    _fetchIncidentMapData(
      bounds: session?.lastCameraBounds,
      zoom: session?.lastCameraZoom?.toInt(),
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

  /// ปุ่มย้อนกลับ / hardware back จากโหมดแผนที่ — คืนการ์ดเดิม ไม่ pop หน้า
  void _exitIncidentMapMode() {
    setState(() => _surfaceMode = EmergencySurfaceMode.live);
    _resumePlayerFromMap();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _adjustMapBounds();
    });
  }

  /// แตะหมุด → กลับโหมดปกติและเล่นการ์ดเหตุนั้น (§22.3 ข้อ 4)
  void _selectIncidentFromMap(IncidentMapPointItem point) {
    final session = _incidentMapSession;
    if (session == null) return;
    session.pinnedVideoId = point.id;
    session.photoHandoffGeneration++;
    session.pendingOverlayPhotoId = null;
    session.pendingOverlayPhotoUrl = null;
    setState(() => _surfaceMode = EmergencySurfaceMode.live);
    _switchVideo(point.id, refreshTrending: false);
  }

  /// ปุ่ม "เลือกเหตุการณ์อื่น" — คืนแผนที่เดิมพร้อม camera/viewport cache
  void _returnToIncidentMap() {
    final session = _incidentMapSession;
    if (session == null) return;
    setState(() {
      _isChatVisible = false;
      _isUiVisible = true;
      _surfaceMode = EmergencySurfaceMode.incidentMap;
      _incidentMapUiState =
          session.lastResponse != null && _incidentMapData != null
          ? IncidentMapUiState.ready
          : IncidentMapUiState.loading;
    });
    _pausePlayerForMap();
    if (session.lastResponse == null) {
      _fetchIncidentMapData();
    }
  }

  /// ปุ่ม "เปลี่ยนประเภทเหตุ" ในโหมดแผนที่ — เปิด sheet เดิม (ทางออกจาก
  /// บริบท map-return, §22.1) — draft/apply ของ Phase 20 คงเดิมทุกอย่าง
  void _openIncidentMapCategoryPicker() {
    TrendingCategoryFilterSheet.show(
      context,
      categories: _emergencyCategories,
      initialSelectedIds: _selectedTrendingCategoryIds,
      suspensionSignal: _missionSuspendSignal,
      onApply: _applyTrendingCategoryFilter,
      onOpenIncidentMap: _canShowIncidentMapEntry
          ? _openIncidentMapForCategory
          : null,
    );
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
      if (!mounted || generation != _incidentMapFetchGeneration) return;
      session.lastResponse = response;
      session.lastFetchedZoom = fetchZoom;
      session.lastFetchedBounds = fetchBounds;
      setState(() {
        _incidentMapData = response;
        _incidentMapUiState = response.items.isEmpty
            ? IncidentMapUiState.empty
            : IncidentMapUiState.ready;
      });
    } catch (e) {
      debugPrint('[IncidentMap] fetch failed: $e');
      if (!mounted || generation != _incidentMapFetchGeneration) return;
      setState(() => _incidentMapUiState = IncidentMapUiState.error);
    }
  }

  /// camera settled → refetch เมื่อ viewport เปลี่ยนพอสมควร (§22.4.3)
  void _onIncidentMapCameraSettled(double zoom, IncidentMapBounds bounds) {
    final session = _incidentMapSession;
    if (session == null || _surfaceMode != EmergencySurfaceMode.incidentMap) {
      return;
    }
    session.lastCameraBounds = bounds;
    session.lastCameraZoom = zoom;
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
    if (session == null) return;
    final handoffGeneration = ++session.photoHandoffGeneration;
    session.pinnedVideoId = point.id;
    session.pendingOverlayPhotoId = photo.id;
    session.pendingOverlayPhotoUrl = photo.url;
    setState(() => _surfaceMode = EmergencySurfaceMode.live);
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
              actionLabel: 'กลับ',
              onAction: _exitIncidentMapMode,
            )
          else ...[
            IncidentMapSurface(
              availability: availability,
              initialBounds:
                  session.lastCameraBounds ?? IncidentMapBounds.thailand,
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
                onAction: _exitIncidentMapMode,
              ),
            if (_incidentMapUiState == IncidentMapUiState.error)
              IncidentMapStateCard(
                icon: Icons.cloud_off_outlined,
                title: 'โหลดแผนที่ไม่สำเร็จ',
                actionLabel: 'ลองอีกครั้ง',
                onAction: () => _fetchIncidentMapData(),
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
            // Partial chip (§22.3.3) — ตัด record ที่พิกัดใช้ไม่ได้ออก
            if (_incidentMapData != null &&
                _incidentMapData!.excluded.total > 0)
              Positioned(
                top: MediaQuery.of(context).padding.top + 64,
                left: 16,
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
                  child: Text(
                    'แสดงเฉพาะเหตุที่มีพิกัด (ตัดออก ${_incidentMapData!.excluded.total})',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ),
            // Realtime pill (§22.3.6) — กดเพื่อรีเฟรช ไม่ขยับแผนที่เอง
            if (_incidentMapNewCount > 0)
              Positioned(
                top: MediaQuery.of(context).padding.top + 64,
                right: 16,
                child: GestureDetector(
                  onTap: _refreshIncidentMapFromPill,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.92),
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
              ),
          ],
        ],
      ),
    );
  }

}
