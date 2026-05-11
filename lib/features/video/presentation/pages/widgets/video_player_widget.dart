import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import '../../../models/video_models.dart';
import 'video_skeleton_widget.dart';

class VideoPlayerWidget extends StatelessWidget {
  final ChewieController? chewieController;
  final String? currentVideoId;
  final Video? currentVideo;
  final bool canViewUnblurred;

  const VideoPlayerWidget({
    super.key,
    required this.chewieController,
    required this.currentVideoId,
    required this.currentVideo,
    this.canViewUnblurred = false,
  });

  @override
  Widget build(BuildContext context) {
    double aspectRatio = 16 / 9;
    if (chewieController != null &&
        chewieController!.videoPlayerController.value.isInitialized) {
      aspectRatio = chewieController!.videoPlayerController.value.aspectRatio;
    }

    return LayoutBuilder(
      builder: (context, outerConstraints) {
        // จำกัดความสูงของ video player ไม่ให้เกินพื้นที่แนวตั้งที่มีอยู่จริง
        // เพื่อป้องกัน Bottom Overflow ในแนวนอน
        final maxH = outerConstraints.maxHeight.isFinite 
            ? outerConstraints.maxHeight 
            : double.infinity;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.1), // โปร่งใสขึ้นอีก (10%)
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // คำนวณขนาดแบบ Dynamic ตามความกว้างจริงที่ Widget ได้รับ
                final width = constraints.maxWidth;
                final titleFontSize = (width * 0.045).clamp(10.0, 16.0);
                final statusFontSize = (width * 0.04).clamp(9.0, 14.0);
                final iconSize = (width * 0.15).clamp(24.0, 48.0);
                final spacing = (width * 0.03).clamp(4.0, 12.0);

                if (currentVideoId == null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min, // แก้ปัญหาล้นแนวตั้งเมื่ออยู่ใน FittedBox
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.dashboard_customize_rounded,
                              color: Colors.white70, size: iconSize),
                          SizedBox(height: spacing * 0.5),
                          Text(
                            'กรุณาเลือกเหตุการณ์จากแผงยอดนิยมด้านขวา\nเพื่อแสดงระบบศูนย์สั่งการและรับชมวิดีโอ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'SukhumvitSet',
                              color: Colors.white,
                              fontSize: titleFontSize,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                bool isImageUrl(String? url) {
                  if (url == null) return false;
                  final lower = url.toLowerCase();
                  return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp') || lower.endsWith('.gif');
                }

                String? imageToDisplay;
                if (currentVideo != null) {
                  if (isImageUrl(currentVideo!.localFilePath)) {
                    imageToDisplay = currentVideo!.localFilePath;
                  } else if (isImageUrl(currentVideo!.bunnyUrl)) {
                    imageToDisplay = currentVideo!.bunnyUrl;
                  } else if (currentVideo!.photoUrls.isNotEmpty && currentVideo!.bunnyUrl == null && currentVideo!.localFilePath == null) {
                    imageToDisplay = currentVideo!.photoUrls.first;
                  }
                }

                if (imageToDisplay != null) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      imageToDisplay.startsWith('http')
                          ? Image.network(imageToDisplay, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white, size: 50))
                          : Image.file(File(imageToDisplay), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white, size: 50)),
                      if (!canViewUnblurred)
                        Positioned(
                          top: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withOpacity(0.15)),
                              ),
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.face_retouching_off, color: Colors.white, size: 12),
                                    SizedBox(width: 4),
                                    Text('สิทธิ์ส่วนบุคคล (Blur)', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white70, fontSize: 8, fontFamily: 'SukhumvitSet', fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                }

                // Wrap with another Stack for the blur overlay
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    chewieController != null &&
                            chewieController!.videoPlayerController.value.isInitialized
                        ? Chewie(controller: chewieController!)
                        : Stack(
                            children: [
                              const VideoSkeletonWidget(), 
                              // ✅ ใช้ Center+LayoutBuilder เพื่อจำกัดความสูงและป้องกัน Bottom Overflow
                              Positioned.fill(
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min, // สำคัญ: ใช้ความสูงแค่พอดีกับเนื้อหา
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (currentVideo?.status == VideoStatus.error) ...[
                                          Icon(Icons.error_outline,
                                              color: Colors.red, size: iconSize),
                                          SizedBox(height: spacing),
                                          Text(
                                            'เกิดข้อผิดพลาดในการโหลดวิดีโอ',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontFamily: 'SukhumvitSet',
                                                color: Colors.white70,
                                                fontSize: statusFontSize),
                                          ),
                                        ] else if ((currentVideo?.status ==
                                                    VideoStatus.processing ||
                                                currentVideo?.status ==
                                                    VideoStatus.uploading) &&
                                            currentVideo?.localFilePath == null) ...[
                                          const VideoProcessingBadge(),
                                          SizedBox(height: spacing * 1.5),
                                          Text(
                                            '(${currentVideo?.progress ?? 0}%)',
                                            style: TextStyle(
                                              fontFamily: 'SukhumvitSet',
                                              color: Colors.white70,
                                              fontSize: statusFontSize,
                                            ),
                                          ),
                                        ] else ...[
                                          SizedBox(
                                            width: iconSize * 0.6,
                                            height: iconSize * 0.6,
                                            child: const CircularProgressIndicator(
                                                color: Colors.red, strokeWidth: 2),
                                          ),
                                          SizedBox(height: spacing * 1.5),
                                          Text(
                                            'กำลังเชื่อมต่อสัญญาณ...',
                                            style: TextStyle(
                                              fontFamily: 'SukhumvitSet',
                                              color: Colors.white70,
                                              fontSize: statusFontSize,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                    // ✅ ยกเลิกการเบลอทั้งวิดีโอ (Dynamic Blurring แบบเก่า)
                    // เปลี่ยนเป็นการบอกสถานะว่ามีการเบลอใบหน้าสงวนสิทธิ์ส่วนบุคคลแล้วที่ไฟล์วิดีโอ (Server-side)
                    if (!canViewUnblurred)
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3), // More transparent
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.15)),
                            ),
                            child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.face_retouching_off, color: Colors.white, size: 12), // ลดจาก 14 เหลือ 12
                                SizedBox(width: 4),
                                Text(
                                  'สิทธิ์ส่วนบุคคล (Blur)', // สั้นลง
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 8, // ลดจาก 9 เหลือ 8
                                    fontFamily: 'SukhumvitSet',
                                    fontWeight: FontWeight.bold,
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
              },
            ),
          ),
        ),
            ),
          ),
        );
      },
    );
  }
}
