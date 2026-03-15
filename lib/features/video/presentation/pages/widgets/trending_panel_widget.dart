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
                          
                          // จัดรูปแบบเวลา วัน/เดือน/ปี เวลา -> วันนี้/เมื่อวาน หรือ แปลง พ.ศ. และเดือนไทย
                          final now = DateTime.now();
                          final createdAt = video.createdAt;
                          final isToday = now.year == createdAt.year && now.month == createdAt.month && now.day == createdAt.day;
                          final yesterday = now.subtract(const Duration(days: 1));
                          final isYesterday = yesterday.year == createdAt.year && yesterday.month == createdAt.month && yesterday.day == createdAt.day;
                          
                          final timeStr = DateFormat('HH.mm').format(createdAt) + ' น.';
                          String dateStr = '';
                          
                          if (isToday) {
                            dateStr = timeStr;
                          } else if (isYesterday) {
                            dateStr = 'เมื่อวาน $timeStr';
                          } else {
                            final thaiMonths = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
                            final thaiYearShort = ((createdAt.year + 543) % 100).toString().padLeft(2, '0');
                            dateStr = '${createdAt.day} ${thaiMonths[createdAt.month - 1]} $thaiYearShort $timeStr';
                          }
                          
                          // ดึงชื่อประเภทเหตุการณ์จากตาราง donation_categories (มากับ Join)
                          String displayTitle = video.categoryName ?? '';
                          if (displayTitle.isEmpty || displayTitle == 'null') {
                            if (video.title.startsWith('Emergency Incident')) {
                              displayTitle = 'เหตุฉุกเฉิน';
                            } else {
                              displayTitle = video.title;
                            }
                            
                            if (displayTitle.isEmpty) {
                              displayTitle = video.description ?? 'เหตุฉุกเฉิน';
                            }
                            // เผื่อมีวันที่แบบเก่าติดมา
                            displayTitle = displayTitle.replaceAll(RegExp(r'\s+\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}$'), '');
                          }
                          
                          // ตัดความยาวไม่เกิน 30 ตัวอักษร เพื่อให้มั่นใจว่าเห็นแค่ชื่อเหตุ
                          if (displayTitle.length > 30) {
                            displayTitle = '${displayTitle.substring(0, 30)}...';
                          }

                          return GestureDetector(
                            onTap: () {
                              if (video.id != currentVideoId) {
                                onSwitchVideo(video.id);
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              width: double.infinity,
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
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                child: FittedBox(
                                  alignment: Alignment.centerLeft,
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min, // ให้สูงพอดีกับเนื้อหา
                                    children: [
                                      Text(
                                        displayTitle,
                                        maxLines: 1,
                                        style: const TextStyle(
                                          fontFamily: 'SukhumvitSet',
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        dateStr,
                                        maxLines: 1,
                                        style: const TextStyle(
                                          fontFamily: 'SukhumvitSet',
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
