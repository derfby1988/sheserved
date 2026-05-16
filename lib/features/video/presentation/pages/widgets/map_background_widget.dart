import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../models/video_models.dart';
import 'package:sheserved/services/platform_service.dart';

class MapBackgroundWidget extends StatelessWidget {
  final String? currentVideoId;
  final Video? currentVideo;
  final List<LatLng> routePoints;
  final LatLng? userLocation;
  final List<Map<String, dynamic>> responders;
  final int selectedTab;
  final Function(GoogleMapController) onMapCreated;
  final VoidCallback? onTap;
  final bool isUiVisible;
  final double? topPadding;
  final double? bottomPadding;

  const MapBackgroundWidget({
    super.key,
    required this.currentVideoId,
    required this.currentVideo,
    required this.routePoints,
    required this.userLocation,
    required this.responders,
    required this.selectedTab,
    required this.onMapCreated,
    this.onTap,
    this.isUiVisible = true,
    this.topPadding,
    this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    final bool showLiveMap = PlatformService.shouldShowLiveMap(pageName: 'emergency');
    
    if (!showLiveMap && kIsWeb) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            PlatformService.mapFallbackImageUrl,
            fit: BoxFit.cover,
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
            child: Container(
              color: Colors.black.withOpacity(0.4),
              child: Center(
                child: Text(
                  PlatformService.mapDisabledMessage,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      );
    }

    Set<Marker> mapMarkers = {};
    // ... rest of marker logic ...

    // 1. Incident Marker
    if (currentVideoId != null && routePoints.isNotEmpty) {
      mapMarkers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: routePoints.last,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'จุดเกิดเหตุ'),
        ),
      );
    }

    // 2. Responders Markers
    int responderIndex = 0;
    if (currentVideoId != null) {
      for (var r in responders) {
        if (r['currentLat'] != null && r['currentLng'] != null) {
          int mins = r['estimatedMinutes'] as int? ?? 0;
          double parseDouble(dynamic value) {
            if (value == null) return 0.0;
            if (value is num) return value.toDouble();
            if (value is String) return double.tryParse(value) ?? 0.0;
            return 0.0;
          }

          double distKm = parseDouble(r['distanceKm']);
          double speedKmh = parseDouble(r['currentSpeed']) * 3.6;

          String subtitle = mins <= 0
              ? 'ถึงที่เกิดเหตุแล้ว'
              : 'ห่าง ${distKm.toStringAsFixed(1)} กม. (อีก $mins นาที) | ${speedKmh.toStringAsFixed(0)} กม./ชม.';

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
            ),
          );
          responderIndex++;
        }
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        GoogleMap(
          key: ValueKey('${currentVideoId}_${currentVideo?.longitude}'),
          padding: EdgeInsets.only(
            top: isUiVisible ? (topPadding ?? MediaQuery.of(context).size.height * 0.2) : 40.0,
            bottom: isUiVisible ? (bottomPadding ?? 100.0) : 40.0,
          ),
          onMapCreated: (controller) {
            PlatformService.logMapLoad(pageName: 'emergency');
            onMapCreated(controller);
          },
          initialCameraPosition: CameraPosition(
            target: routePoints.isNotEmpty
                ? routePoints.last
                : (userLocation ?? const LatLng(13.7367, 100.5604)),
            zoom: 15.0,
          ),
          // แสดงแผนที่จริงเฉพาะเมื่อเงื่อนไข PlatformService อนุญาต (Web: check per page)
          // หากเป็น Web และตั้งค่าปิดไว้ จะแสดง Placeholder แทน (จัดการใน Layer บน)
          myLocationEnabled: PlatformService.shouldShowLiveMap(pageName: 'emergency') && !kIsWeb ? true : false,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          trafficEnabled: true,
          compassEnabled: false,
          mapToolbarEnabled: false,
          onTap: (_) {
            debugPrint("EMERGENCY_DEBUG: Google Map widget tapped");
            onTap?.call();
          },
          polylines: currentVideoId == null
              ? {}
              : {
                  // 1. เส้นทางรวมพิกัด (Official Gps Tracks)
                  Polyline(
                    polylineId: const PolylineId('emergency_route'),
                    points: routePoints,
                    color: const Color(0xFF7B2FF7),
                    width: 5,
                  ),
                  // 2. เส้นทางจาก Responder แต่ละคนไปยังจุดเกิดเหตุ (ถ้ามีพิกัด)
                  ...responders.where((r) => r['currentLat'] != null && r['currentLng'] != null && routePoints.isNotEmpty).map((r) {
                    return Polyline(
                      polylineId: PolylineId('responder_route_${r['id']}'),
                      points: [
                        LatLng(r['currentLat'], r['currentLng']),
                        routePoints.last, // ลากไปยังจุดล่าสุดของที่เกิดเหตุ
                      ],
                      color: Colors.blue.withOpacity(0.6),
                      width: 4,
                      patterns: [PatternItem.dash(20), PatternItem.gap(10)], // ทำเป็นเส้นประเพื่อให้ดูแตกต่าง
                    );
                  }),
                },
          markers: mapMarkers,
        ),
        if (selectedTab != 0)
          GestureDetector(
            onTap: onTap,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
              child: Container(
                color: Colors.black.withOpacity(0.15),
              ),
            ),
          ),
      ],
    );
  }
}
