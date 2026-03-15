import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'websocket_service.dart';

/// Location Tracking Service
/// Handles GPS location tracking and sends to WebSocket server
class LocationTrackingService {
  static LocationTrackingService? _instance;
  final WebSocketService _webSocketService;
  StreamSubscription<Position>? _positionSubscription;
  bool _isTracking = false;
  String? _currentUserId;
  
  // Location update settings
  Duration _updateInterval = const Duration(seconds: 10); // Update every 10 seconds
  double _distanceFilter = 10.0; // Update if moved 10 meters
  
  LocationTrackingService._(this._webSocketService);
  
  /// Singleton instance
  factory LocationTrackingService({WebSocketService? webSocketService}) {
    _instance ??= LocationTrackingService._(
      webSocketService ?? WebSocketService(),
    );
    return _instance!;
  }
  
  /// Check and request location permissions
  Future<bool> checkPermissions({bool requestAlways = false}) async {
    // 1. Initial status check
    PermissionStatus status = await Permission.location.status;
    
    // 2. Request if denied (first time or reset)
    if (status.isDenied) {
      status = await Permission.location.request();
    }
    
    // 3. Handle Always requirement
    if (requestAlways) {
      PermissionStatus alwaysStatus = await Permission.locationAlways.status;
      if (alwaysStatus.isDenied) {
        alwaysStatus = await Permission.locationAlways.request();
      }
      return alwaysStatus.isGranted || alwaysStatus.isLimited;
    }
    
    // 4. Final check for foreground/general permission
    return status.isGranted || status.isLimited;
  }
  
  /// Specifically request background location permission (Android 11+)
  Future<bool> requestBackgroundPermission() async {
    // First, ensure foreground is granted
    final foregroundGranted = await checkPermissions(requestAlways: false);
    if (!foregroundGranted) return false;
    
    // Then request background
    final status = await Permission.locationAlways.request();
    return status.isGranted;
  }

  /// Check if background location permission is currently granted
  Future<bool> isBackgroundPermissionGranted() async {
    return await checkPermissions(requestAlways: true);
  }
  
  Future<bool> isLocationEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Request to ignore battery optimizations (Android only)
  /// This helps prevent the OS from killing the foreground service in Doze mode
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        debugPrint('LocationTrackingService: Requesting battery optimization exclusion');
        await Permission.ignoreBatteryOptimizations.request();
      }
    }
  }
  
  /// Start tracking location
  Future<void> startTracking({
    required String userId,
    Duration? updateInterval,
    double? distanceFilter,
  }) async {
    if (_isTracking) {
      debugPrint('Location tracking already started');
      return;
    }
    
    // Check permissions
    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      throw Exception('Location permission not granted');
    }
    
    // Check if location services are enabled
    final isEnabled = await isLocationEnabled();
    if (!isEnabled) {
      throw Exception('Location services are disabled');
    }

    // Request battery optimization exclusion for background reliability
    await requestIgnoreBatteryOptimizations();
    
    _currentUserId = userId;
    if (updateInterval != null) _updateInterval = updateInterval;
    if (distanceFilter != null) _distanceFilter = distanceFilter;
    
    // Get location accuracy settings
    // For Android, we use foreground service settings to prevent the app from being killed
    late final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilter.toInt(),
        forceLocationManager: true,
        intervalDuration: _updateInterval,
        // Set foreground notification details
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "กำลังติดตามระดับพิกัดเพื่อรับแจ้งเหตุช่วยเหลือ",
          notificationTitle: "Sheserved: กำลังออนไลน์",
          enableWakeLock: true,
        ),
      );
    } else {
      locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilter.toInt(),
      );
    }
    
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        _onLocationUpdate(position);
      },
      onError: (error) {
        debugPrint('Location tracking error: $error');
      },
    );
    
    _isTracking = true;
    debugPrint('Location tracking started for user: $userId');
  }
  
  /// Stop tracking location
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
    _currentUserId = null;
    debugPrint('Location tracking stopped');
  }
  
  /// Handle location update
  void _onLocationUpdate(Position position) {
    if (_currentUserId == null) return;
    
    _webSocketService.sendLocation(
      userId: _currentUserId!,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: position.heading,
    );
  }
  
  /// Get current location (one-time)
  Future<Position?> getCurrentLocation() async {
    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      throw Exception('Location permission not granted');
    }
    
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      debugPrint('Error getting current location: $e');
      return null;
    }
  }
  
  /// Update tracking settings
  void updateSettings({
    Duration? updateInterval,
    double? distanceFilter,
  }) {
    if (updateInterval != null) _updateInterval = updateInterval;
    if (distanceFilter != null) _distanceFilter = distanceFilter;
    
    // Restart tracking if already tracking
    if (_isTracking && _currentUserId != null) {
      stopTracking();
      startTracking(userId: _currentUserId!);
    }
  }
  
  bool get isTracking => _isTracking;
  String? get currentUserId => _currentUserId;
}
