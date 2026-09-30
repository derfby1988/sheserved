import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/pages/book_court_page.dart';
import 'package:sheserved/features/sport_club/find_coach/presentation/pages/find_coach_page.dart';
import 'package:sheserved/features/sport_club/presentation/pages/sport_club_page.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_bar_controller.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_controller.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_sport_catalog.dart';
import 'package:sheserved/features/sport_club/shared/presentation/widgets/shared_sport_filter_bar.dart';
import 'package:sheserved/features/sport_club/shared/presentation/widgets/sports_hub_page_indicator.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/shared/widgets/tlz_app_top_bar.dart';
import 'package:sheserved/shared/widgets/tlz_bottom_navigation_bar.dart';
import 'package:sheserved/shared/widgets/tlz_drawer.dart';

class SportsHubPage extends StatefulWidget {
  final Widget? findBuddiesPage;

  /// Index of the hub page shown first. `/community/sport-club` and legacy
  /// entry points always use 1 (Find Buddies); dedicated Sports Hub routes
  /// such as `/community/sports/courts` (0) and `/community/sports/coaches`
  /// (2) land on their domain page directly.
  final int initialPage;

  const SportsHubPage({super.key, this.findBuddiesPage, this.initialPage = 1});

  @override
  State<SportsHubPage> createState() => _SportsHubPageState();
}

class _SportsHubPageState extends State<SportsHubPage> {
  final _findBuddiesController = SportClubPageController();
  late final SportsHubController _hubController;
  late final SportsHubSportCatalog _sportCatalog;
  late final SportsHubBarController _sportBar;
  int _currentPage = 1;

  int get _initialPage => widget.initialPage.clamp(0, 2).toInt();

  @override
  void initState() {
    super.initState();
    _currentPage = _initialPage;
    _hubController = SportsHubController(
      userIdProvider: () => AuthService.instance.currentUser?.id,
    );
    _sportCatalog = SportsHubSportCatalog(
      userIdProvider: () => AuthService.instance.currentUser?.id,
    );
    _sportBar = SportsHubBarController();
    unawaited(_hubController.load());
    unawaited(_sportCatalog.load());
    AuthService.instance.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    final userId = AuthService.instance.currentUser?.id;
    _hubController.handleUserChanged(userId);
    // Load the new user's persisted hub filters (no-op on logout).
    unawaited(_hubController.load());
    unawaited(_sportCatalog.load());
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    _hubController.dispose();
    _sportCatalog.dispose();
    _sportBar.dispose();
    _findBuddiesController.dispose();
    super.dispose();
  }

  void _handlePageChanged(int page) {
    if (_currentPage == page) return;
    setState(() => _currentPage = page);
    _sportBar.setActivePage(page);
    if (page == 1) unawaited(_findBuddiesController.refreshIfStale());
  }

  void _onSharedSportSelected(String? id, bool selected) {
    _hubController.updateShared(
      _hubController.shared.withSportId(selected ? id : null),
    );
  }

  void _onNavIndexChanged(int index) {
    final routes = <int, String>{
      0: '/home',
      1: '/volunteer',
      3: '/pharmacy',
      4: '/profile',
    };
    final route = routes[index];
    if (route == null) return;
    Navigator.pushReplacementNamed(context, route);
  }

  void _onAddPressed() {
    Navigator.pushNamed(context, '/emergency');
  }

