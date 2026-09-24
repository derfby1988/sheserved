import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_controller.dart';
import 'package:sheserved/features/sport_club/shared/domain/sports_discovery_filter.dart';
import 'package:sheserved/features/sport_club/shared/presentation/widgets/shared_sport_filter_bar.dart';
import 'package:sheserved/services/auth_service.dart';

import '../../application/book_court_booking_service.dart';
import '../../application/book_court_query.dart';
import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';
import '../../domain/book_court_filter.dart';
import '../widgets/book_court_filter_sheet.dart';
import '../widgets/book_court_quick_filter_row.dart';
import '../widgets/court_booking_sheet.dart';
import '../widgets/court_card.dart';
import '../widgets/court_detail_sheet.dart';
import '../widgets/court_owner_register_sheet.dart';
import '../widgets/court_usage_terms_dialog.dart';
import 'court_my_bookings_page.dart';
import 'court_owner_dashboard.dart';

/// Book Court page of the Sports Hub.
///
/// Discovery surface for approved venues/courts plus the booking entry
/// flow. The page owns only Book Court domain data: the shared
/// sport/location state comes from [SportsHubController] and the domain
/// filter lives in `hub.courts`, so values like booking date never leak
/// into Find Buddies or Find Coach queries.
class BookCourtPage extends StatefulWidget {
  final SportsHubController? hubController;

  const BookCourtPage({super.key, this.hubController});

  @override
  State<BookCourtPage> createState() => _BookCourtPageState();
}

class _BookCourtPageState extends State<BookCourtPage> {
  late final FitnessBuddiesRepository _buddiesRepo;
  late final BookCourtRepository _repo;
  late final BookCourtQuery _query;
  late final BookCourtBookingService _booking;

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _sports = [];
  List<VenueSummary> _venues = [];
  bool _loading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  int _requestId = 0;
  double? _userLat;
  double? _userLng;

  static const _pageSize = 20;

