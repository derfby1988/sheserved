import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:sheserved/features/donation/models/donation_models.dart';
import 'video_player_widget.dart';
import 'viewer_count_widget.dart';
import 'action_buttons_widget.dart';
import 'trending_panel_widget.dart';
import 'thai_mhung_gallery_widget.dart';
import 'thai_mhung_ruler_gallery_widget.dart';
import '../../../models/video_models.dart';
import 'package:chewie/chewie.dart';

class LiveViewWidget extends StatefulWidget {
  final ChewieController? chewieController;
  final String? currentVideoId;
  final Video? currentVideo;
  final String formattedViewerCount;
  final String likeCountFormatted;
  // ✅ เปลี่ยนจากตัวแปรเดียวเป็นรายการคำร้อง (Multi-request support)
  final List<DonationRequest> activeRequests;
  final int activeRequestIndex;
  /// เรียกเมื่อผู้ใช้กดลูกศรสลับคำร้อง
  final Function(bool forward)? onSwitchRequest;
  final List<Video> trendingVideos;
  final bool isLoadingTrending;
  final bool canViewUnblurred;
  final String? highlightVideoId;
  final VoidCallback onLike;
  final VoidCallback onDonate;
  final Function(String) onSwitchVideo;
  /// ✅ ผู้ใช้มีสิทธิ์สร้างคำร้องบริจาคไหม? (Reporter/Responder)
  final bool userCanCreateRequest;

  const LiveViewWidget({
    super.key,
    required this.chewieController,
    required this.currentVideoId,
    required this.currentVideo,
    required this.formattedViewerCount,
    required this.likeCountFormatted,
    required this.activeRequests,
    this.activeRequestIndex = 0,
    this.onSwitchRequest,
    required this.trendingVideos,
    required this.isLoadingTrending,
    this.highlightVideoId,
    this.canViewUnblurred = false,
    required this.onLike,
    required this.onDonate,
    required this.onSwitchVideo,
    this.userCanCreateRequest = false,
  });

  @override
  State<LiveViewWidget> createState() => _LiveViewWidgetState();
}

class _LiveViewWidgetState extends State<LiveViewWidget> with WidgetsBindingObserver {
  bool _isKeyboardOpen = false;

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

  void _checkKeyboard() {
    final bottomInset = ui.PlatformDispatcher.instance.views.first.viewInsets.bottom;
    final isOpen = bottomInset > 0;
    if (_isKeyboardOpen != isOpen) {
      if (mounted) setState(() => _isKeyboardOpen = isOpen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final videoWidth = (constraints.maxWidth - 32) * 0.45;
        double ar = 16 / 9;
        if (widget.chewieController != null && widget.chewieController!.videoPlayerController.value.isInitialized) {
          ar = widget.chewieController!.videoPlayerController.value.aspectRatio;
        }
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
                    minHeight: widget.currentVideoId == null ? MediaQuery.of(context).size.height * 0.4 : 0,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: (constraints.maxWidth - 32) * 0.45,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            VideoPlayerWidget(
                              chewieController: widget.chewieController,
                              currentVideoId: widget.currentVideoId,
                              currentVideo: widget.currentVideo,
                              canViewUnblurred: widget.canViewUnblurred,
                            ),
                            if (widget.currentVideoId != null) ...[
                              const SizedBox(height: 12),
                              ViewerCountWidget(formattedViewerCount: widget.formattedViewerCount),
                              const SizedBox(height: 12),
                              ActionButtonsWidget(
                                likeCountFormatted: widget.likeCountFormatted,
                                activeRequests: widget.activeRequests,
                                activeRequestIndex: widget.activeRequestIndex,
                                userCanCreateRequest: widget.userCanCreateRequest,
                                onLike: widget.onLike,
                                onYieldWay: () {},
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
                        ThaiMhungRulerGalleryWidget(
                          videoId: widget.currentVideoId!,
                          height: videoHeight, // ความสูงเท่ากับ Video Player พอดี
                        ),
                        // สำรองพื้นที่ด้านขวา เพื่อไม่ให้ Trending Panel มาบัง Gallery
                        SizedBox(width: (constraints.maxWidth - 32) * 0.35 + 8),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: widget.currentVideoId == null || _isKeyboardOpen ? null : 0,
                  height: widget.currentVideoId == null 
                      ? MediaQuery.of(context).size.height * 0.4 
                      : (_isKeyboardOpen ? videoHeight : null),
                  right: 0,
                  width: (constraints.maxWidth - 32) * 0.35,
                  child: TrendingPanelWidget(
                    trendingVideos: widget.trendingVideos,
                    isLoadingTrending: widget.isLoadingTrending,
                    currentVideoId: widget.currentVideoId,
                    highlightVideoId: widget.highlightVideoId,
                    onSwitchVideo: widget.onSwitchVideo,
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