  /// The single shared sport bar (plan 21.7.13): one instance owned by the
  /// shell, overlaid on the PageView so it does not move with horizontal
  /// swipes. Collapsing slides/fades the bar without changing the page
  /// viewport, and its horizontal scroll offset lives in the single mounted
  /// chips list so it survives page switches.
  Widget _buildSharedSportBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: Listenable.merge([_sportBar, _sportCatalog, _hubController]),
        builder: (context, _) {
          final collapsed = _sportBar.isCollapsed;
          return AnimatedSlide(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            offset: collapsed ? const Offset(0, -0.6) : Offset.zero,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 240),
              opacity: collapsed ? 0 : 1,
              child: IgnorePointer(
                ignoring: collapsed,
                child: Container(
                  height: SportsHubBarController.barHeight,
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _sportCatalog.loadError != null
                      // Catalog unreachable: surface retry rather than a
                      // bar that looks loaded with only "ทั้งหมด".
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () =>
                                unawaited(_sportCatalog.load()),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('โหลดรายการกีฬาไม่สำเร็จ'),
                          ),
                        )
                      : SharedSportFilterBar(
                          sports: _sportCatalog.sports,
                          selectedSportId: _hubController.shared.sportId,
                          myCreatedSportIds: _sportCatalog.myCreatedSportIds,
                          onSportSelected: _onSharedSportSelected,
                          trailing:
                              _sportBar.buildTrailing(context, _currentPage),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      extendBody: true,
      drawer: TlzDrawer(),
      bottomNavigationBar: TlzBottomNavigationBar(
        currentIndex: -1,
        onIndexChanged: _onNavIndexChanged,
        onAddPressed: _onAddPressed,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: TlzAppTopBar.onPrimary(
                  middle: ValueListenableBuilder<String?>(
                    valueListenable: _findBuddiesController.feedTitle,
                    builder: (context, sportName, _) {
                      // The Find Buddies header shows the active sport filter
                      // while its filter bar is collapsed.
                      final title = _currentPage == 1 && sportName != null
                          ? sportName
                          : 'คลับกีฬา';
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                        ),
                      );
                    },
                  ),
                  onChatRoomTap: _findBuddiesController.openGroupChat,
                  actions: [
                    IconButton(
                      tooltip: 'รีเฟรชข้อมูล',
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _currentPage == 1
                          ? _findBuddiesController.refresh
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
              ),
              child: SportsHubPager(
                initialPage: _initialPage,
                bookCourtPage: BookCourtPage(
                  hubController: _hubController,
                  sportCatalog: _sportCatalog,
                  sportBar: _sportBar,
                ),
                findBuddiesPage:
                    widget.findBuddiesPage ??
                    SportClubPage(
                      embeddedInSportsHub: true,
                      controller: _findBuddiesController,
                      hubController: _hubController,
                      sportCatalog: _sportCatalog,
                      sportBar: _sportBar,
                    ),
                findCoachPage: FindCoachPage(
                  hubController: _hubController,
                  sportCatalog: _sportCatalog,
                  sportBar: _sportBar,
                ),
                overlay: _buildSharedSportBar(),
                onPageChanged: _handlePageChanged,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _currentPage == 1
          ? Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 4),
              child: FloatingActionButton.extended(
                heroTag: 'createGroupFab',
                onPressed: _findBuddiesController.createGroup,
                icon: const Icon(Icons.add),
                label: const Text('สร้างก๊วน'),
              ),
            )
          : null,
    );
  }
}

class SportsHubPager extends StatefulWidget {
  final Widget bookCourtPage;
  final Widget findBuddiesPage;
  final Widget findCoachPage;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;

  /// Overlay rendered above the PageView viewport (e.g. the shared sport
  /// bar). It stays fixed while pages swipe underneath it.
  final Widget? overlay;

  const SportsHubPager({
    super.key,
    required this.bookCourtPage,
    required this.findBuddiesPage,
    required this.findCoachPage,
    this.initialPage = 1,
    this.onPageChanged,
    this.overlay,
  });

  @override
  State<SportsHubPager> createState() => _SportsHubPagerState();
}

class _SportsHubPagerState extends State<SportsHubPager> {
  late final PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage.clamp(0, 2).toInt();
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _animateToPage(int page) {
    if (page < 0 || page > 2 || page == _currentPage) return;
    if (!_pageController.hasClients) {
      _pageController.jumpToPage(page);
      return;
    }
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  void _handlePageChanged(int page) {
    if (_currentPage == page) return;
    setState(() => _currentPage = page);
    widget.onPageChanged?.call(page);
  }

  /// ลาก ruler — กระโดดไปหน้าทันทีระหว่างลาก (ไม่เล่นอนิเมชัน) เพื่อให้หัวหมุด
  /// กับเนื้อหาตรงกันแบบเรียลไทม์และไม่ snap กลับไปหน้าเดิมก่อน
  void _scrubToPage(int page) {
    if (page < 0 || page > 2) return;
    if (!_pageController.hasClients) {
      if (_currentPage != page) setState(() => _currentPage = page);
      return;
    }
    if (_pageController.page?.round() == page) return;
    _pageController.jumpToPage(page);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: AnimatedBuilder(
            animation: _pageController,
            builder: (context, _) => SportsHubPageIndicator(
              // ส่งตำแหน่งหน้าแบบต่อเนื่อง เพื่อให้หัวหมุด/ปุ่มที่เลือกขยับตาม
              // การปัดหรืออนิเมชันของ PageView ทันที (ไม่หน่วงรอ onPageChanged)
              page: _pageController.hasClients && _pageController.page != null
                  ? _pageController.page!
                  : _currentPage.toDouble(),
              onPageSelected: _animateToPage,
              onPageScrubbed: _scrubToPage,
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              PageView(
                key: const PageStorageKey<String>('sports_hub_page_view'),
                controller: _pageController,
                onPageChanged: _handlePageChanged,
                children: [
                  _KeepAlivePage(
                    key: const PageStorageKey<String>('book_court'),
                    child: widget.bookCourtPage,
                  ),
                  _KeepAlivePage(
                    key: const PageStorageKey<String>('find_buddies'),
                    child: widget.findBuddiesPage,
                  ),
                  _KeepAlivePage(
                    key: const PageStorageKey<String>('find_coach'),
                    child: widget.findCoachPage,
                  ),
                ],
              ),
              ?widget.overlay,
            ],
          ),
        ),
      ],
    );
  }
}

/// Keeps a hub page mounted while the user swipes to another page, so each
/// page keeps its own loaded data and scroll position instead of reloading
/// every time it comes back into view.
class _KeepAlivePage extends StatefulWidget {
  final Widget child;

  const _KeepAlivePage({super.key, required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
