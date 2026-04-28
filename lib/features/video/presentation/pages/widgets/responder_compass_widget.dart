import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';

class ResponderCompassWidget extends StatelessWidget {
  final LatLng? userLocation;
  final LatLng? destinationLocation;
  final double? deviceHeading;

  const ResponderCompassWidget({
    super.key,
    required this.userLocation,
    required this.destinationLocation,
    required this.deviceHeading,
  });

  @override
  Widget build(BuildContext context) {
    if (userLocation == null || destinationLocation == null || deviceHeading == null) {
      return const SizedBox.shrink();
    }

    // 1. Calculate bearing from user to destination
    final double bearing = Geolocator.bearingBetween(
      userLocation!.latitude,
      userLocation!.longitude,
      destinationLocation!.latitude,
      destinationLocation!.longitude,
    );

    // 2. Adjust for device heading to get relative angle
    // Arrow angle = Bearing - Current Heading
    // If bearing is 90 (East) and heading is 90 (facing East), angle should be 0 (straight ahead).
    final double relativeAngle = (bearing - deviceHeading!) * (pi / 180);

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: relativeAngle,
              child: const Icon(
                Icons.navigation,
                color: Colors.redAccent,
                size: 32,
              ),
            ),
            const Text(
              'เหตุการณ์',
              style: TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
