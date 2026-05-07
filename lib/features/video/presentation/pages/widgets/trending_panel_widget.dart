import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:sheserved/config/app_config.dart';
import 'package:sheserved/services/websocket_service.dart';
import '../../../models/video_models.dart';
import 'video_skeleton_widget.dart';

class TrendingPanelWidget extends StatefulWidget {
  final List<Video> trendingVideos;
  final bool isLoadingTrending;
  final String? currentVideoId;
  final String? highlightVideoId; // ID ของวิดีโอที่เป็นเหตุฉุกเฉินใหม่
  final Function(String) onSwitchVideo;
  final VoidCallback? onLoadMore;

  const TrendingPanelWidget({
    super.key,
    required this.trendingVideos,
    required this.isLoadingTrending,
    required this.currentVideoId,
    required this.onSwitchVideo,
    this.highlightVideoId,
    this.onLoadMore,
  });

  @override
  State<TrendingPanelWidget> createState() => _TrendingPanelWidgetState();
}

class _TrendingPanelWidgetState extends State<TrendingPanelWidget> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _pulseController;
  final Map<String, GlobalKey> _itemKeys = {};

  // ใช้วัดขนาดจริงของ AnimatedSize โดยตรง
  final GlobalKey _animatedSizeKey = GlobalKey();
  double? _lastMeasuredHeight;
  int _stableFrameCount = 0;
  bool _isWaitingForSettle = false;

  // ✅ Recommendation #7: Thumbnail URL overrides จาก WebSocket real-time update
  // key = videoId, value = thumbnailUrl ที่ได้รับจาก server หลัง Worker generate เสร็จ
  final Map<String, String> _thumbnailOverrides = {};
  StreamSubscription? _thumbnailSub;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        widget.onLoadMore?.call();
      }
    });

    // ✅ Recommendation #7: ฟัง thumbnail-updated event จาก WebSocket
    _thumbnailSub = WebSocketService().thumbnailUpdateStream.listen((data) {
      if (!mounted) return;
      final incidentId = data['incidentId']?.toString();
      final thumbnailUrl = data['thumbnailUrl']?.toString();
      if (incidentId != null && thumbnailUrl != null) {
        debugPrint('[TrendingPanel] Thumbnail updated for $incidentId: $thumbnailUrl');
        setState(() {
          _thumbnailOverrides[incidentId] = thumbnailUrl;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pulseController.dispose();
    _thumbnailSub?.cancel();
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

    // ถ้ามีการเปลี่ยนวิดีโอที่กำลังดู หรือโหลดเสร็จครั้งแรก
    if (widget.currentVideoId != oldWidget.currentVideoId) {
      _scrollToSelectedCard();
    } else if (oldWidget.isLoadingTrending && !widget.isLoadingTrending) {
      _scrollToSelectedCard();
    }
  }

  void _scrollToSelectedCard() {
    if (widget.currentVideoId == null) return;

    // รีเซ็ต state สำหรับการวัดขนาดใหม่
    _lastMeasuredHeight = null;
    _stableFrameCount = 0;
    _isWaitingForSettle = true;

    // เริ่มวนลูปวัดขนาดจริงของ RenderBox ทุกเฟรม
    _checkSizeSettled();
  }

  /// วัดความสูงจริงของ AnimatedSize widget ทุกเฟรม
  /// เมื่อความสูงไม่เปลี่ยนติดต่อกัน 3 เฟรม → ถือว่า AnimatedSize เล่นจบ → สั่ง scroll
  void _checkSizeSettled() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isWaitingForSettle) return;

      // วัดขนาดจริงจาก RenderBox ของ AnimatedSize
      final renderBox = _animatedSizeKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) {
        // ยังไม่ render → รอเฟรมถัดไป
        _checkSizeSettled();
        return;
      }

      final currentHeight = renderBox.size.height;

      if (_lastMeasuredHeight != null && (currentHeight - _lastMeasuredHeight!).abs() < 0.5) {
        // ความสูงเท่าเดิม (ต่างไม่เกิน 0.5px) → นับเฟรมนิ่ง
        _stableFrameCount++;
      } else {
        // ความสูงยังเปลี่ยนอยู่ → รีเซ็ต
        _stableFrameCount = 0;
      }
      _lastMeasuredHeight = currentHeight;

      if (_stableFrameCount >= 3) {
        // นิ่งแล้ว 3 เฟรมติด → AnimatedSize เล่นจบแน่นอน → สั่ง scroll
        _isWaitingForSettle = false;
        _performScroll();
      } else {
        // ยังไม่นิ่ง → เช็คเฟรมถัดไป
        _checkSizeSettled();
      }
    });
  }

  void _performScroll() {
    if (!mounted || widget.currentVideoId == null) return;

    final key = _itemKeys[widget.currentVideoId!];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        alignment: 0.5,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      // Fallback: ประเมิน offset แล้วค่อย ensureVisible อีกครั้ง
      final index = widget.trendingVideos.indexWhere((v) => v.id == widget.currentVideoId);
      if (index != -1 && _scrollController.hasClients) {
        _scrollController.animateTo(
          index * 80.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        ).then((_) {
          if (!mounted) return;
          final updatedKey = _itemKeys[widget.currentVideoId!];
          if (updatedKey?.currentContext != null) {
            Scrollable.ensureVisible(
              updatedKey!.currentContext!,
              alignment: 0.5,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
          }
        });
      }
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
      key: _animatedSizeKey,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutQuart,
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          Flexible(
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
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        itemCount: widget.trendingVideos.length,
                        itemBuilder: (context, index) {
                          final video = widget.trendingVideos[index];
                          final bool isNewEmergency = video.id == widget.highlightVideoId;
                          
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
                            displayTitle = displayTitle.replaceAll(RegExp(r'\s+\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}$'), '');
                          }
                          
                          if (displayTitle.length > 30) {
                            displayTitle = '${displayTitle.substring(0, 30)}...';
                          }
                          
                          if (isNewEmergency) {
                            displayTitle = '🚨 ใหม่: $displayTitle';
                          }

                          final bool hasLocalPreview = video.localFilePath != null;
                          final bool isStillProcessing = video.status == VideoStatus.processing;
                          final bool isSelected = video.id == widget.currentVideoId;

                          final String? effectiveThumbnailUrl =
                              _thumbnailOverrides[video.id] ?? video.bestThumbnailUrl;

                          if (!_itemKeys.containsKey(video.id)) {
                            _itemKeys[video.id] = GlobalKey();
                          }
                          final itemKey = _itemKeys[video.id];

                          return GestureDetector(
                            key: itemKey,
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
                                  clipBehavior: Clip.hardEdge,
                                  decoration: BoxDecoration(
                                    color: isNewEmergency
                                        ? Colors.red.withOpacity(0.9 + (0.1 * _pulseController.value))
                                        : isSelected
                                            ? Colors.amber[900]?.withOpacity(0.85)
                                            : Colors.blueGrey[900],
                                    borderRadius: BorderRadius.circular(12),
                                    border: isNewEmergency
                                        ? Border.all(color: Colors.white, width: 2)
                                        : isSelected
                                            ? Border.all(color: Colors.amberAccent, width: 2.5)
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
                                                BoxShadow(
                                                  color: Colors.orangeAccent.withOpacity(0.5),
                                                  blurRadius: 8,
                                                  spreadRadius: 2,
                                                )
                                              ]
                                            : null,
                                    // ✅ Bug #5 Fix: ไม่ใช้ BoxDecoration.image → ใช้ Stack+Image.network ใน child แทน
                                  ),
                                  child: child,
                                );
                              },
                              // ✅ Bug #5 Fix: ใช้ Stack เป็น child ของ AnimatedBuilder
                              // เพื่อให้ Image.network มี errorBuilder + loadingBuilder
                              child: Stack(
                                fit: StackFit.loose,
                                children: [
                                  // Layer 1: Thumbnail Background
                                  if (effectiveThumbnailUrl != null)
                                    Positioned.fill(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: CachedNetworkImage(
                                          imageUrl: effectiveThumbnailUrl,
                                          fit: BoxFit.cover,
                                          color: (isNewEmergency
                                                  ? Colors.red
                                                  : isSelected ? Colors.orange : Colors.black)
                                              .withOpacity(isSelected ? 0.3 : 0.5),
                                          colorBlendMode: BlendMode.darken,
                                          // ✅ errorWidget: แสดง fallback เมื่อ URL โหลดไม่ได้
                                          errorWidget: (_, __, ___) => _buildPlaceholderBackground(),
                                          // ✅ placeholder: shimmer เบาๆ ขณะโหลด
                                          placeholder: (_, __) => _buildLoadingBackground(),
                                        ),
                                      ),
                                    )
                                  else
                                    Positioned.fill(child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: _buildPlaceholderBackground(),
                                    )),

                                  // Layer 2: Text + Badge
                                  _buildCardText(
                                    isSelected: isSelected,
                                    displayTitle: displayTitle,
                                    dateStr: dateStr,
                                    hasLocalPreview: hasLocalPreview,
                                    isStillProcessing: isStillProcessing,
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
    ),
   );
  }

  /// Placeholder background เมื่อไม่มีรูปหรือโหลดไม่ได้
  Widget _buildPlaceholderBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blueGrey[800]!,
            Colors.blueGrey[900]!,
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.image_not_supported_outlined, color: Colors.white24, size: 20),
      ),
    );
  }

  /// Loading shimmer เบาๆ ขณะโหลดรูป
  Widget _buildLoadingBackground() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) => Container(
        color: Colors.blueGrey[900]!.withOpacity(0.7 + 0.1 * _pulseController.value),
      ),
    );
  }

  /// Card text content (title + date + badge)
  Widget _buildCardText({
    required bool isSelected,
    required String displayTitle,
    required String dateStr,
    required bool hasLocalPreview,
    required bool isStillProcessing,
  }) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCirc,
      padding: EdgeInsets.symmetric(
        horizontal: 4,
        vertical: isSelected ? 12 : 8,
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
                fontSize: 11,
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
                fontSize: 9,
                fontWeight: FontWeight.w500,
                shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
              ),
            ),
            // Badge เมื่อเป็น Local Preview (ยังรอ Server)
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
