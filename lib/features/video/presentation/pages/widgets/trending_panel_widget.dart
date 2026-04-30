import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sheserved/config/app_config.dart';
import '../../../models/video_models.dart';
import 'video_skeleton_widget.dart';

class TrendingPanelWidget extends StatefulWidget {
  final List<Video> trendingVideos;
  final bool isLoadingTrending;
  final String? currentVideoId;
  final String? highlightVideoId; // ID ของวิดีโอที่เป็นเหตุฉุกเฉินใหม่
  final Function(String) onSwitchVideo;

  const TrendingPanelWidget({
    super.key,
    required this.trendingVideos,
    required this.isLoadingTrending,
    required this.currentVideoId,
    required this.onSwitchVideo,
    this.highlightVideoId,
  });

  @override
  State<TrendingPanelWidget> createState() => _TrendingPanelWidgetState();
}

class _TrendingPanelWidgetState extends State<TrendingPanelWidget> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TrendingPanelWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ถ้ามี highlight ใหม่เข้ามา ให้เลื่อนขึ้นบนสุด
    if (widget.highlightVideoId != null && 
        widget.highlightVideoId != oldWidget.highlightVideoId) {
      _scrollToTop();
    }
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutQuart,
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 1), // ลดจาก 3 เหลือ 1
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // ให้ Column หดความสูงเท่าที่จำเป็น
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
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Flexible( // ใช้ Flexible แทน Expanded เพื่อให้หดตามเนื้อหาได้หากมีน้อย
            child: widget.isLoadingTrending
                ? _buildSkeletonList()
                : widget.trendingVideos.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child: Text(
                            'ไม่มีข้อมูล',
                            style: TextStyle(fontFamily: 'SukhumvitSet', color: Colors.black54),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        shrinkWrap: true, // ยืดหดความสูงตามจำนวนการ์ด
                        padding: const EdgeInsets.symmetric(horizontal: 4), // ลดจาก 8 เหลือ 4
                        itemCount: widget.trendingVideos.length,
                        itemBuilder: (context, index) {
                          final video = widget.trendingVideos[index];
                          final bool isNewEmergency = video.id == widget.highlightVideoId;
                          
                          // จัดรูปแบบเวลา วัน/เดือน/ปี เวลา -> วันนี้/เมื่อวาน หรือ แปลง พ.ศ. และเดือนไทย
                          final now = AppConfig.thailandNow;
                          final createdAt = AppConfig.toThailand(video.createdAt);
                          final isToday = now.year == createdAt.year && now.month == createdAt.month && now.day == createdAt.day;
                          final yesterday = now.subtract(const Duration(days: 1));
                          final isYesterday = yesterday.year == createdAt.year && yesterday.month == createdAt.month && yesterday.day == createdAt.day;
                          
                          final timeStr = DateFormat('HH.mm').format(createdAt) + ' น.';
                          String dateStr = '';
                          
                          final diff = now.difference(createdAt);
                          
                          if (diff.inMinutes < 60 && diff.inMinutes >= 0) {
                            if (diff.inMinutes == 0) {
                              dateStr = 'เมื่อครู่นี้';
                            } else {
                              dateStr = '${diff.inMinutes} นาทีที่แล้ว';
                            }
                          } else if (isToday) {
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
                          
                          if (isNewEmergency) {
                            displayTitle = '🚨 ใหม่: $displayTitle';
                          }

                          final bool hasLocalPreview = video.localFilePath != null;
                          final bool isStillProcessing = video.status == VideoStatus.processing;
                          final bool isSelected = video.id == widget.currentVideoId; // ลำดับที่ผู้ใช้กำลังดูอยู่

                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              debugPrint('[TrendingPanel] Card tapped! video.id: ${video.id}, currentVideoId: ${widget.currentVideoId}');
                              if (video.id != widget.currentVideoId) {
                                widget.onSwitchVideo(video.id);
                              } else {
                                debugPrint('[TrendingPanel] Already on this video.');
                              }
                            },
                            child: AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCirc,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: isNewEmergency 
                                        ? Colors.red.withOpacity(0.9 + (0.1 * _pulseController.value))
                                        : isSelected
                                            ? Colors.amber[900]?.withOpacity(0.85) // สีส้มทองแสดงถึงการโฟกัส
                                            : Colors.blueGrey[900],
                                    borderRadius: BorderRadius.circular(12),
                                    border: isNewEmergency
                                        ? Border.all(color: Colors.white, width: 2)
                                        : isSelected
                                            ? Border.all(color: Colors.amberAccent, width: 2.5) // กรอบสีเด่น
                                            : Border.all(color: Colors.transparent, width: 2.5),
                                    boxShadow: isNewEmergency
                                        ? [
                                            BoxShadow(
                                              color: Colors.red.withOpacity(0.4),
                                              blurRadius: 12 * _pulseController.value,
                                              spreadRadius: 2 * _pulseController.value,
                                            )
                                          ]
                                        : isSelected
                                            ? [
                                                BoxShadow( // แสงเรืองรองใต้ปุ่ม
                                                  color: Colors.orangeAccent.withOpacity(0.5),
                                                  blurRadius: 8,
                                                  spreadRadius: 2,
                                                )
                                              ]
                                            : null,
                                    image: video.thumbnailUrl != null
                                        ? DecorationImage(
                                            image: NetworkImage(video.thumbnailUrl!),
                                            fit: BoxFit.cover,
                                            colorFilter: ColorFilter.mode(
                                                (isNewEmergency 
                                                    ? Colors.red 
                                                    : isSelected 
                                                        ? Colors.orange // ย้อมสีจางๆ ให้รู้ว่าเลือกอยู่
                                                        : Colors.black)
                                                    .withOpacity(isSelected ? 0.3 : 0.4),
                                                BlendMode.darken),
                                          )
                                        : null,
                                    ), // closes BoxDecoration
                                    child: child,
                                ); // closes return AnimatedContainer
                              },
                              child: AnimatedPadding(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCirc,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 4, // ลดจาก 8 เหลือ 4
                                  vertical: isSelected ? 12 : 8, // ลดความสูงลงเล็กน้อย
                                ),
                                child: FittedBox(
                                  alignment: Alignment.centerLeft,
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        displayTitle,
                                        maxLines: 1,
                                        style: const TextStyle(
                                          fontFamily: 'SukhumvitSet',
                                          color: Colors.white,
                                          fontSize: 11, // ลดจาก 14 เหลือ 11
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
                                          fontSize: 9, // ลดจาก 12 เหลือ 9
                                          fontWeight: FontWeight.w500,
                                          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                                        ),
                                      ),
                                      // แสดง Badge เมื่อเป็น Local Preview (ยังรอ Server)
                                      if (hasLocalPreview && isStillProcessing) ...[
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withOpacity(0.85),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            '⏳ ตัวอย่างจากเครื่อง',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
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
    ),
   );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: 4,
      itemBuilder: (_, __) => const VideoSkeletonWidget(isTrendingCard: true),
    );
  }
}
