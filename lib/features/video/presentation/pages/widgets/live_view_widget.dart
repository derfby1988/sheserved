import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:sheserved/features/donation/models/donation_models.dart';
import '../../../../../services/service_locator.dart';
import 'video_player_widget.dart';
import 'viewer_count_widget.dart';
import 'action_buttons_widget.dart';
import 'trending_panel_widget.dart';
import 'thai_mhung_gallery_widget.dart';
import 'thai_mhung_ruler_gallery_widget.dart';
import '../../../models/video_models.dart';
import 'package:chewie/chewie.dart';
import 'like_trend_chart_widget.dart';
import '../../../../../services/websocket_service.dart';

class LiveViewWidget extends StatefulWidget {
  final ChewieController? chewieController;
  final String? currentVideoId;
  final Video? currentVideo;
  final String formattedViewerCount;
  final int viewerCount; // ✅ เพิ่มตัวเลขสำหรับกราฟ
  final String likeCountFormatted;
  // ✅ เปลี่ยนจากตัวแปรเดียวเป็นรายการคำร้อง (Multi-request support)
  final List<DonationRequest> activeRequests;
  final int activeRequestIndex;

  /// เรียกเมื่อผู้ใช้กดลูกศรสลับคำร้อง
  final Function(bool forward)? onSwitchRequest;
  final List<Video> trendingVideos;
  final VoidCallback? onLoadMoreTrending;
  final bool isLoadingTrending;
  final bool canViewUnblurred;
  final String? highlightVideoId;
  final String yieldWayCount;
  final int yieldWayCountValue; // ✅ เพิ่มค่าตัวเลข
  final int yieldWayNotifiedCount; // ✅ เพิ่มจำนวนที่แจ้งเตือน
  final VoidCallback onLike;
  final VoidCallback onYieldWay;
  final VoidCallback onDonate;
  final void Function(String) onSwitchVideo;

  /// ✅ ผู้ใช้มีสิทธิ์สร้างคำร้องบริจาคไหม? (Reporter/Responder)
  final bool userCanCreateRequest;
  final bool isLiked;
  final int likeCount;
  final int likeTrigger;
  final void Function(ThaiMhungRulerPhoto photo)? onNewPhotoArrived;
  final void Function(bool isOverlayVisible)? onOverlayChanged;
  final GlobalKey? trendingPanelKey;

  /// ✅ Phase 22: การ์ดที่เลือกจากแผนที่เกิดเหตุ — แสดงป้าย "จากแผนที่"
  /// บนการ์ดนั้นในกล่องยอดนิยม (§22.1)
  final String? pinnedFromMapVideoId;
  final VoidCallback? onOpenFullscreen;
  // ✅ GlobalKey ของแถวปุ่ม action (ส่งกำลังใจ/บริจาค/ให้ทาง) — ใช้วัดขอบล่าง
  // เพื่อจำกัดความสูงแชท ไม่ให้ฟองข้อความลอยขึ้นไปบังปุ่มเหล่านี้
  final GlobalKey? actionButtonsKey;
  // ✅ GlobalKey ของการ์ดวิดีโอ — ใช้เป็นเพดานแชทตอนแป้นพิมพ์เปิด
  // (ปุ่ม action ถูกซ่อนแล้ว เหลือการ์ดวิดีโอเป็นองค์ประกอบล่างสุดฝั่งซ้าย)
  final GlobalKey? videoCardKey;

  /// ✅ ล็อกแผงเหตุการณ์ขณะผู้ช่วยเหลืออยู่ระหว่างภารกิจ
  /// - ป้องกันการปัดเปลี่ยนการ์ดและกดการ์ดอื่น
  final bool lockToCurrentVideo;

  /// ✅ Phase 20: ตัวกรองประเภทเหตุของกล่องยอดนิยม — ส่งต่อให้
  /// [TrendingPanelWidget] ตรง ๆ (page เป็นเจ้าของ state)
  /// ปุ่มเปิด sheet อยู่ที่ `EmergencyTopBar` แล้ว จึงไม่ส่ง categories/
  /// canShow/missionSuspendSignal ผ่าน widget นี้
  final Set<String> selectedTrendingCategoryIds;
  final Future<bool> Function(Set<String> selected)?
  onApplyTrendingCategoryFilter;
  final int trendingFilterResetToken;

