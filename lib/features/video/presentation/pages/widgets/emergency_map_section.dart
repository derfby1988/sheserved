import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_background_widget.dart';
import 'responder_compass_widget.dart';
import 'floating_back_button.dart';
import '../../../models/video_models.dart';
import '../../../../donation/models/donation_models.dart';

class EmergencyMapSection extends StatelessWidget {
  final String? currentVideoId;
  final Video? currentVideo;
  final List<LatLng> routePoints;
  final LatLng? userLocation;
  final List<Map<String, dynamic>> responders;
  final int selectedTab;
  final Function(GoogleMapController) onMapCreated;
  final bool isUiVisible;
  final double topPadding;
  final VoidCallback onMapTap;
  final String? currentResponseId;
  final double? deviceHeading;
  final bool isThaiMhungReporting;
  final VoidCallback onBackTap;
  final bool isYieldPulsing;
  final bool isEmergencyHealthDataAvailable;
  final VoidCallback? onShowHealthDataTap;
  final String? emergencyHealthStatus;

  const EmergencyMapSection({
    super.key,
    required this.currentVideoId,
    required this.currentVideo,
    required this.routePoints,
    required this.userLocation,
    required this.responders,
    required this.selectedTab,
    required this.onMapCreated,
    required this.isUiVisible,
    required this.topPadding,
    required this.onMapTap,
    required this.currentResponseId,
    required this.deviceHeading,
    required this.isThaiMhungReporting,
    required this.onBackTap,
    this.isYieldPulsing = false,
    this.isEmergencyHealthDataAvailable = false,
    this.onShowHealthDataTap,
    this.emergencyHealthStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Layer 1: Map
        MapBackgroundWidget(
          currentVideoId: currentVideoId,
          currentVideo: currentVideo,
          routePoints: routePoints,
          userLocation: userLocation,
          responders: responders,
          selectedTab: selectedTab,
          onMapCreated: onMapCreated,
          isUiVisible: isUiVisible,
          topPadding: topPadding,
          onTap: onMapTap,
        ),

        // Layer 1.1: Compass
        if (currentResponseId != null && userLocation != null && (routePoints.isNotEmpty || (currentVideo?.latitude != null && currentVideo?.longitude != null)))
          Positioned(
            top: 100,
            right: 16,
            child: IgnorePointer(
              ignoring: !isUiVisible,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: isUiVisible ? 1.0 : 0.0,
                child: ResponderCompassWidget(
                  userLocation: userLocation,
                  destinationLocation: routePoints.isNotEmpty 
                    ? routePoints.last 
                    : LatLng(currentVideo!.latitude, currentVideo!.longitude),
                  deviceHeading: deviceHeading,
                ),
              ),
            ),
          ),

        // Layer 1.2: Yield Way Pulse Effect
        IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 500),
            opacity: isYieldPulsing ? 1.0 : 0.0,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.redAccent.withOpacity(0.6),
                  width: 8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.redAccent.withOpacity(0.3),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
            ),
          ),
        ),

        // ✅ [Phase 3b] Floating health data badge on map
        if (isEmergencyHealthDataAvailable && onShowHealthDataTap != null)
          Positioned(
            left: 16,
            bottom: MediaQuery.of(context).padding.bottom + 120,
            child: IgnorePointer(
              ignoring: !isUiVisible,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: isUiVisible ? 1.0 : 0.0,
                child: GestureDetector(
                  onTap: onShowHealthDataTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade700,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.medical_services, color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'ข้อมูลสุขภาพ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            fontFamily: 'SukhumvitSet',
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        // ✅ [Phase 3b] Privacy mask indicator for locked health data
        if (!isEmergencyHealthDataAvailable && currentResponseId != null && emergencyHealthStatus == 'counting')
          Positioned(
            left: 16,
            bottom: MediaQuery.of(context).padding.bottom + 120,
            child: IgnorePointer(
              ignoring: !isUiVisible,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: isUiVisible ? 1.0 : 0.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_clock, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'ข้อมูลสุขภาพเร็วๆ นี้',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          fontFamily: 'SukhumvitSet',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ✅ [Phase 3b] Cancelled / revoked indicator
        if (!isEmergencyHealthDataAvailable && currentResponseId != null && emergencyHealthStatus == 'cancelled')
          Positioned(
            left: 16,
            bottom: MediaQuery.of(context).padding.bottom + 120,
            child: IgnorePointer(
              ignoring: !isUiVisible,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: isUiVisible ? 1.0 : 0.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade700,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'ข้อมูลสุขภาพถูกยกเลิก',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          fontFamily: 'SukhumvitSet',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

      ],
    );
  }
}
