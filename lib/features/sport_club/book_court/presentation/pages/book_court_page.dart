import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_bar_controller.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_controller.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_sport_catalog.dart';
import 'package:sheserved/features/sport_club/shared/domain/sports_discovery_filter.dart';
import 'package:sheserved/features/sport_club/shared/presentation/widgets/shared_sport_filter_bar.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

import '../../application/book_court_booking_service.dart';
import '../../application/book_court_query.dart';
import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';
import '../../domain/book_court_filter.dart';
import '../../domain/venue_local_time.dart';
import '../widgets/book_court_filter_sheet.dart';
import '../widgets/booking_group_sheet.dart';
import '../widgets/book_court_quick_filter_row.dart';
import '../widgets/court_booking_dialog.dart';
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

  /// Shell-owned shared sport catalog + bar state (plan 21.7.13). Present
  /// when embedded in [SportsHubPage]; the shared chips row is rendered once
  /// by the shell overlay, so this page then only reserves its height.
  final SportsHubSportCatalog? sportCatalog;
  final SportsHubBarController? sportBar;

  const BookCourtPage({
    super.key,
    this.hubController,
    this.sportCatalog,
    this.sportBar,
  });

  @override
  State<BookCourtPage> createState() => _BookCourtPageState();
}

class _BookCourtPageState extends State<BookCourtPage> {
  late final FitnessBuddiesRepository _buddiesRepo;
  late final BookCourtRepository _repo;
  late final BookCourtQuery _query;
  late final BookCourtBookingService _booking;