  const LiveViewWidget({
    super.key,
    required this.chewieController,
    required this.currentVideoId,
    required this.currentVideo,
    required this.formattedViewerCount,
    this.viewerCount = 0,
    required this.likeCountFormatted,
    required this.activeRequests,
    this.activeRequestIndex = 0,
    this.onSwitchRequest,
    required this.trendingVideos,
    this.onLoadMoreTrending,
    required this.isLoadingTrending,
    this.highlightVideoId,
    this.canViewUnblurred = false,
    required this.yieldWayCount,
    this.yieldWayCountValue = 0,
    this.yieldWayNotifiedCount = 0,
    required this.onLike,
    required this.onYieldWay,
    required this.onDonate,
    required this.onSwitchVideo,
    this.userCanCreateRequest = false,
    this.isLiked = false,
    this.likeCount = 0,
    this.likeTrigger = 0,
    this.onNewPhotoArrived,
    this.onOverlayChanged,
    this.trendingPanelKey,
    this.pinnedFromMapVideoId,
    this.actionButtonsKey,
    this.videoCardKey,
    this.onOpenFullscreen,
    this.lockToCurrentVideo = false,
    this.selectedTrendingCategoryIds = const {},
    this.onApplyTrendingCategoryFilter,
    this.trendingFilterResetToken = 0,
  });

  @override
  State<LiveViewWidget> createState() => LiveViewWidgetState();
}

