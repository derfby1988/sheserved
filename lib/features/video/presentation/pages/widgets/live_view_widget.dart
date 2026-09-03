import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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
  final VoidCallback? onOpenFullscreen;

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
    this.onOpenFullscreen,
  });

  @override
  State<LiveViewWidget> createState() => _LiveViewWidgetState();
}

class _LiveViewWidgetState extends State<LiveViewWidget>
    with WidgetsBindingObserver {
  bool _isKeyboardOpen = false;

  // สำหรับระบบ Overlay ภาพจากแกลลอรี่ลงบนวิดีโอ
  String? _selectedOverlayPhotoUrl;
  int? _selectedOverlayPhotoIndex;
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
                                                      widget.canViewUnblurred
                                                          ? CachedNetworkImage(
                                                              imageUrl:
                                                                  overlayImageUrl,
                                                              fit: BoxFit
                                                                  .contain,
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
                                                            )
                                                          : ImageFiltered(
                                                              imageFilter:
                                                                  ui.ImageFilter.blur(
                                                                    sigmaX: 10,
                                                                    sigmaY: 10,
                                                                  ),
                                                              child: CachedNetworkImage(
                                                                imageUrl:
                                                                    overlayImageUrl,
                                                                fit: BoxFit
                                                                    .cover,
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
                                if (widget.currentVideoId != null) ...[
                                  const SizedBox(height: 12),
                                  ViewerCountWidget(
                                    formattedViewerCount:
                                        widget.formattedViewerCount,
                                    viewerCount: widget.viewerCount,
                                  ),
                                  const SizedBox(height: 12),
                                  ActionButtonsWidget(
                                    likeCountFormatted:
                                        widget.likeCountFormatted,
                                    likeCount: widget
                                        .likeCount, // ✅ ส่งยอดไลค์ไปให้กราฟด้านใน
                                    isLiked: widget.isLiked,
                                    activeRequests: widget.activeRequests,
                                    activeRequestIndex:
                                        widget.activeRequestIndex,
                                    yieldWayCount: widget.yieldWayCount,
                                    yieldWayCountValue:
                                        widget.yieldWayCountValue,
                                    yieldWayNotifiedCount:
                                        widget.yieldWayNotifiedCount,
                                    userCanCreateRequest:
                                        widget.userCanCreateRequest,
                                    onLike: widget.onLike,
                                    onYieldWay: widget.onYieldWay,
                                    onDonate: widget.onDonate,
                                    onSwitchRequest: widget.onSwitchRequest,
                                  ),
                                ],
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
                                  setState(() {
                                    _selectedOverlayPhotoUrl = photoUrl;
                                    _selectedOverlayPhotoIndex = index;
                                  });
                                  widget.onOverlayChanged?.call(true);
                                },
                                onPhotoChanged: (index, photoUrl) {
                                  // สลับภาพ Overlay อัตโนมัติหากหน้าจอ Overlay กำลังทำงานอยู่
                                  if (_selectedOverlayPhotoUrl != null) {
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
                      trendingVideos: widget.trendingVideos,
                      onLoadMore: widget.onLoadMoreTrending,
                      isLoadingTrending: widget.isLoadingTrending,
                      currentVideoId: widget.currentVideoId,
                      highlightVideoId: widget.highlightVideoId,
                      onSwitchVideo: widget.onSwitchVideo,
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
