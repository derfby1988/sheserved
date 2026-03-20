import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'video_player_widget.dart';
import 'viewer_count_widget.dart';
import 'action_buttons_widget.dart';
import 'trending_panel_widget.dart';
import '../../../models/video_models.dart';
import 'package:chewie/chewie.dart';

class LiveViewWidget extends StatefulWidget {
  final ChewieController? chewieController;
  final String? currentVideoId;
  final Video? currentVideo;
  final String formattedViewerCount;
  final String likeCountFormatted;
  final String donationTotalFormatted;
  final List<Video> trendingVideos;
  final bool isLoadingTrending;
  final bool canViewUnblurred;
  final String? highlightVideoId;
  final VoidCallback onLike;
  final VoidCallback onDonate;
  final Function(String) onSwitchVideo;

  const LiveViewWidget({
    super.key,
    required this.chewieController,
    required this.currentVideoId,
    required this.currentVideo,
    required this.formattedViewerCount,
    required this.likeCountFormatted,
    required this.donationTotalFormatted,
    required this.trendingVideos,
    required this.isLoadingTrending,
    this.highlightVideoId,
    this.canViewUnblurred = false,
    required this.onLike,
    required this.onDonate,
    required this.onSwitchVideo,
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
                                donationTotalFormatted: widget.donationTotalFormatted,
                                onLike: widget.onLike,
                                onYieldWay: () {},
                                onDonate: widget.onDonate,
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(width: (constraints.maxWidth - 32) * 0.55),
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
