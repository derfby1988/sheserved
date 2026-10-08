import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/incident_report_widget.dart';

IncidentReportWidget _buildIncidentReport({
  required List<XFile> capturedPhotos,
  required bool isThaiMhungMode,
  required VoidCallback onBackTap,
}) {
  return IncidentReportWidget(
    isRecording: false,
    isLoadingCategories: false,
    prepCountdown: 0,
    recordingTimeLeft: 0,
    isPhotoMode: true,
    capturedPhotos: capturedPhotos,
    selectedEmergencyCategoryId: null,
    selectedEmergencyCategory: null,
    emergencyCategories: const [],
    cameraController: null,
    onTakePhoto: () {},
    onSendPhotos: () {},
    onLongPressDownVideo: () {},
    onLongPressEndCancelVideo: () {},
    onCategorySelected: (_) {},
    onModeChanged: (_) {},
    onLoadCategories: () {},
    onYieldWay: () {},
    yieldWayCount: '',
    onBackTap: onBackTap,
    isThaiMhungMode: isThaiMhungMode,
  );
}

void main() {
  final photoPath = File(
    'test/shared/map/goldens/osm_map_markers_route.png',
  ).absolute.path;

  group('IncidentReportWidget pending photos', () {
    testWidgets('canceling Thai-mung mode clears all captured photos', (
      tester,
    ) async {
      final photos = [XFile(photoPath), XFile(photoPath)];
      var backTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _buildIncidentReport(
              capturedPhotos: photos,
              isThaiMhungMode: true,
              onBackTap: () => backTapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('ยกเลิกโหมดไทยมุง'));
      await tester.pump();

      expect(backTapped, isTrue);
      expect(photos, isEmpty);
    });

    testWidgets('canceling another report preserves captured photos', (
      tester,
    ) async {
      final photos = [XFile(photoPath)];
      var backTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _buildIncidentReport(
              capturedPhotos: photos,
              isThaiMhungMode: false,
              onBackTap: () => backTapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('ยกเลิกการแจ้งเหตุ'));
      await tester.pump();

      expect(backTapped, isTrue);
      expect(photos, hasLength(1));
    });
  });
}
