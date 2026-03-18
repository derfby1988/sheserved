import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../../../donation/models/donation_models.dart';

class IncidentReportWidget extends StatelessWidget {
  final bool isRecording;
  final bool isLoadingCategories;
  final int prepCountdown;
  final int recordingTimeLeft;
  final bool isPhotoMode;
  final List<XFile> capturedPhotos;
  final String? selectedEmergencyCategoryId;
  final DonationCategory? selectedEmergencyCategory;
  final List<DonationCategory> emergencyCategories;
  final CameraController? cameraController;
  final VoidCallback onTakePhoto;
  final VoidCallback onSendPhotos;
  final VoidCallback onLongPressDownVideo;
  final VoidCallback onLongPressEndCancelVideo;
  final Function(DonationCategory) onCategorySelected;
  final Function(bool) onModeChanged;
  final VoidCallback onLoadCategories;
  final VoidCallback onYieldWay; // Added Yield Way callback
  final VoidCallback? onBackTap; // ✅ Added Back button callback
  final bool isThaiMhungMode;
  final int maxPhotos;

  const IncidentReportWidget({
    super.key,
    required this.isRecording,
    required this.isLoadingCategories,
    required this.prepCountdown,
    required this.recordingTimeLeft,
    required this.isPhotoMode,
    required this.capturedPhotos,
    required this.selectedEmergencyCategoryId,
    required this.selectedEmergencyCategory,
    required this.emergencyCategories,
    required this.cameraController,
    required this.onTakePhoto,
    required this.onSendPhotos,
    required this.onLongPressDownVideo,
    required this.onLongPressEndCancelVideo,
    required this.onCategorySelected,
    required this.onModeChanged,
    required this.onLoadCategories,
    required this.onYieldWay, // Required Yield Way callback
    this.onBackTap, // ✅ Back button
    this.isThaiMhungMode = false,
    this.maxPhotos = 3,
  });

