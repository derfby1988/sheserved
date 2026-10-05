import '../../models/video_models.dart';

String? trendingCategoryFilterAutoSwitchTarget({
  required String? currentVideoId,
  required String? currentVideoIdAtApply,
  required String? currentCategoryId,
  required Set<String> selectedCategoryIds,
  required Iterable<Video> visibleVideos,
  required bool missionFilterSuspended,
}) {
  if (missionFilterSuspended ||
      currentVideoId == null ||
      currentVideoId != currentVideoIdAtApply ||
      selectedCategoryIds.isEmpty) {
    return null;
  }

  final currentMatchesSelection =
      (currentCategoryId != null &&
          selectedCategoryIds.contains(currentCategoryId)) ||
      visibleVideos.any(
        (video) =>
            video.id == currentVideoId &&
            video.categoryId != null &&
            selectedCategoryIds.contains(video.categoryId),
      );
  if (currentMatchesSelection) return null;

  for (final video in visibleVideos) {
    if (video.id != currentVideoId &&
        video.categoryId != null &&
        selectedCategoryIds.contains(video.categoryId)) {
      return video.id;
    }
  }

  return null;
}