class LiveViewWidgetState extends State<LiveViewWidget>
    with WidgetsBindingObserver {
  bool _isKeyboardOpen = false;

  // สำหรับระบบ Overlay ภาพจากแกลลอรี่ลงบนวิดีโอ
  String? _selectedOverlayPhotoUrl;
  int? _selectedOverlayPhotoIndex;
  int _overlayPhotoGeneration = 0;
  final GlobalKey<ThaiMhungRulerGalleryWidgetState> _galleryKey =
      GlobalKey<ThaiMhungRulerGalleryWidgetState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkKeyboard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _checkKeyboard();
  }

  @override
  void didUpdateWidget(LiveViewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentVideoId != widget.currentVideoId) {
      _overlayPhotoGeneration++;
      if (_selectedOverlayPhotoUrl != null) {
        setState(() {
          _selectedOverlayPhotoUrl = null;
          _selectedOverlayPhotoIndex = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onOverlayChanged?.call(false);
        });
      }
    }
  }

  void _checkKeyboard() {
    final bottomInset =
        ui.PlatformDispatcher.instance.views.first.viewInsets.bottom;
    final isOpen = bottomInset > 0;
    if (_isKeyboardOpen != isOpen) {
      if (mounted) setState(() => _isKeyboardOpen = isOpen);
    }
  }

  /// ✅ Phase 22 (§22.3 ข้อ 5): เปิด overlay ภาพบนการ์ดจากแผนที่เกิดเหตุ —
  /// การ์ดต้อง **หยุด** อยู่เบื้องหลังจริง (ปัจจุบัน overlay เดิมไม่ pause
  /// ตอนเปิด) และปิด overlay แล้วจึงเล่นต่อตาม flow เดิม
  void showOverlayPhoto({required String photoId, required String photoUrl}) {
    if (!mounted) return;
    final generation = ++_overlayPhotoGeneration;
    final videoId = widget.currentVideoId;
    try {
      widget.chewieController?.videoPlayerController.pause();
    } catch (_) {}
    setState(() {
      _selectedOverlayPhotoUrl = photoUrl;
      _selectedOverlayPhotoIndex = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onOverlayChanged?.call(true);
    });
    unawaited(
      _resolveMapPhotoOverlay(
        photoId: photoId,
        videoId: videoId,
        generation: generation,
      ),
    );
  }

  Future<void> _resolveMapPhotoOverlay({
    required String photoId,
    required String? videoId,
    required int generation,
  }) async {
    final focus = await _galleryKey.currentState?.focusPhotoById(photoId);
    if (!mounted ||
        generation != _overlayPhotoGeneration ||
        widget.currentVideoId != videoId ||
        _selectedOverlayPhotoUrl == null) {
      return;
    }
    if (focus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('แสดงภาพตัวอย่างที่แตะ แต่ไม่สามารถเลื่อนดูแกลเลอรีได้'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    setState(() {
      _selectedOverlayPhotoUrl = focus.photoUrl;
      _selectedOverlayPhotoIndex = focus.index;
    });
    if (!focus.exact) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่พบตำแหน่งภาพใน 5 หน้า — แสดงภาพไทยมุงล่าสุดแทน'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// pause ตอนเปิด overlay จาก Ruler gallery เองด้วย (fix เดียวกัน)
  void _pauseVideoForOverlay() {
    try {
      widget.chewieController?.videoPlayerController.pause();
    } catch (_) {}
  }

  bool _isControllerReady() {
    final controller = widget.chewieController;
    if (controller == null) return false;
    try {
      return controller.videoPlayerController.value.isInitialized;
    } catch (_) {
      return false;
    }
  }

  double _safeAspectRatio() {
    final controller = widget.chewieController;
    if (controller == null) return 16 / 9;
    try {
      final value = controller.videoPlayerController.value;
      return value.isInitialized ? value.aspectRatio : 16 / 9;
    } catch (_) {
      return 16 / 9;
    }
  }

  /// ✅ ปัดขึ้น/ลงบนวิดีโอ → เปลี่ยนการ์ดเหตุการณ์ (เหมือนโหมด fullscreen)
  /// - ปัดขึ้น (isUp = true) → การ์ดถัดไปใน Trending
  /// - ปัดลง (isUp = false) → การ์ดก่อนหน้า
  /// - นับ view ทุกครั้งที่เปลี่ยนการ์ดสำเร็จ (เหมือน fullscreen)
  /// - ไม่ทำงานเมื่อ Overlay รูปจาก Ruler Gallery เปิดอยู่
  void _handleVerticalSwipe(bool isUp) {
    if (widget.currentVideoId == null) return;
    // ✅ ระหว่างภารกิจ: ห้ามเปลี่ยนเหตุการณ์ (ป้องกันเผลอกด)
    if (widget.lockToCurrentVideo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('อยู่ระหว่างภารกิจ — ไม่สามารถเปลี่ยนเหตุการณ์ได้'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.black54,
        ),
      );
      return;
    }
    if (_selectedOverlayPhotoUrl != null)
      return; // overlay เปิดอยู่ — ไม่เปลี่ยนการ์ด
    final videos = widget.trendingVideos;
    if (videos.isEmpty) return;

    final currentIndex = videos.indexWhere(
      (v) => v.id == widget.currentVideoId,
    );
    final newIndex = isUp ? currentIndex + 1 : currentIndex - 1;

    if (newIndex < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่มีเหตุการณ์ก่อนหน้า'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.black54,
        ),
      );
      return;
    }
    if (newIndex >= videos.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่มีเหตุการณ์เพิ่มเติม'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.black54,
        ),
      );
      return;
    }

    // นับ view ทุกครั้งที่ปัดเปลี่ยนการ์ด (ตามกฎเดียวกับ fullscreen)
    WebSocketService().recordVideoView(videos[newIndex].id);
    widget.onSwitchVideo(videos[newIndex].id);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final videoWidth = (constraints.maxWidth - 32) * 0.45;
        final ar = _safeAspectRatio();
        final videoHeight = videoWidth / ar;

        return Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 60),
          child: Align(
            alignment: Alignment.topCenter,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  constraints: BoxConstraints(
                    minHeight: widget.currentVideoId == null
                        ? MediaQuery.of(context).size.height * 0.4
                        : 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: (constraints.maxWidth - 32) * 0.45,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Stack(
                                  key: widget.videoCardKey,
                                  children: [
                                    VideoPlayerWidget(
                                      chewieController: widget.chewieController,
                                      currentVideoId: widget.currentVideoId,
                                      currentVideo: widget.currentVideo,
                                      canViewUnblurred: widget.canViewUnblurred,
                                      onOpenFullscreen: widget.onOpenFullscreen,
                                      onDoubleTapLike: widget.onLike,
                                      onVerticalSwipeEnd: _handleVerticalSwipe,
                                    ),
                                    if (_selectedOverlayPhotoUrl != null)
                                      Positioned.fill(
                                        child: GestureDetector(
                                          onHorizontalDragEnd: (details) {
                                            if (details.primaryVelocity! < 0) {
                                              // ปัดซ้าย -> ถัดไป
                                              _galleryKey.currentState
                                                  ?.animateToIndex(
                                                    (_selectedOverlayPhotoIndex ??
                                                            0) +
                                                        1,
                                                  );
                                            } else if (details
                                                    .primaryVelocity! >
                                                0) {
                                              // ปัดขวา -> ก่อนหน้า
                                              final currentIndex =
                                                  _selectedOverlayPhotoIndex ??
                                                  0;
                                              if (currentIndex == 0) {
                                                // ถ้าอยู่รูปแรกแล้วปัดขวา -> ปิด Overlay
                                                setState(() {
                                                  _selectedOverlayPhotoUrl =
                                                      null;
                                                  _selectedOverlayPhotoIndex =
                                                      null;
                                                });
                                                widget.onOverlayChanged?.call(
                                                  false,
                                                );
                                                try {
                                                  widget
                                                      .chewieController
                                                      ?.videoPlayerController
                                                      .play();
                                                } catch (_) {}
                                              } else {
                                                _galleryKey.currentState
                                                    ?.animateToIndex(
                                                      currentIndex - 1,
                                                    );
                                              }
                                            }
                                          },
                                          onTap: () {
                                            if (_selectedOverlayPhotoIndex !=
                                                null) {
                                              _galleryKey.currentState
                                                  ?.showLightbox(
                                                    _selectedOverlayPhotoIndex!,
                                                  );
                                            }
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              40,
                                            ),
                                            child: Container(
                                              color: Colors.black,
                                              child: Builder(
                                                builder: (context) {
                                                  final overlayImageUrl =
                                                      ServiceLocator
                                                          .instance
                                                          .videoRepository
                                                          .ensureFullUrl(
                                                            _selectedOverlayPhotoUrl!,
                                                          );
                                                  return Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      // ✅ §22.11 policy C:
                                                      // photo_url ที่ผ่านมาเป็น
                                                      // ไฟล์เบลอหน้าฝั่ง server
                                                      // (blur_status='completed')
                                                      // อยู่แล้ว — ไม่เบลอซ้ำที่
                                                      // client ตาม lightbox เดิม
                                                      CachedNetworkImage(
                                                        imageUrl:
                                                            overlayImageUrl,
                                                        fit: BoxFit.contain,
                                                        placeholder:
                                                            (
                                                              context,
                                                              url,
                                                            ) => const Center(
                                                              child: CircularProgressIndicator(
                                                                color: Colors
                                                                    .pinkAccent,
                                                              ),
                                                            ),
                                                        errorWidget:
                                                            (
                                                              context,
                                                              url,
                                                              error,
                                                            ) => const Icon(
                                                              Icons
                                                                  .broken_image,
                                                              color: Colors
                                                                  .white,
                                                              size: 50,
                                                            ),
                                                      ),
                                                      Positioned(
                                                        top: 16,
                                                        right: 16,
                                                        child: GestureDetector(
                                                          onTap: () {
                                                            setState(() {
                                                              _selectedOverlayPhotoUrl =
                                                                  null;
                                                              _selectedOverlayPhotoIndex =
                                                                  null;
                                                            });
                                                            widget
                                                                .onOverlayChanged
                                                                ?.call(false);
                                                            try {
                                                              widget
                                                                  .chewieController
                                                                  ?.videoPlayerController
                                                                  .play();
                                                            } catch (_) {}
                                                          },
                                                          child: Container(
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Colors
                                                                      .black54,
                                                                  shape: BoxShape
                                                                      .circle,
                                                                ),
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  6,
                                                                ),
                                                            child: const Icon(
                                                              Icons.close,
                                                              color:
                                                                  Colors.white,
                                                              size: 20,
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
                                  ],
                                ),
                                // ✅ ซ่อนแถว viewer count + ปุ่ม action (ส่งกำลังใจ/
                                // เปิดรับบริจาค/ให้ทาง) ขณะแป้นพิมพ์เปิด — เหมือน
                                // BottomTabsWidget ที่ซ่อนอยู่แล้ว กันฟองแชท
                                // ลอยขึ้นไปบัง/บล็อกปุ่ม และเพิ่มพื้นที่แชทตอนพิมพ์
                                // ใช้ AnimatedSize ให้ยุบ/กลับมาอย่างนุ่มนวล
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                  alignment: Alignment.topCenter,
                                  child: widget.currentVideoId != null &&
                                          !_isKeyboardOpen
                                      ? Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 12),
                                            ViewerCountWidget(
                                              formattedViewerCount: widget
                                                  .formattedViewerCount,
                                              viewerCount: widget.viewerCount,
                                            ),
                                            const SizedBox(height: 12),
                                            ActionButtonsWidget(
                                              key: widget.actionButtonsKey,
                                              likeCountFormatted: widget
                                                  .likeCountFormatted,
                                              likeCount: widget.likeCount,
                                              isLiked: widget.isLiked,
                                              activeRequests:
                                                  widget.activeRequests,
                                              activeRequestIndex:
                                                  widget.activeRequestIndex,
                                              yieldWayCount:
                                                  widget.yieldWayCount,
                                              yieldWayCountValue:
                                                  widget.yieldWayCountValue,
                                              yieldWayNotifiedCount: widget
                                                  .yieldWayNotifiedCount,
                                              userCanCreateRequest: widget
                                                  .userCanCreateRequest,
                                              onLike: widget.onLike,
                                              onYieldWay: widget.onYieldWay,
                                              onDonate: widget.onDonate,
                                              onSwitchRequest:
                                                  widget.onSwitchRequest,
                                            ),
                                          ],
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                          // Thai Mhung Gallery (Ruler Picker) วางด้านขวาของวิดีโอ
                          if (widget.currentVideoId != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: ThaiMhungRulerGalleryWidget(
                                key: _galleryKey,
                                videoId: widget.currentVideoId!,
                                height:
                                    videoHeight, // ความสูงเท่ากับ Video Player พอดี
                                canViewUnblurred: widget.canViewUnblurred,
                                onPhotoTap: (index, photoUrl) {
                                  _overlayPhotoGeneration++;
                                  _pauseVideoForOverlay(); // ✅ §22.2: การ์ดหยุดขณะ overlay เปิด
                                  setState(() {
                                    _selectedOverlayPhotoUrl = photoUrl;
                                    _selectedOverlayPhotoIndex = index;
                                  });
                                  widget.onOverlayChanged?.call(true);
                                },
                                onPhotoChanged: (index, photoUrl) {
                                  // สลับภาพ Overlay อัตโนมัติหากหน้าจอ Overlay กำลังทำงานอยู่
                                  if (_selectedOverlayPhotoUrl != null) {
                                    _overlayPhotoGeneration++;
                                    setState(() {
                                      _selectedOverlayPhotoUrl = photoUrl;
                                      _selectedOverlayPhotoIndex = index;
                                    });
                                  }
                                },
                                onNewPhotoArrived: widget.onNewPhotoArrived,
                              ),
                            ),
                            // สำรองพื้นที่ด้านขวา เพื่อไม่ให้ Trending Panel มาบัง Gallery
                            SizedBox(
                              width: (constraints.maxWidth - 32) * 0.35 + 8,
                            ),
                          ],
                        ],
                      ),
                      // ✅ [Support Analytics] เอาโค้ด LikeTrendChartWidget ตรงนี้ออกเพราะถูกย้ายไปใน ActionButtonsWidget แล้ว
                    ],
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCirc,
                  top: 0,
                  bottom: widget.currentVideoId == null || _isKeyboardOpen
                      ? null
                      : 0,
                  height: widget.currentVideoId == null
                      ? MediaQuery.of(context).size.height * 0.4
                      : (_isKeyboardOpen ? videoHeight : null),
                  right: 0,
                  width: (constraints.maxWidth - 32) * 0.35,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: TrendingPanelWidget(
                      key: widget.trendingPanelKey,
                      pinnedFromMapVideoId: widget.pinnedFromMapVideoId,
                      trendingVideos: widget.trendingVideos,
                      onLoadMore: widget.onLoadMoreTrending,
                      isLoadingTrending: widget.isLoadingTrending,
                      currentVideoId: widget.currentVideoId,
                      highlightVideoId: widget.highlightVideoId,
                      onSwitchVideo: widget.onSwitchVideo,
                      lockToCurrentVideo: widget.lockToCurrentVideo,
                      selectedCategoryIds:
                          widget.selectedTrendingCategoryIds,
                      onApplyCategoryFilter:
                          widget.onApplyTrendingCategoryFilter,
                      filterResetToken: widget.trendingFilterResetToken,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
