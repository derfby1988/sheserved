import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/video_models.dart';

class TrendingPanelWidget extends StatelessWidget {
  final List<Video> trendingVideos;
  final bool isLoadingTrending;
  final String? currentVideoId;
  final Function(String) onSwitchVideo;

  const TrendingPanelWidget({
    super.key,
    required this.trendingVideos,
    required this.isLoadingTrending,
    required this.currentVideoId,
    required this.onSwitchVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'ยอดนิยม',
              style: TextStyle(
                fontFamily: 'SukhumvitSet',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: isLoadingTrending
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B35)))
                : trendingVideos.isEmpty
                    ? const Center(
                        child: Text(
                          'ไม่มีข้อมูล',
                          style: TextStyle(fontFamily: 'SukhumvitSet', color: Colors.black54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: trendingVideos.length,
                        itemBuilder: (context, index) {
                          final video = trendingVideos[index];
                          
                          // จัดรูปแบบเวลา วัน/เดือน/ปี เวลา
                          final timeFormat = DateFormat('dd/MM/yyyy HH:mm').format(video.createdAt);
                          
                          // สร้างชื่อวิดีโอ (ถ้ามี category ใน title ก็ใช้ ถ้าไม่มีก็เติม)
                          // รูปแบบ: ประเภทเหตุ - วันเวลา - (ตำแหน่งถ้ามี)
                          String displayTitle = video.title;
                          if (!displayTitle.contains(timeFormat)) {
                             displayTitle = '${video.description ?? 'เหตุฉุกเฉิน'} $timeFormat';
                          }

                          return GestureDetector(
                            onTap: () {
                              if (video.id != currentVideoId) {
                                onSwitchVideo(video.id);
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              height: 100, // เพิ่มความสูงเพื่อใส่ชื่อ
                              decoration: BoxDecoration(
                                color: Colors.blueGrey[900],
                                borderRadius: BorderRadius.circular(12),
                                image: video.thumbnailUrl != null
                                    ? DecorationImage(
                                        image: NetworkImage(video.thumbnailUrl!),
                                        fit: BoxFit.cover,
                                        colorFilter: ColorFilter.mode(
                                            Colors.black.withValues(alpha: 0.4), BlendMode.darken), // มืดลงหน่อยให้อ่านง่าย
                                      )
                                    : null,
                              ),
                              child: Stack(
                                children: [
                                  // Rank Badge
                                  Positioned(
                                    top: 4, left: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text('#${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    )
                                  ),
                                  // Title text at bottom
                                  Positioned(
                                    bottom: 6, left: 6, right: 6,
                                    child: Text(
                                      displayTitle,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'SukhumvitSet',
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
