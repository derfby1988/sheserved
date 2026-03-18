import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/websocket_service.dart';
import '../../../../services/auth_service.dart';
import '../../../../config/sync_config.dart';
import '../../../../config/app_config.dart';
import '../../../donation/models/donation_models.dart';
import '../../data/repositories/video_repository.dart';
import '../../models/video_models.dart';

class EmergencyReportingController {
  final BuildContext context;
  final Function(VoidCallback) setState;
  
  CameraController? cameraController;
  bool isRecording = false;
  Timer? gpsTimer;
  DateTime? recordingStartTime;
  List<Map<String, dynamic>> recordedGpsTracks = [];
  String? selectedEmergencyCategoryId;
  DonationCategory? selectedEmergencyCategory;
  List<DonationCategory> emergencyCategories = [];
  bool isLoadingCategories = false;

  Timer? countdownTimer;
  Timer? durationTimer;
  int prepCountdown = 0;
  int recordingTimeLeft = SyncConfig.maxEmergencyRecordingSeconds;
  
  bool isPhotoMode = false;
  final List<XFile> capturedPhotos = [];

  EmergencyReportingController({required this.context, required this.setState});

  Future<void> initCamera() async {
    if (cameraController != null) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      cameraController = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: true);
      await cameraController!.initialize();
      setState(() {});
    } catch (e) {
      debugPrint("Error initializing camera: $e");
    }
  }

  Future<void> loadEmergencyCategories() async {
    if (emergencyCategories.isNotEmpty || isLoadingCategories) return;
    setState(() => isLoadingCategories = true);
    try {
      final cats = await ServiceLocator.instance.donationRepository.getEmergencyCategories();
      setState(() => emergencyCategories = cats);
    } catch (e) {
      debugPrint('Error loading emergency categories: $e');
    } finally {
      setState(() => isLoadingCategories = false);
    }
  }

  void onLongPressDownVideo(Function() startRecording) async {
    if (isRecording || prepCountdown > 0) return;
    if (selectedEmergencyCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาเลือกประเภทเหตุฉุกเฉินก่อนเริ่มบันทึก'), backgroundColor: Colors.red));
      return;
    }
    setState(() => prepCountdown = 3);
    countdownTimer?.cancel();
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (prepCountdown > 1) {
          prepCountdown--;
        } else {
          prepCountdown = 0;
          timer.cancel();
          startRecording();
        }
      });
    });
  }

  Future<void> startEmergencyRecording(LatLng? userLocation) async {
    if (cameraController == null || !cameraController!.value.isInitialized) await initCamera();
    if (cameraController == null || isRecording) return;

    try {
      await cameraController!.startVideoRecording();
      recordingStartTime = DateTime.now();
      recordedGpsTracks = [];
      isRecording = true;
      recordingTimeLeft = SyncConfig.maxEmergencyRecordingSeconds;
      
      try {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        recordedGpsTracks.add({'latitude': pos.latitude, 'longitude': pos.longitude, 'timestampOffset': 0});
      } catch (_) {}
      
      durationTimer?.cancel();
      durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
         setState(() {
           if (recordingTimeLeft > 0) recordingTimeLeft--;
           else stopEmergencyRecording((file) => uploadIncident(file));
         });
      });

      gpsTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        try {
          Position pos = await Geolocator.getCurrentPosition();
          int offset = DateTime.now().difference(recordingStartTime!).inSeconds;
          recordedGpsTracks.add({'latitude': pos.latitude, 'longitude': pos.longitude, 'timestampOffset': offset});
        } catch (_) {}
      });
      setState(() {});
    } catch (e) {
      debugPrint("Error starting recording: $e");
    }
  }

  Future<void> stopEmergencyRecording(Function(File) onFileReady) async {
    durationTimer?.cancel();
    if (cameraController == null || !isRecording) return;
    try {
      XFile videoFile = await cameraController!.stopVideoRecording();
      if (gpsTimer != null) gpsTimer!.cancel();
      isRecording = false;
      setState(() {});
      onFileReady(File(videoFile.path));
    } catch (e) {
      debugPrint("Error stopping recording: $e");
    }
  }

  Future<void> takePhoto() async {
    if (cameraController == null || !cameraController!.value.isInitialized) await initCamera();
    if (cameraController == null || capturedPhotos.length >= 3) return;
    try {
      XFile photo = await cameraController!.takePicture();
      setState(() => capturedPhotos.add(photo));
      if (recordedGpsTracks.isEmpty) {
         try {
           Position pos = await Geolocator.getCurrentPosition();
           recordedGpsTracks.add({'latitude': pos.latitude, 'longitude': pos.longitude, 'timestampOffset': 0});
         } catch (_) {}
      }
    } catch (e) {
      debugPrint("Error taking photo: $e");
    }
  }

  Future<void> uploadIncident(File file) async {
     // ... (Upload logic)
  }

  void dispose() {
    countdownTimer?.cancel();
    durationTimer?.cancel();
    gpsTimer?.cancel();
    cameraController?.dispose();
  }
}
