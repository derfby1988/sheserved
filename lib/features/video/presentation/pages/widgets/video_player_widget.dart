import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import '../../../models/video_models.dart';

class VideoPlayerWidget extends StatelessWidget {
  final ChewieController? chewieController;
  final String? currentVideoId;
  final Video? currentVideo;

  const VideoPlayerWidget({
    super.key,
    required this.chewieController,
    required this.currentVideoId,
    required this.currentVideo,
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
        borderRadius: BorderRadius.circular(4),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1), // โปร่งใสขึ้นอีก (10%)
              borderRadius: BorderRadius.circular(4),
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

                return chewieController != null &&
                        chewieController!.videoPlayerController.value.isInitialized
                    ? Chewie(controller: chewieController!)
                    : Padding(
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
                            ] else if (currentVideo?.status ==
                                    VideoStatus.processing ||
                                currentVideo?.status == VideoStatus.uploading) ...[
                              SizedBox(
                                width: iconSize * 0.6,
                                height: iconSize * 0.6,
                                child: const CircularProgressIndicator(
                                    color: Colors.orange, strokeWidth: 2),
                              ),
                              SizedBox(height: spacing * 1.5),
                              Text(
                                'กำลังประมวลผล... (${currentVideo?.progress ?? 0}%)',
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
                      );
              },
            ),
          ),
        ),
      ),
    );
  }
}
