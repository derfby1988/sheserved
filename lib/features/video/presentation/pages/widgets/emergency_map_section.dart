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

      ],
    );
  }
}