  final _scrollController = ScrollController();

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
      quoteVenueSlotPrices: _repo.quoteVenuePricesForLocalSlot,
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
    _scrollController.dispose();
    _hub?.removeListener(_onHubChanged);
    super.dispose();
  }

  /// Shared filter changes (sport/location/query) re-run discovery with a
  /// new request id so superseded responses are discarded.
  void _onHubChanged() {
    if (!mounted) return;
    _reload();
  }

  Future<void> _init() async {
    // Embedded pages share the shell's single ranked catalog (21.7.13);
    // standalone usage keeps its own load.
    if (widget.sportCatalog == null) {
      try {
        final sports = await _buddiesRepo.getApprovedSports(userId: _userId);
        if (!mounted) return;
        setState(() => _sports = sports);
      } catch (_) {
        // Empty sport row is fine; the feed still renders.
      }
    }
    await _reload();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    widget.sportBar?.reportScroll(0, _scrollController.position.pixels);
    if (_loading || _isLoadingMore || !_hasMore) return;
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
        setState(() {
          _venues = [];
          _loading = false;
        });
        if (e.message == 'PRICE_FILTER_REQUIRES_SLOT') {
          _toast('เลือกวัน เวลาเริ่ม และระยะเวลาเพื่อกรองราคา');
        } else if (e.message == 'PRICE_FILTER_CROSSES_DAY') {
          _toast('ช่วงราคาและระยะเวลาต้องอยู่ภายในวันเดียวกัน');
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        if ((_filter.minPrice != null || _filter.maxPrice != null) &&
            error.toString().contains('PGRST202')) {
          _toast('ระบบฐานข้อมูลยังไม่พร้อม กรุณาอัปเดต Supabase migrations');
        }
      }
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
    hub.updateShared(hub.shared.withSportId(selected ? id : null));
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
        hub.updateCourts(filter.copyWith(availableOnly: !filter.availableOnly));
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
      arguments: {'returnAfterLogin': true},
    );
    return _userId != null;
  }

  Future<void> _showAdvancedFilter() async {
    final hub = _hub;
    if (hub == null) return;
    final result = await BookCourtFilterSheet.show(
      context,
      current: _filter,
      currentQuery: hub.shared.query,
      currentProvince: hub.shared.province,
      currentDistrict: hub.shared.district,
    );
    if (result == null || !mounted) return;
    hub.updateShared(
      hub.shared.copyWith(
        query: result.query,
        province: result.province,
        clearProvince: result.province == null,
        district: result.district,
        clearDistrict: result.district == null,
      ),
    );
    hub.updateCourts(result.filter);
  }

  // =============== Detail + booking flow ===============

  Future<void> _openVenue(VenueSummary venue) async {
    // Real user detail-opens feed the shared usage ranking (21.7.13).
    widget.sportCatalog?.recordDetailOpen(
      domain: 'courts',
      entityId: venue.id,
      sportIds: venue.sportIds,
    );
    final userId = _userId;
    bool? canManageAvailability;
    if (userId != null) {
      try {
        canManageAvailability = (await _repo.listMyManagedVenueIds(
          userId,
        )).contains(venue.id);
      } catch (_) {
        canManageAvailability = false;
      }
    }
    if (!mounted) return;
    await CourtDetailSheet.show(
      context,
      venue: venue,
      repo: _repo,
      sharedSportId: _hub?.shared.sportId,
      userId: userId,
      canManageAvailability: canManageAvailability == true,
      onBookCourt: (court, {initialDate, initialSlotStart}) => _startBooking(
        venue,
        court,
        initialDate: initialDate,
        initialSlotStart: initialSlotStart,
        verifiedCanManageAvailability: canManageAvailability,
      ),
      onWriteReview: _userId == null
          ? null
          : () => _openMyBookings(reviewVenueId: venue.id),
      onOpenMyBookings: () => _openMyBookings(),
    );
  }

  /// Booking flow: pick slot -> accept venue terms -> trusted RPC create.
  /// On `TERMS_VERSION_CHANGED` the fresh terms are fetched and the consent
  /// dialog is shown once more with the new version.
  Future<void> _startBooking(
    VenueSummary venue,
    VenueCourt court, {
    DateTime? initialDate,
    DateTime? initialSlotStart,
    bool? verifiedCanManageAvailability,
  }) async {
    final userId = _userId;
    if (userId == null) {
      await _requireLogin();
      if (_userId == null) return;
    }
    if (!mounted) return;
    final actorUserId = _userId;
    if (actorUserId == null) return;
    var canManageAvailability = verifiedCanManageAvailability ?? false;
    if (verifiedCanManageAvailability == null) {
      try {
        canManageAvailability = (await _repo.listMyManagedVenueIds(
          actorUserId,
        )).contains(venue.id);
      } catch (_) {}
    }
    if (!mounted) return;

    final ranges = await CourtBookingDialog.show(
      context,
      court: court,
      venueName: venue.name,
      timezone: venue.timezone,
      venueUnitLabel: venue.venueUnitLabel,
      loadAvailability: _repo.getCourtAvailability,
      quotePrice: _repo.quoteCourtPrice,
      initialDate: initialDate ?? _filter.date,
      initialSlotStart: initialSlotStart,
      canManageAvailability: canManageAvailability,
      manageAvailability: (courtId, suspend, selectedRanges) =>
          _repo.manageCourtAvailability(
            userId: actorUserId,
            courtId: courtId,
            suspend: suspend,
            ranges: selectedRanges,
          ),
    );
    if (ranges == null || ranges.isEmpty || !mounted) return;

    // Evidence-gated courts take the atomic group path; when the venue
    // has no policy (surface == null) the legacy per-slot flow is
    // completely unchanged.
    CourtEvidenceSurface? evidenceSurface;
    try {
      evidenceSurface = await _repo.getCourtEvidenceSurface(court.id);
    } catch (_) {}
    if (!mounted) return;

    final slots = [
      for (final range in ranges)
        (
          start: range.start,
          end: range.end,
          idempotencyKey: const Uuid().v4(),
          priceScheduleVersion: range.priceQuote.priceScheduleVersion,
        ),
    ];
    var completed = 0;
    try {
      var terms = await _repo.getActiveVenueTerms(venue.id);
      for (var attempt = 0; attempt < 2; attempt++) {
        if (!mounted) return;
        final accepted = await CourtUsageTermsDialog.show(
          context,
          terms: terms,
          venueName: venue.name,
          acceptLabel: evidenceSurface != null
              ? 'ยอมรับและดำเนินการต่อ'
              : slots.length > 1
              ? 'ยอมรับและจอง ${slots.length - completed} ช่วง'
              : 'ยอมรับและจอง',
        );
        if (!mounted) return;
        if (accepted == null) {
          if (completed > 0) {
            await _showBookingResults(
              court,
              ranges,
              completed,
              'ยกเลิกการจองช่วงที่เหลือ',
            );
          }
          return;
        }
        if (evidenceSurface != null) {
          // Atomic group create — every selected range succeeds or none do.
          final groupId = await _repo.createBookingGroup(
            userId: actorUserId,
            items: [
              for (final range in ranges)
                (
                  courtId: court.id,
                  startsAt: range.start,
                  endsAt: range.end,
                  priceScheduleVersion:
                      range.priceQuote.priceScheduleVersion,
                ),
            ],
            termsVersion: accepted.version,
            idempotencyKey: const Uuid().v4(),
          );
          if (!mounted) return;
          await _openGroupSheet(groupId);
          return;
        }
        final result = await _booking.bookSlots(
          userId: _userId,
          court: court,
          slots: slots.sublist(completed),
          termsVersion: accepted.version,
        );
        completed += result.completed;
        if (!mounted) return;
        final error = result.error;
        if (error == null) {
          if (ranges.length == 1) {
            _toast(
              court.approvalMode == BookingApprovalMode.instant
                  ? 'จองสำเร็จ'
                  : 'ส่งคำขอจองแล้ว รอเจ้าของอนุมัติ',
            );
          } else {
            await _showBookingResults(court, ranges, completed, null);
          }
          return;
        }
        if (error.toString().contains('TERMS_VERSION_CHANGED') &&
            attempt == 0) {
          terms = await _repo.getActiveVenueTerms(venue.id);
          continue;
        }
        await _showBookingResults(
          court,
          ranges,
          completed,
          _mapBookingError(error, timezone: venue.timezone),
        );
        return;
      }
    } catch (error) {
      if (mounted) {
        await _showBookingResults(
          court,
          ranges,
          completed,
          _mapBookingError(error, timezone: venue.timezone),
        );
      }
    }
  }

  /// Opens the evidence/hold detail sheet for a freshly created or
  /// existing booking group. The group is looked up from the booker
  /// listing so countdowns always run on the server clock.
  Future<void> _openGroupSheet(String groupId) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final res = await _repo.listMyBookingGroups(userId);
      if (!mounted) return;
      final group = res.groups
          .where((g) => g.id == groupId)
          .cast<VenueBookingGroup?>()
          .firstOrNull;
      if (group == null) {
        _toast('สร้างการจองแล้ว — ดูรายละเอียดในหน้าการจองของฉัน');
        return;
      }
      await BookingGroupSheet.show(
        context,
        repo: _repo,
        userId: userId,
        group: group,
        serverNow: res.serverNow,
      );
    } catch (_) {
      if (mounted) {
        _toast('สร้างการจองแล้ว — ดูรายละเอียดในหน้าการจองของฉัน');
      }
    }
  }

  Future<void> _showBookingResults(
    VenueCourt court,
    List<CourtBookingSelection> ranges,
    int completed,
    String? error,
  ) {
    String time(DateTime value) =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return GlassDialog.show<void>(
      context: context,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'สำเร็จ $completed/${ranges.length} รายการ',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              LitGlassSurface.frosted(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < ranges.length; i++)
                        Text(
                          '${time(ranges[i].start)}–${time(ranges[i].end)}: ${i < completed
                              ? court.approvalMode == BookingApprovalMode.instant
                                    ? 'จองสำเร็จ'
                                    : 'รอเจ้าของอนุมัติ'
                              : 'ยังไม่ยืนยันการจอง'}',
                        ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(error),
                      ],
                      if (completed < ranges.length) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'รายการที่สำเร็จยังคงอยู่ หากการเชื่อมต่อขัดข้อง กรุณาตรวจสอบการจองของฉันก่อนจองซ้ำ',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GlassActionButton(
                label: 'ปิด',
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMyBookings({String? reviewVenueId}) async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CourtMyBookingsPage(repo: _repo)),
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
        contactPhone: result.contactPhone,
        contactEmail: result.contactEmail,
      );
      if (!mounted) return;
      _toast('ส่งใบสมัครเจ้าของสถานที่แล้ว รอการอนุมัติ');
    } catch (e) {
      _toast(_mapOwnerApplicationError(e));
    }
  }

  static String _mapOwnerApplicationError(Object e) {
    final raw = e.toString();
    if (raw.contains('APPLICATION_PENDING')) {
      return 'มีใบสมัครที่รอการอนุมัติอยู่แล้ว';
    }
    if (raw.contains('ALREADY_APPROVED')) {
      return 'บัญชีนี้เป็นเจ้าของสถานที่ที่อนุมัติแล้ว';
    }
    if (raw.contains('OWNER_SUSPENDED')) {
      return 'บัญชีเจ้าของถูกระงับ กรุณาติดต่อทีมงาน';
    }
    if (raw.contains('INVALID_APPLICATION')) {
      return 'กรุณากรอกข้อมูลให้ครบถ้วน';
    }
    if (raw.contains('UNAUTHORIZED')) return 'กรุณาเข้าสู่ระบบใหม่';
    return 'ส่งใบสมัครไม่สำเร็จ กรุณาลองใหม่';
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
    final query = shared?.query.trim() ?? '';
    if (query.isNotEmpty) parts.add('ค้นหา: $query');
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
            bottom: 120,
            child: FloatingActionButton.extended(
              heroTag: 'book_court_register_venue',
              tooltip: 'ลงทะเบียนสถานที่',
              onPressed: _openOwnerRegistration,
              icon: const Icon(Icons.storefront_rounded),
              label: const Text('ลงทะเบียนสถานที่'),
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
              if (widget.sportBar != null)
                // The shared chips row is the shell's overlay; this spacer
                // keeps the quick filters at their usual position without
                // changing the viewport when the bar collapses.
                const SizedBox(height: SportsHubBarController.barHeight - 8)
              else
                SharedSportFilterBar(
                  sports: _sports,
                  selectedSportId: shared?.sportId,
                  onSportSelected: _onSportSelected,
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
              if (filter.ownerOnly) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'การจองของฉัน',
                        icon: const Icon(Icons.event_note_rounded),
                        onPressed: _openMyBookings,
                      ),
                      IconButton(
                        tooltip: 'จัดการสถานที่ของฉัน',
                        icon: const Icon(Icons.storefront_rounded),
                        onPressed: _openOwnerDashboard,
                      ),
                    ],
                  ),
                ),
              ],
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
                              'ไม่พบสถานที่ที่ตรงกับตัวกรอง',
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

  static String _mapBookingError(Object e, {String? timezone}) {
    final raw = e.toString();
    if (raw.contains('BOOKING_NOT_OPEN_YET')) {
      // The RPC carries the opensAt instant in the PostgREST detail —
      // show it venue-local when available, else a generic fallback.
      final opensAt = bookingReleaseOpensAt(e);
      if (opensAt != null && timezone != null) {
        return 'ช่วงเวลานี้ยังไม่เปิดจอง — เปิดรับจอง '
            '${VenueLocalTime.formatInstantWall(opensAt, timezone)}';
      }
      return 'ช่วงเวลานี้ยังไม่เปิดจอง กรุณาลองใหม่ภายหลัง';
    }
    if (raw.contains('PLATFORM_TERMS_NOT_CONFIGURED')) {
      return 'สถานที่ยังไม่มีเงื่อนไขมาตรฐาน กรุณาติดต่อเจ้าของสถานที่หรือกลับมาลองใหม่ภายหลัง';
    }
    if (raw.contains('TERMS_VERSION_CHANGED')) {
      return 'เงื่อนไขของสถานที่เปลี่ยนแล้ว กรุณาลองใหม่';
    }
    if (raw.contains('PRICE_CHANGED')) {
      return 'ราคาของสถานที่เปลี่ยนแล้ว กรุณาเลือกเวลาใหม่เพื่อตรวจสอบราคา';
    }
    if (raw.contains('PRICE_VERSION_REQUIRED')) {
      return 'กรุณาอัปเดตแอปก่อนจองสถานที่ที่กำหนดราคาแยกช่วงเวลา';
    }
    if (raw.contains('PRICE_NOT_CONFIGURED')) {
      return 'สถานที่ยังไม่ได้กำหนดราคาในช่วงเวลานี้';
    }
    if (raw.contains('SLOT_TAKEN') ||
        raw.contains('OVERLAP') ||
        raw.contains('CAPACITY')) {
      return 'ช่วงเวลานี้ถูกจองแล้ว กรุณาเลือกเวลาอื่น';
    }
    if (raw.contains('VENUE_NOT_APPROVED') || raw.contains('COURT_INACTIVE')) {
      return 'สถานที่นี้ไม่เปิดรับจองแล้ว';
    }
    if (raw.contains('PGRST202') ||
        raw.contains('PGRST203') ||
        raw.contains('PGRST204')) {
      return 'ระบบจองยังไม่พร้อม กรุณาอัปเดต Supabase migrations แล้วลองใหม่';
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
