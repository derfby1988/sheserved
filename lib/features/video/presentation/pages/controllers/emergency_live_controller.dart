import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:camera/camera.dart';
import '../../../../services/websocket_service.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../data/repositories/video_repository.dart';
import '../../../donation/models/donation_models.dart';
import '../../models/video_models.dart';
import '../../../../config/app_config.dart';
import '../../../../config/sync_config.dart';

class EmergencyLiveController extends ChangeNotifier {
  // --- Core State ---
  int selectedTab = 0;
  int viewerCount = 0;
  int likeCount = 0;
  double donationTotal = 0.0;
  LatLng? userLocation;
  bool isConnected = true;
  String? currentVideoId;
  Video? currentVideo;
  GoogleMapController? mapController;
  
  // --- Subscriptions ---
  StreamSubscription? connectionSub;
  StreamSubscription? interactionSub;
  StreamSubscription? myLocationStreamSub;
  StreamSubscription? emergencySub;
  StreamSubscription? compassSub;
  
  // --- UI & Data ---
  double? deviceHeading;
  List<Video> trendingVideos = [];
  bool isLoadingTrending = true;
  String? highlightVideoId;
  String? currentResponseId;
  List<Map<String, dynamic>> responders = [];
  List<LatLng> routePoints = [];
  bool isUiVisible = true;
  bool canViewUnblurred = false;
  bool isThaiMhungReporting = false;

  // --- Reporting State ---
  CameraController? cameraController;
  bool isRecording = false;
  int prepCountdown = 0;
  int recordingTimeLeft = SyncConfig.maxEmergencyRecordingSeconds;
  bool isPhotoMode = false;
  List<XFile> capturedPhotos = [];
  String? selectedEmergencyCategoryId;
  DonationCategory? selectedEmergencyCategory;
  List<DonationCategory> emergencyCategories = [];
  bool isLoadingCategories = false;

  final BuildContext context;

  EmergencyLiveController(this.context);

  void setTab(int index) {
    selectedTab = index;
    isThaiMhungReporting = false;
    notifyListeners();
  }

  void toggleUiVisibility() {
    isUiVisible = !isUiVisible;
    notifyListeners();
  }

  void setThaiMhungReporting(bool value) {
    isThaiMhungReporting = value;
    if (value) selectedTab = 0;
    notifyListeners();
  }

  // --- Logic Methods (To be filled from Page) ---
  
  Future<void> loadInitialData() async {
    // Ported from EmergencyLivePage._loadInitialData
    notifyListeners();
  }

  void disposeControllers() {
    connectionSub?.cancel();
    interactionSub?.cancel();
    myLocationStreamSub?.cancel();
    emergencySub?.cancel();
    compassSub?.cancel();
    cameraController?.dispose();
    super.dispose();
  }
}