  SportsHubController? get _hub => widget.hubController;
  BookCourtFilter get _filter => _hub?.courts ?? const BookCourtFilter();
  String? get _userId => AuthService.instance.currentUser?.id;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    _buddiesRepo = FitnessBuddiesRepository(client);
    _repo = BookCourtRepository(client);
    _query = BookCourtQuery(
      listVenues: _repo.listPublicVenues,
      hydrateVenues: _repo.hydrateVenueCards,
      bookedVenueIds: _repo.listMyBookedVenueIds,
      managedVenueIds: _repo.listMyManagedVenueIds,
      pageSize: _pageSize,
    );
    _booking = BookCourtBookingService(
      create: _repo.createBooking,
      cancel: _repo.cancelBooking,
      decide: _repo.decideBooking,
      changeSlot: _repo.changePendingBookingSlot,
    );
    _scrollController.addListener(_onScroll);
    _hub?.addListener(_onHubChanged);
    _searchController.text = _hub?.shared.query ?? '';
    _init();
  }

  @override
  void didUpdateWidget(covariant BookCourtPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hubController != widget.hubController) {
      oldWidget.hubController?.removeListener(_onHubChanged);
      widget.hubController?.addListener(_onHubChanged);
      _onHubChanged();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _hub?.removeListener(_onHubChanged);
    super.dispose();
  }

  /// Shared filter changes (sport/location/query) re-run discovery with a
  /// new request id so superseded responses are discarded.
  void _onHubChanged() {
    if (!mounted) return;
    final shared = _hub?.shared;
    if (shared != null && _searchController.text != shared.query) {
      _searchController.text = shared.query;
    }
    _reload();
  }

  Future<void> _init() async {
    try {
      final sports = await _buddiesRepo.getApprovedSports(userId: _userId);
      if (!mounted) return;
      setState(() => _sports = sports);
    } catch (_) {
      // Empty sport row is fine; the feed still renders.
    }
    await _reload();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    final requestId = ++_requestId;
    setState(() => _loading = true);
    try {
      final page = await _query.fetch(
        shared: _hub?.shared ?? const _SharedFallback().filter,
        filter: _filter,
        offset: 0,
        userId: _userId,
        userLat: _userLat,
        userLng: _userLng,
        isStale: () => requestId != _requestId,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _venues = page.venues;
        _offset = page.nextOffset;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } on StateError catch (e) {
      if (e.message != 'STALE_FILTER_REQUEST' && mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final requestId = ++_requestId;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _query.fetch(
        shared: _hub?.shared ?? const _SharedFallback().filter,
        filter: _filter,
        offset: _offset,
        userId: _userId,
        userLat: _userLat,
        userLng: _userLng,
        isStale: () => requestId != _requestId,
      );
      if (!mounted) return;
      if (requestId != _requestId) {
        setState(() => _isLoadingMore = false);
        return;
      }
      setState(() {
        _venues = [..._venues, ...page.venues];
        _offset = page.nextOffset;
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  // =============== Shared filter handlers ===============

  void _onSportSelected(String? id, bool selected) {
    final hub = _hub;
    if (hub == null) return;
    hub.updateShared(
      hub.shared.copyWith(sportId: selected ? id : null, clearSportId: true),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _hub?.updateShared(_hub!.shared.copyWith(query: value));
    });
  }

  Future<bool> _requestLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }
    try {
      final position = await Geolocator.getCurrentPosition();
      _userLat = position.latitude;
      _userLng = position.longitude;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _toggleQuickFilter(String key) async {
    final hub = _hub;
    if (key == 'radius') {
      if (hub == null) return;
      if (hub.shared.locationEnabled) {
        hub.updateShared(hub.shared.copyWith(locationEnabled: false));
        return;
      }
      final ok = await _requestLocation();
      if (!ok) {
        _toast('ไม่สามารถเข้าถึงตำแหน่งได้ กรุณาอนุญาตสิทธิ์ตำแหน่ง');
        return;
      }
      hub.updateShared(hub.shared.copyWith(locationEnabled: true));
      return;
    }
    if (hub == null) return;
    final filter = _filter;
    switch (key) {
      case 'available':
        hub.updateCourts(
          filter.copyWith(availableOnly: !filter.availableOnly),
        );
      case 'bookedByMe':
        if (!await _requireLogin()) return;
        hub.updateCourts(
          filter.copyWith(bookedByMeOnly: !filter.bookedByMeOnly),
        );
      case 'owner':
        if (!await _requireLogin()) return;
        hub.updateCourts(filter.copyWith(ownerOnly: !filter.ownerOnly));
    }
  }

  Future<bool> _requireLogin() async {
    if (_userId != null) return true;
    await Navigator.pushNamed(
      context,
      '/login',
      arguments: {'redirect': '/community/sport-club'},
    );
    return _userId != null;
  }

  Future<void> _showAdvancedFilter() async {
    final hub = _hub;
    if (hub == null) return;
    final next = await BookCourtFilterSheet.show(context, current: _filter);
    if (next != null) hub.updateCourts(next);
  }

  // =============== Detail + booking flow ===============

  Future<void> _openVenue(VenueSummary venue) async {
    await CourtDetailSheet.show(
      context,
      venue: venue,
      repo: _repo,
      sharedSportId: _hub?.shared.sportId,
      onBookCourt: (court) => _startBooking(venue, court),
      onWriteReview: _userId == null
          ? null
          : () => _openMyBookings(reviewVenueId: venue.id),
    );
  }

  /// Booking flow: pick slot -> accept venue terms -> trusted RPC create.
  /// On `TERMS_VERSION_CHANGED` the fresh terms are fetched and the consent
  /// dialog is shown once more with the new version.
  Future<void> _startBooking(VenueSummary venue, VenueCourt court) async {
    final userId = _userId;
    if (userId == null) {
      await _requireLogin();
      if (_userId == null) return;
    }
    if (!mounted) return;
    Navigator.of(context).maybePop(); // close detail sheet

    final slot = await CourtBookingSheet.show(
      context,
      court: court,
      venueName: venue.name,
      initialDate: _filter.date,
    );
    if (slot == null || !mounted) return;

    var terms = await _repo.getActiveVenueTerms(venue.id);
    final idempotencyKey = const Uuid().v4();
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!mounted) return;
      final accepted = await CourtUsageTermsDialog.show(
        context,
        terms: terms,
        venueName: venue.name,
      );
      if (accepted == null || !mounted) return;
      try {
        await _booking.book(
          userId: _userId,
          court: court,
          startsAt: slot.start,
          endsAt: slot.end,
          termsVersion: accepted.version,
          idempotencyKey: idempotencyKey,
        );
        if (!mounted) return;
        _toast(
          court.approvalMode == BookingApprovalMode.instant
              ? 'จองสนามสำเร็จ'
              : 'ส่งคำขอจองแล้ว รอเจ้าของอนุมัติ',
        );
        return;
      } catch (e) {
        if (e.toString().contains('TERMS_VERSION_CHANGED') && attempt == 0) {
          terms = await _repo.getActiveVenueTerms(venue.id);
          continue;
        }
        _toast(_mapBookingError(e));
        return;
      }
    }
  }

  Future<void> _openMyBookings({String? reviewVenueId}) async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourtMyBookingsPage(repo: _repo),
      ),
    );
  }

  Future<void> _openOwnerDashboard() async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CourtOwnerDashboard(repo: _repo)),
    );
    if (mounted) _reload();
  }

  /// "ลงทะเบียนสนาม" entry point — shown while the `ownerOnly` quick filter
  /// is active, same bottom-right slot as the Find Buddies "สร้างก๊วน" FAB.
  /// Approved owners land on the dashboard to add/manage venues; everyone
  /// else gets the owner application sheet.
  Future<void> _openOwnerRegistration() async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    final userId = _userId;
    if (userId == null) return;

    VenueOwnerProfile? profile;
    try {
      profile = await _repo.getMyOwnerProfile(userId);
    } catch (_) {
      profile = null;
    }
    if (!mounted) return;
    if (profile?.status == VenueOwnerStatus.approved) {
      await _openOwnerDashboard();
      return;
    }

    final result = await CourtOwnerRegisterSheet.show(context);
    if (result == null || !mounted) return;
    try {
      await _repo.submitOwnerApplication(
        userId: userId,
        businessName: result.businessName ?? result.legalName,
        contactName: result.legalName,
        contactPhone: result.contact,
      );
      if (!mounted) return;
      _toast('ส่งใบสมัครเจ้าของสนามแล้ว รอการอนุมัติ');
    } catch (_) {
      _toast('ส่งใบสมัครไม่สำเร็จ กรุณาลองใหม่');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _filterSummary {
    final parts = <String>[];
    final shared = _hub?.shared;
    final f = _filter;
    if (shared?.province?.isNotEmpty == true) parts.add(shared!.province!);
    if (shared?.district?.isNotEmpty == true) parts.add(shared!.district!);
    if (f.date != null) parts.add('${f.date!.day}/${f.date!.month}');
    if (f.minPrice != null || f.maxPrice != null) parts.add('ราคา');
    if (f.minRating != null) parts.add('⭐${f.minRating}');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final shared = _hub?.shared;
    final filter = _filter;
    return Stack(
      children: [
        _buildBody(shared, filter),
        if (filter.ownerOnly)
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton.extended(
              heroTag: 'book_court_register_venue',
              tooltip: 'ลงทะเบียนสนาม',
              onPressed: _openOwnerRegistration,
              icon: const Icon(Icons.storefront_rounded),
              label: const Text('ลงทะเบียนสนาม'),
            ),
          ),
      ],
    );
  }

  Widget _buildBody(SportsDiscoveryFilter? shared, BookCourtFilter filter) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              SharedSportFilterBar(
                sports: _sports,
                selectedSportId: shared?.sportId,
                onSportSelected: _onSportSelected,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'การจองของฉัน',
                      icon: const Icon(Icons.event_note_rounded),
                      onPressed: _openMyBookings,
                    ),
                    IconButton(
                      tooltip: 'จัดการสนามของฉัน',
                      icon: const Icon(Icons.storefront_rounded),
                      onPressed: _openOwnerDashboard,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'ค้นหาสนาม…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              BookCourtQuickFilterRow(
                availableOnly: filter.availableOnly,
                bookedByMeOnly: filter.bookedByMeOnly,
                ownerOnly: filter.ownerOnly,
                locationEnabled: shared?.locationEnabled ?? false,
                radiusKm: shared?.radiusKm,
                activeFilterCount:
                    filter.activeCount + (shared?.activeCount ?? 0),
                filterSummary: _filterSummary,
                onToggleFilter: _toggleQuickFilter,
                onShowAdvancedFilter: _showAdvancedFilter,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: _loading
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  )
                : _venues.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 80),
                        child: Column(
                          children: [
                            Icon(
                              Icons.sports_tennis_rounded,
                              size: 56,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'ไม่พบสนามที่ตรงกับตัวกรอง',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    key: const PageStorageKey<String>('book_court_feed'),
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 8, bottom: 120),
                    itemCount: _venues.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _venues.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final venue = _venues[index];
                      return CourtCard(
                        venue: venue,
                        distanceKm: _distanceTo(venue),
                        onTap: () => _openVenue(venue),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  double? _distanceTo(VenueSummary venue) {
    if (_userLat == null || _userLng == null) return null;
    if (venue.lat == null || venue.lng == null) return null;
    return distanceKm(_userLat!, _userLng!, venue.lat!, venue.lng!);
  }

  static String _mapBookingError(Object e) {
    final raw = e.toString();
    if (raw.contains('TERMS_VERSION_CHANGED')) {
      return 'เงื่อนไขสนามเปลี่ยนแล้ว กรุณาลองใหม่';
    }
    if (raw.contains('SLOT_TAKEN') ||
        raw.contains('OVERLAP') ||
        raw.contains('CAPACITY')) {
      return 'ช่วงเวลานี้ถูกจองแล้ว กรุณาเลือกเวลาอื่น';
    }
    if (raw.contains('VENUE_NOT_APPROVED') || raw.contains('COURT_INACTIVE')) {
      return 'สนามนี้ไม่เปิดรับจองแล้ว';
    }
    if (raw.contains('UNAUTHORIZED')) return 'กรุณาเข้าสู่ระบบใหม่';
    return 'จองไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }
}

/// Fallback shared filter when the page is used without a hub controller
/// (e.g. standalone tests).
class _SharedFallback {
  const _SharedFallback();
  SportsDiscoveryFilter get filter => const SportsDiscoveryFilter();
}
