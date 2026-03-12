import 'package:flutter/material.dart';
import 'video_player_widget.dart';
import 'viewer_count_widget.dart';
import 'action_buttons_widget.dart';
import 'trending_panel_widget.dart';
import '../../../models/video_models.dart';
import 'package:chewie/chewie.dart';

class LiveViewWidget extends StatelessWidget {
  final ChewieController? chewieController;
  final String? currentVideoId;
  final Video? currentVideo;
  final String formattedViewerCount;
  final String likeCountFormatted;
  final String donationTotalFormatted;
  final List<Video> trendingVideos;
  final bool isLoadingTrending;
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
    required this.onLike,
    required this.onDonate,
    required this.onSwitchVideo,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.topCenter,
            child: Stack(
              clipBehavior: Clip.none,
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
                          VideoPlayerWidget(
                            chewieController: chewieController,
                            currentVideoId: currentVideoId,
                            currentVideo: currentVideo,
                          ),
                          const SizedBox(height: 12),
                          ViewerCountWidget(formattedViewerCount: formattedViewerCount),
                          const SizedBox(height: 12),
                          ActionButtonsWidget(
                            likeCountFormatted: likeCountFormatted,
                            donationTotalFormatted: donationTotalFormatted,
                            onLike: onLike,
                            onYieldWay: () {},
                            onDonate: onDonate,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: (constraints.maxWidth - 32) * 0.55),
                  ],
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: (constraints.maxWidth - 32) * 0.35,
                  child: TrendingPanelWidget(
                    trendingVideos: trendingVideos,
                    isLoadingTrending: isLoadingTrending,
                    currentVideoId: currentVideoId,
                    onSwitchVideo: onSwitchVideo,
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
