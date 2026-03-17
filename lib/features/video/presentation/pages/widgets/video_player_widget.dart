import 'dart:ui';
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

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1), // โปร่งใสขึ้นอีก (10%)
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.dashboard_customize_rounded,
                            color: Colors.white70, size: iconSize),
                        SizedBox(height: spacing),
                        Text(
                          'กรุณาเลือกเหตุการณ์จากแผงยอดนิยมด้านขวา\nเพื่อแสดงระบบศูนย์สั่งการและรับชมวิดีโอ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'SukhumvitSet',
                            color: Colors.white,
                            fontSize: titleFontSize,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
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
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (currentVideo?.status == VideoStatus.error) ...[
                                      Icon(Icons.error_outline,
                                          color: Colors.red, size: iconSize),
                                      SizedBox(height: spacing),
                                      Text('เกิดข้อผิดพลาดในการโหลดวิดีโอ',
                                          style: TextStyle(
                                              fontFamily: 'SukhumvitSet',
                                              color: Colors.white70,
                                              fontSize: statusFontSize)),
                                    ] else if ((currentVideo?.status ==
                                                VideoStatus.processing ||
                                            currentVideo?.status ==
                                                VideoStatus.uploading) &&
                                        currentVideo?.localFilePath == null) ...[
                                      const Center(child: VideoProcessingBadge()), 
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
                                      Center(
                                        child: Column(
                                          children: [
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
                                        ),
                                      ),
                                    ],
                                  ],
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
                              color: Colors.black.withValues(alpha: 0.3), // More transparent
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.face_retouching_off, color: Colors.white, size: 14),
                                SizedBox(width: 6),
                                Text(
                                  'สิทธิ์ภาพบุคคล (Face Blur)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9, // Slightly smaller default
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
    );
  }
}