  @override
  Widget build(BuildContext context) {
    final bool categorySelected = selectedEmergencyCategoryId != null;
    final bool canRecord = categorySelected && !isLoadingCategories;

    final screenSize = MediaQuery.of(context).size;
    final maxPreviewHeight = screenSize.height * 0.75;
    
    // คำนวณขนาด Preview แบบ Dynamic (ทางเลือกที่ 3)
    double previewWidth = screenSize.width - 32; // หัก padding ซ้ายขวาอย่างละ 16
    double previewHeight = 280; // ค่าเริ่มต้นก่อนที่กล้องจะ Initialize เสร็จ

    if (cameraController != null && cameraController!.value.isInitialized) {
      final double cameraAspectRatio = cameraController!.value.aspectRatio;
      
      // กรณีแนวตั้ง (Portrait): aspectRatio มักจะน้อยกว่า 1 (เช่น 0.56 สำหรับ 9:16)
      // กรณีแนวนอน (Landscape): aspectRatio มักจะมากกว่า 1 (เช่น 1.77 สำหรับ 16:9)
      // CameraPreview ของ Flutter มักจะคืนค่าเป็นกว้าง/สูงของเซนเซอร์
      double calculatedHeight = previewWidth / cameraAspectRatio;

      // ปรับปรุง: ตรวจสอบความสูงไม่ให้เกิน 75% ของหน้าจอ
      if (calculatedHeight > maxPreviewHeight) {
        previewHeight = maxPreviewHeight;
        previewWidth = previewHeight * cameraAspectRatio;
      } else {
        previewHeight = calculatedHeight;
      }
    }

    return GestureDetector(
      onTap: onBackTap,
      behavior: HitTestBehavior.translucent,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            if (onBackTap != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onTap: onBackTap,
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        isThaiMhungMode ? 'ยกเลิกโหมดไทยมุง' : 'ยกเลิกการแจ้งเหตุ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SukhumvitSet',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: previewHeight,
                width: previewWidth,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isRecording ? Colors.red : (categorySelected ? Colors.green : Colors.white24),
                    width: isRecording ? 2.5 : 1.5,
                  ),
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: cameraController != null && cameraController!.value.isInitialized
                          ? SizedBox.expand(child: CameraPreview(cameraController!))
                          : const Center(child: Icon(Icons.camera_alt, color: Colors.white38, size: 48)),
                    ),
                    if (!isRecording && prepCountdown == 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(14),
                              bottomRight: Radius.circular(14),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: categorySelected ? Colors.green : Colors.red.shade700,
                                    ),
                                    child: Center(
                                      child: categorySelected
                                          ? const Icon(Icons.check, color: Colors.white, size: 13)
                                          : const Text('!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    categorySelected
                                        ? 'ประเภท: ${selectedEmergencyCategory?.name ?? ""}'
                                        : 'เลือกประเภทเหตุฉุกเฉิน',
                                    style: TextStyle(
                                      color: categorySelected ? Colors.greenAccent : Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (isLoadingCategories)
                                const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              else if (emergencyCategories.isEmpty)
                                GestureDetector(
                                  onTap: onLoadCategories,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.refresh, color: Colors.white, size: 14),
                                        SizedBox(width: 6),
                                        Text('โหลดใหม่', style: TextStyle(color: Colors.white, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: emergencyCategories.map((cat) {
                                      final selected = selectedEmergencyCategoryId == cat.id;
                                      return GestureDetector(
                                        onTap: () => onCategorySelected(cat),
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 150),
                                          margin: const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: selected ? Colors.red : Colors.black54,
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: selected ? Colors.red.shade300 : Colors.white38,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Text(
                                            cat.name,
                                            style: TextStyle(
                                              color: selected ? Colors.white : Colors.white70,
                                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (!isRecording && prepCountdown == 0 && !isThaiMhungMode)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => onModeChanged(false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: !isPhotoMode ? Colors.red : Colors.transparent,
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: const Text('วิดีโอ', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => onModeChanged(true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isPhotoMode ? Colors.red : Colors.transparent,
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: const Text('ภาพถ่าย', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (prepCountdown > 0)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$prepCountdown',
                                style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const Text('กำลังเริ่มบันทึก...', style: TextStyle(color: Colors.white70, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    if (isRecording)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.red, width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(recordingTimeLeft ~/ 60).toString().padLeft(2, '0')}:${(recordingTimeLeft % 60).toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (isThaiMhungMode) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'โหมดไทยมุง: ถ่ายภาพได้สูงสุด $maxPhotos ภาพ (${capturedPhotos.length}/$maxPhotos)',
                        style: const TextStyle(
                          fontFamily: 'SukhumvitSet',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // ✅ Yield Way Button (ตามแผน §4 Yield Way Feedback System)
              GestureDetector(
                onTap: onYieldWay,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF007AFF), Color(0xFF00C7BE)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.directions_car, color: Colors.white, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'ช่วยกดปุ่ม "ให้ทาง" (Yield Way)',
                        style: TextStyle(
                          fontFamily: 'SukhumvitSet',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (isPhotoMode && capturedPhotos.isNotEmpty) ...[
              SizedBox(
                height: 64,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: capturedPhotos.length,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: FileImage(File(capturedPhotos[index].path)),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: GestureDetector(
                          onTap: () => (context as dynamic).setState(() => capturedPhotos.removeAt(index)), // This might need a better way if we want to follow strict encapsulation, but for now it's okay for an extraction
                          child: const Icon(Icons.cancel, color: Colors.white, size: 20),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
            Opacity(
              opacity: canRecord ? 1.0 : 0.45,
              child: isPhotoMode
                  ? Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: GestureDetector(
                            onTap: (canRecord && capturedPhotos.length < maxPhotos) ? onTakePhoto : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.red, width: 2),
                              ),
                              child: const Center(child: Icon(Icons.camera_alt, color: Colors.red, size: 30)),
                            ),
                          ),
                        ),
                        if (capturedPhotos.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: GestureDetector(
                              onTap: onSendPhotos,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFFFF3B30), Color(0xFFFF2D55)]),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Center(
                                  child: Text(
                                    'ส่งรูปภาพ',
                                    style: TextStyle(fontFamily: 'SukhumvitSet', fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    )
                  : isThaiMhungMode 
                    ? const SizedBox.shrink() // No video button in Thai Mhung mode
                    : GestureDetector(
                      onLongPressDown: canRecord ? (_) => onLongPressDownVideo() : null,
                      onLongPressEnd: (_) => onLongPressEndCancelVideo(),
                      onLongPressCancel: () => onLongPressEndCancelVideo(),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isRecording
                                ? [Colors.black87, Colors.black]
                                : canRecord
                                    ? [const Color(0xFFFF3B30), const Color(0xFFFF2D55)]
                                    : [Colors.grey.shade700, Colors.grey.shade800],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: (isRecording ? Colors.black : canRecord ? Colors.red : Colors.grey)
                                  .withValues(alpha: 0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isRecording ? Icons.stop_circle : Icons.videocam,
                              color: Colors.white,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              isRecording
                                  ? 'ปล่อยเพื่อหยุดและส่ง'
                                  : canRecord
                                      ? 'กดค้างเพื่อเริ่มบันทึก'
                                      : 'เลือกประเภทเหตุก่อน',
                              style: const TextStyle(
                                fontFamily: 'SukhumvitSet',
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 100), // เพิ่มพื้นที่ด้านล่างเพื่อให้แตะพื้นที่แผนที่ได้กว้างขึ้น
          ],
        ),
      ),
    );

  }
}
