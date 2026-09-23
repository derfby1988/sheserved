/// Tracks the Find Buddies feed scroll offset and decides when the pinned
/// filter rows should collapse (content scrolled up past a threshold) and
/// expand again (any upward scroll of the content).
class FeedFilterCollapseController {
  FeedFilterCollapseController({this.collapseThreshold = 56});

  final double collapseThreshold;

  double _lastOffset = 0;
  bool _collapsed = false;

  bool get isCollapsed => _collapsed;

  /// Feeds the current scroll offset. Returns true when the collapsed state
  /// changed and the UI should rebuild.
  bool update(double pixels) {
    final wasCollapsed = _collapsed;
    if (pixels > collapseThreshold && pixels >= _lastOffset) {
      _collapsed = true;
    } else if (pixels < _lastOffset - 1) {
      _collapsed = false;
    }
    _lastOffset = pixels;
    return _collapsed != wasCollapsed;
  }

  /// Restores the filter rows immediately (e.g. floating filter button tap).
  void expand() {
    _collapsed = false;
  }
}
