import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../services/service_locator.dart';
import 'home_painters.dart';

// ไม่ได้ใช้ flutter_map และ latlong2 อีกต่อไปในไฟล์นี้

/// ===============================================================
/// Home Map Background
/// ---------------------------------------------------------------
/// Logic:
///   1. ดึงตำแหน่ง GPS ของผู้ใช้ — แสดงเป็น default
///   2. Poll active emergency locations ทุก 30 วิ
///   3. ถ้ามี emergency → เลื่อนแผนที่ไปยัง event ที่ใกล้ผู้ใช้ที่สุด
///   4. ถ้า event นั้นจบแล้ว → เลื่อนไป event ถัดไปอัตโนมัติ
/// ===============================================================
class HomeMapBackground extends StatefulWidget {
  const HomeMapBackground({
    super.key,
    this.initialLocation = const gm.LatLng(13.7563, 100.5018),
    this.initialZoom = 14.0,
    this.focusedAlert,
  });

  final gm.LatLng initialLocation;
  final double initialZoom;
  final Map<String, dynamic>? focusedAlert;

  @override
  State<HomeMapBackground> createState() => _HomeMapBackgroundState();
}

class _HomeMapBackgroundState extends State<HomeMapBackground>
    with SingleTickerProviderStateMixin {
  // ─── Map controller ────────────────────────────────────────
  gm.GoogleMapController? _mapController;
  bool _isMapLoaded = false;
  bool _mapHasError = false;
  late AnimationController _shimmerController;

  // ─── User location ─────────────────────────────────────────
  gm.LatLng? _userLatLng;
  bool _locationPermissionDenied = false;

  // ─── Emergency events ──────────────────────────────────────
  List<Map<String, dynamic>> _activeEvents = [];
  Map<String, dynamic>? _focusedEvent; // event ที่กำลังโฟกัสอยู่
  Set<gm.Marker> _markers = {};
  Set<gm.Polyline> _polylines = {}; // เส้นทางนำทาง
  Timer? _refreshTimer;

  // ─── Info banner ───────────────────────────────────────────
  bool _showBanner = false;
  String _bannerTitle = '';
  String _bannerSubtitle = '';

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _initUserLocation();
    _pollEmergencyEvents();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _pollEmergencyEvents(),
    );

    if (widget.focusedAlert != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleFocusedAlert(widget.focusedAlert!);
      });
    }
  }

  @override
  void didUpdateWidget(HomeMapBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusedAlert != oldWidget.focusedAlert) {
      if (widget.focusedAlert != null) {
        _handleFocusedAlert(widget.focusedAlert!);
      } else {
        setState(() {
          _polylines.clear();
        });
      }
    }
  }

  void _handleFocusedAlert(Map<String, dynamic> alert) {
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    final lat = parseDouble(alert['latitude']);
    final lng = parseDouble(alert['longitude']);
    if (lat == 0.0) return;

    final dest = gm.LatLng(lat, lng);
    
    if (_userLatLng != null) {
      setState(() {
        _polylines = {
          gm.Polyline(
            polylineId: const gm.PolylineId('route_to_incident'),
            points: [_userLatLng!, dest],
            color: Colors.red,
            width: 5,
            jointType: gm.JointType.round,
            startCap: gm.Cap.roundCap,
            endCap: gm.Cap.roundCap,
          ),
        };
      });
      _animateToFit(dest, _userLatLng!);
    } else {
      _animateCameraTo(dest, zoom: 15.0);
    }
    
    _showEventBanner(alert);
  }

  void _animateToFit(gm.LatLng p1, gm.LatLng p2) {
    if (_mapController == null) return;
    
    double minLat = min(p1.latitude, p2.latitude);
    double maxLat = max(p1.latitude, p2.latitude);
    double minLng = min(p1.longitude, p2.longitude);
    double maxLng = max(p1.longitude, p2.longitude);

    final bounds = gm.LatLngBounds(
      southwest: gm.LatLng(minLat, minLng),
      northeast: gm.LatLng(maxLat, maxLng),
    );

    _mapController!.animateCamera(
      gm.CameraUpdate.newLatLngBounds(bounds, 100.0),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _refreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ─── Get user location ─────────────────────────────────────
  Future<void> _initUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationPermissionDenied = true);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      if (!mounted) return;
      final latLng = gm.LatLng(pos.latitude, pos.longitude);
      setState(() => _userLatLng = latLng);

      // ย้ายกล้องไปตำแหน่งผู้ใช้ (ถ้ายังไม่มี emergency focus)
      if (_focusedEvent == null) {
        _animateCameraTo(latLng, zoom: 14.5);
      }
    } catch (e) {
      debugPrint('HomeMap: _initUserLocation error: $e');
    }
  }

  // ─── Poll active emergencies ───────────────────────────────
  Future<void> _pollEmergencyEvents() async {
    try {
      final events = await ServiceLocator.instance.videoRepository
          .getActiveEmergencyLocations();

      if (!mounted) return;

      // หา event ที่ใกล้ผู้ใช้ที่สุด
      final nearest = _findNearestEvent(events);

      setState(() {
        _activeEvents = events;
        _focusedEvent = nearest;
        _markers = _buildMarkers(events, nearest);
      });

      double parseDouble(dynamic value) {
        if (value == null) return 0.0;
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value) ?? 0.0;
        return 0.0;
      }

      // เลื่อนกล้องไปตามสถานการณ์
      if (nearest != null) {
        final lat = parseDouble(nearest['latitude']);
        final lng = parseDouble(nearest['longitude']);
        _animateCameraTo(gm.LatLng(lat, lng), zoom: 14.0);
        _showEventBanner(nearest);
      } else if (_userLatLng != null) {
        // ไม่มี event — กลับที่ตำแหน่งผู้ใช้
        _animateCameraTo(_userLatLng!, zoom: 14.5);
        _hideBanner();
      }
    } catch (e) {
      debugPrint('HomeMap: _pollEmergencyEvents error: $e');
    }
  }

  // ─── Find nearest event to user ────────────────────────────
  Map<String, dynamic>? _findNearestEvent(List<Map<String, dynamic>> events) {
    if (events.isEmpty) return null;
    if (_userLatLng == null) return events.first; // fallback ถ้ายังไม่รู้ตำแหน่งผู้ใช้

    Map<String, dynamic>? nearest;
    double minDist = double.infinity;

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    for (final e in events) {
      final lat = parseDouble(e['latitude']);
      final lng = parseDouble(e['longitude']);
      final dist = _haversineDistance(
        _userLatLng!.latitude, _userLatLng!.longitude, lat, lng);
      if (dist < minDist) {
        minDist = dist;
        nearest = e;
      }
    }
    return nearest;
  }

  /// Haversine distance in metres
  double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _deg2rad(double deg) => deg * pi / 180;

  // ─── Build markers ─────────────────────────────────────────
  Set<gm.Marker> _buildMarkers(
      List<Map<String, dynamic>> events, Map<String, dynamic>? focused) {
    final markers = <gm.Marker>{};

    // User location marker
    if (_userLatLng != null) {
      markers.add(gm.Marker(
        markerId: const gm.MarkerId('user_location'),
        position: _userLatLng!,
        icon: gm.BitmapDescriptor.defaultMarkerWithHue(
            gm.BitmapDescriptor.hueBlue),
        infoWindow: const gm.InfoWindow(title: 'ตำแหน่งของคุณ'),
        zIndex: 2,
      ));
    }

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    // Emergency event markers
    for (final e in events) {
      final videoId = e['videoId'] as String;
      final isFocused = focused != null && focused['videoId'] == videoId;
      markers.add(gm.Marker(
        markerId: gm.MarkerId(videoId),
        position: gm.LatLng(parseDouble(e['latitude']), parseDouble(e['longitude'])),
        icon: gm.BitmapDescriptor.defaultMarkerWithHue(
          isFocused
              ? gm.BitmapDescriptor.hueRed
              : gm.BitmapDescriptor.hueOrange,
        ),
        infoWindow: gm.InfoWindow(
          title: '🚨 ${e['categoryName'] ?? 'เหตุฉุกเฉิน'}',
          snippet: isFocused ? 'ใกล้คุณที่สุด' : 'แตะเพื่อดูรายละเอียด',
        ),
        zIndex: isFocused ? 1.5 : 1.0,
        onTap: () {
          _mapController?.showMarkerInfoWindow(gm.MarkerId(videoId));
        },
      ));
    }
    return markers;
  }

  // ─── Camera helpers ────────────────────────────────────────
  void _animateCameraTo(gm.LatLng target, {double zoom = 14.0}) {
    _mapController?.animateCamera(
      gm.CameraUpdate.newCameraPosition(
        gm.CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

  // ─── Banner ────────────────────────────────────────────────
  void _showEventBanner(Map<String, dynamic> event) {
    if (!mounted) return;
    setState(() {
      _bannerTitle = '🚨 ${event['categoryName'] ?? 'เหตุฉุกเฉิน'}';
      double parseDouble(dynamic value) {
        if (value == null) return 0.0;
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value) ?? 0.0;
        return 0.0;
      }

      final lat = parseDouble(event['latitude']).toStringAsFixed(5);
      final lng = parseDouble(event['longitude']).toStringAsFixed(5);
      _bannerSubtitle = 'ใกล้คุณที่สุด · $lat, $lng';
      _showBanner = true;
    });
  }

  void _hideBanner() {
    if (!mounted) return;
    setState(() => _showBanner = false);
  }

  // ─── MapCreated ────────────────────────────────────────────
  void _onMapCreated(gm.GoogleMapController controller) {
    _mapController = controller;
    setState(() => _isMapLoaded = true);

    // หลัง map สร้างเสร็จ ตั้งกล้องตามสถานะ
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_focusedEvent != null) {
        double parseDouble(dynamic value) {
          if (value == null) return 0.0;
          if (value is num) return value.toDouble();
          if (value is String) return double.tryParse(value) ?? 0.0;
          return 0.0;
        }

        _mapController?.animateCamera(
          gm.CameraUpdate.newLatLngZoom(
            gm.LatLng(parseDouble(_focusedEvent!['latitude']),
                parseDouble(_focusedEvent!['longitude'])),
            15.0,
          ),
        );
      } else if (_userLatLng != null) {
        _animateCameraTo(_userLatLng!, zoom: 14.5);
      }
    });
  }

  // ─── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Skeleton Loader
        if (!_isMapLoaded && !_mapHasError) _buildMapSkeleton(),

        // Error fallback
        if (_mapHasError) _buildMapError(),

        // Google Map
        if (!_mapHasError)
          AnimatedOpacity(
            opacity: _isMapLoaded ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 600),
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                child: gm.GoogleMap(
                  initialCameraPosition: gm.CameraPosition(
                    target: widget.initialLocation,
                    zoom: widget.initialZoom,
                  ),
                  onMapCreated: _onMapCreated,
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: !_locationPermissionDenied,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  compassEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
            ),
          ),

        // Overlay tint
        if (!_mapHasError)
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.05),
              ),
            ),
          ),

        // Event info banner (แสดงเมื่อมี emergency focus)
        if (_showBanner && _isMapLoaded)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildEventBanner(),
          ),
      ],
    );
  }

  // ─── Event Banner ──────────────────────────────────────────
  Widget _buildEventBanner() {
    return AnimatedOpacity(
      opacity: _showBanner ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade700.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_bannerTitle,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  Text(_bannerSubtitle,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            Text(
              '${_activeEvents.length} เหตุ',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Skeleton & Error ──────────────────────────────────────
  Widget _buildMapSkeleton() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin:
                  Alignment(-1.0 + 2 * _shimmerController.value, 0),
              end: Alignment(
                  -1.0 + 2 * _shimmerController.value + 1, 0),
              colors: [
                AppColors.background,
                AppColors.background.withValues(alpha: 0.5),
                AppColors.surface,
                AppColors.background.withValues(alpha: 0.5),
                AppColors.background,
              ],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
            ),
          ),
          child: Stack(
            children: [
              CustomPaint(
                size: Size.infinite,
                painter: MapSkeletonPainter(
                  color: AppColors.border.withValues(alpha: 0.3),
                ),
              ),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.shadow,
                          blurRadius: 8,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('กำลังโหลดแผนที่...',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMapError() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background,
            AppColors.background.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Icon(Icons.map_outlined,
                  size: 48, color: AppColors.textHint),
            ),
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ไม่สามารถโหลดแผนที่ได้',
                      style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ต',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _mapHasError = false;
                        _isMapLoaded = false;
                      });
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('ลองใหม่'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
