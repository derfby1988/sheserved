import '../../models/video_models.dart';

Set<String> trendingCategoryIdsForActiveScope({
  required Set<String> committedCategoryIds,
  required String? incidentMapCategoryId,
  required bool isIncidentMapPlaybackContext,
  required bool missionFilterSuspended,
}) {
  if (missionFilterSuspended) return const {};
  final mapCategoryId = incidentMapCategoryId?.trim();
  if (isIncidentMapPlaybackContext &&
      mapCategoryId != null &&
      mapCategoryId.isNotEmpty) {
    return {mapCategoryId};
  }
  return Set<String>.of(committedCategoryIds);
}

List<Video> filterTrendingVideosByCategoryIds(
  Iterable<Video> videos,
  Set<String> categoryIds,
) {
  if (categoryIds.isEmpty) return List<Video>.of(videos);
  return videos
      .where(
        (video) =>
            video.categoryId != null && categoryIds.contains(video.categoryId),
      )
      .toList();
}

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
