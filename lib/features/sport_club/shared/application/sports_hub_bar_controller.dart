import 'package:flutter/widgets.dart';

import '../../application/feed_filter_collapse_controller.dart';

/// Owns the shell-level shared sport bar state (plan 21.7.13):
///
/// - Collapse/expand is driven by the *active* page's scroll offset, kept
///   per page so switching back restores that page's collapsed state with an
///   animated transition instead of a jump.
/// - Per-page trailing widgets (e.g. Add Sport, coach quick actions) are
///   registered by each page and rendered by the single shell-owned bar, so
///   real controls keep an aligned frame without reserving blank space for
///   pages that have none.
class SportsHubBarController extends ChangeNotifier {
  static const double barHeight = 56;

  final Map<int, FeedFilterCollapseController> _collapses = {};
  final Map<int, WidgetBuilder> _trailing = {};
  int _activePage = 1;
  bool _collapsed = false;

  bool get isCollapsed => _collapsed;
  int get activePage => _activePage;

  /// Feeds the current scroll offset of [page]. Only the active page can
  /// change the shared bar; inactive pages just remember their state.
  void reportScroll(int page, double pixels) {
    final controller = _collapses.putIfAbsent(
      page,
      FeedFilterCollapseController.new,
    );
    final changed = controller.update(pixels);
    if (page == _activePage && changed && controller.isCollapsed != _collapsed) {
      _collapsed = controller.isCollapsed;
      notifyListeners();
    }
  }

  void setActivePage(int page) {
    if (_activePage == page) return;
    _activePage = page;
    final next = _collapses[page]?.isCollapsed ?? false;
    _collapsed = next;
    // Always notify: the trailing control switches pages even when the
    // collapse state does not change.
    notifyListeners();
  }

  /// Registers (or clears, with null) the trailing control for [page].
  void setTrailing(int page, WidgetBuilder? builder) {
    if (builder == null) {
      if (_trailing.remove(page) == null) return;
    } else {
      _trailing[page] = builder;
    }
    notifyListeners();
  }

  Widget? buildTrailing(BuildContext context, int page) =>
      _trailing[page]?.call(context);

  /// Expands the bar (e.g. floating filter button tap on Find Buddies).
  void expand() {
    final controller = _collapses[_activePage] ?? FeedFilterCollapseController();
    _collapses[_activePage] = controller..expand();
    if (_collapsed) {
      _collapsed = false;
      notifyListeners();
    }
  }
}
