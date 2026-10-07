import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/shared/widgets/glass/glass_text_prompt_dialog.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';

/// Admin review page for venue owner applications and pending venues.
///
/// Both lists are loaded through admin RPCs (`list_sports_venue_owner_
/// applications`, `list_sports_venues_for_review`) that validate the caller
/// is an admin server-side, so a non-admin sees an empty state.
class AdminCourtOwnerReviewPage extends StatelessWidget {
  final BookCourtRepository repo;

  const AdminCourtOwnerReviewPage({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor,
      appBar: AppBar(
        title: const Text(
          'ตรวจสอบเจ้าของสถานที่',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        backgroundColor: NeumorphicTheme.baseColor,
        elevation: 0,
        foregroundColor: NeumorphicTheme.textPrimary,
      ),
      body: AdminCourtOwnerReviewPanel(repo: repo),
    );
  }
}

/// Body-only review surface — same data and actions as the standalone page
/// but without its own Scaffold/AppBar, so it can be embedded as a tab in
/// the "จัดการกีฬา" admin page.
class AdminCourtOwnerReviewPanel extends StatefulWidget {
  final BookCourtRepository repo;

  const AdminCourtOwnerReviewPanel({super.key, required this.repo});

  @override
  State<AdminCourtOwnerReviewPanel> createState() =>
      _AdminCourtOwnerReviewPanelState();
}

class _AdminCourtOwnerReviewPanelState
    extends State<AdminCourtOwnerReviewPanel> {
  List<VenueOwnerProfile> _applications = [];
  List<VenueSummary> _venues = [];
  List<SlipVerificationProvider> _providers = [];
  List<AdminVenueVerifyPolicy> _verifyPolicies = [];
  GlobalSlipVerificationPolicy? _globalVerifyPolicy;
  bool _globalPolicyLoading = true;
  bool _savingGlobalPolicy = false;
  bool _loading = true;

  /// Lazily loaded readiness details per venue id.
  final Map<String, Map<String, dynamic>> _venueDetails = {};
  final Set<String> _detailLoading = {};
  final Set<String> _detailErrors = {};

  String? get _adminId => AuthService.instance.currentUser?.id;

  static const _missingLabels = {
    'owner_not_approved': 'บัญชีเจ้าของยังไม่อนุมัติ',
    'name': 'ชื่อสถานที่',
    'province': 'จังหวัด',
    'district': 'อำเภอ/เขต',
    'address': 'ที่อยู่',
    'location': 'พิกัดละติจูด/ลองจิจูด',
    'timezone': 'เขตเวลา',
    'sports': 'กีฬาของสถานที่',
    'hours': 'เวลาเปิด–ปิดครบ 7 วัน',
    'amenities': 'ยืนยันสิ่งอำนวยความสะดวก',
    'terms': 'เลือกเงื่อนไขการใช้งาน',
    'courts': 'รายการที่เปิดใช้งาน',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final adminId = _adminId;
    if (adminId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.repo.listOwnerApplications(adminId),
        widget.repo.listVenuesForReview(adminId),
        widget.repo.adminListSlipProviders(adminId),
      ]);
      if (!mounted) return;
      setState(() {
        _applications = results[0] as List<VenueOwnerProfile>;
        _venues = results[1] as List<VenueSummary>;
        _providers = results[2] as List<SlipVerificationProvider>;
        _venueDetails.clear();
        _detailErrors.clear();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    // Additive: verification controls must not blank the owner-review lists
    // when their migrations have not reached the target database yet.
    await Future.wait([_loadVerifyPolicies(), _loadGlobalVerifyPolicy()]);
  }

  Future<void> _loadGlobalVerifyPolicy() async {
    final adminId = _adminId;
    if (adminId == null) return;
    setState(() => _globalPolicyLoading = true);
    try {
      final policy = await widget.repo.adminGetGlobalVerifyPolicy(adminId);
      if (mounted) setState(() => _globalVerifyPolicy = policy);
    } catch (_) {
      if (mounted) setState(() => _globalVerifyPolicy = null);
    } finally {
      if (mounted) setState(() => _globalPolicyLoading = false);
    }
  }

  Future<void> _loadVerifyPolicies() async {
    final adminId = _adminId;
    if (adminId == null) return;
    try {
      final policies = await widget.repo.adminListVenueVerifyPolicies(adminId);
      if (mounted) setState(() => _verifyPolicies = policies);
    } catch (_) {
      if (mounted) setState(() => _verifyPolicies = const []);
    }
  }

  Future<void> _reviewApplication(VenueOwnerProfile app, bool approve) async {
    final adminId = _adminId;
    if (adminId == null) return;
    final reason = approve ? null : await _askReason('เหตุผลที่ไม่อนุมัติ');
    if (!approve && reason == null) return;
    try {
      await widget.repo.reviewOwnerApplication(
        adminId,
        app.id,
        approve ? 'approved' : 'rejected',
        reason: reason,
      );
      _toast(approve ? 'อนุมัติเจ้าของสถานที่แล้ว' : 'ปฏิเสธคำขอแล้ว');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Future<void> _reviewVenue(VenueSummary venue, bool approve) async {
    final adminId = _adminId;
    if (adminId == null) return;
    final reason = approve ? null : await _askReason('เหตุผลที่ไม่อนุมัติ');
    if (!approve && reason == null) return;
    try {
      await widget.repo.reviewVenue(
        adminId,
        venue.id,
        approve ? 'approved' : 'rejected',
        reason: reason,
      );
      _toast(approve ? 'อนุมัติสถานที่แล้ว' : 'ปฏิเสธสถานที่แล้ว');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Future<void> _loadVenueDetail(String venueId) async {
    final adminId = _adminId;
    if (adminId == null || _detailLoading.contains(venueId)) return;
    setState(() {
      _detailLoading.add(venueId);
      _detailErrors.remove(venueId);
    });
    try {
      final detail = await widget.repo.getVenueAdminReviewDetail(
        adminId,
        venueId,
      );
      if (!mounted) return;
      setState(() => _venueDetails[venueId] = detail);
    } catch (_) {
      if (mounted) setState(() => _detailErrors.add(venueId));
    } finally {
      if (mounted) setState(() => _detailLoading.remove(venueId));
    }
  }

  Future<String?> _askReason(String title) {
    return GlassTextPromptDialog.show(
      context,
      title: title,
      hint: 'ระบุเหตุผล',
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                _sectionHeader(
                  'คำขอเป็นเจ้าของสถานที่ (${_applications.length})',
                ),
                if (_applications.isEmpty)
                  _empty('ไม่มีคำขอรอตรวจสอบ')
                else
                  for (final app in _applications) _buildAppCard(app),
                _sectionHeader('สถานที่รออนุมัติ (${_venues.length})'),
                if (_venues.isEmpty)
                  _empty('ไม่มีสถานที่รออนุมัติ')
                else
                  for (final venue in _venues) _buildVenueCard(venue),
                _sectionHeader(
                  'ผู้ให้บริการตรวจสลิป (${_providers.length})',
                ),
                if (_providers.isEmpty)
                  _empty('ยังไม่มีผู้ให้บริการ')
                else
                  for (final p in _providers) _buildProviderCard(p),
                _sectionHeader('ขอบเขตระบบตรวจสลิปอัตโนมัติ'),
                _buildGlobalVerifyPolicyCard(),
                _sectionHeader(
                  'นโยบายตรวจสลิปและค่าใช้จ่ายรายสถานที่ (${_verifyPolicies.length})',
                ),
                if (_verifyPolicies.isEmpty)
                  _empty('ยังไม่มีสถานที่ให้ตั้งค่า')
                else
                  for (final v in _verifyPolicies)
                    _buildVerifyPolicyCard(v),
              ],
            ),
          );
  }

  Widget _buildAppCard(VenueOwnerProfile app) {
    return NeumorphicContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      depth: 4,
      blur: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            app.businessName.isNotEmpty ? app.businessName : app.contactName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'ผู้ติดต่อ: ${[app.contactName, if (app.contactPhone.isNotEmpty) app.contactPhone].join(' • ')}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          if (app.contactEmail?.isNotEmpty == true)
            Text(
              app.contactEmail!,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => _reviewApplication(app, false),
                child: const Text(
                  'ปฏิเสธ',
                  style: TextStyle(color: Colors.red),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                ),
                onPressed: () => _reviewApplication(app, true),
                child: const Text('อนุมัติ'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVenueCard(VenueSummary venue) {
    return NeumorphicContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      depth: 4,
      blur: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            venue.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            [venue.district, venue.province].whereType<String>().join(', '),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              dense: true,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title: Text(
                'ความพร้อมก่อนอนุมัติ',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onExpansionChanged: (expanded) {
                if (expanded &&
                    !_venueDetails.containsKey(venue.id) &&
                    !_detailErrors.contains(venue.id)) {
                  _loadVenueDetail(venue.id);
                }
              },
              children: [_buildVenueReadiness(venue)],
            ),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => _reviewVenue(venue, false),
                child: const Text(
                  'ปฏิเสธ',
                  style: TextStyle(color: Colors.red),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                ),
                onPressed: () => _reviewVenue(venue, true),
                child: const Text('อนุมัติ'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVenueReadiness(VenueSummary venue) {
    if (_detailLoading.contains(venue.id)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_detailErrors.contains(venue.id)) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'โหลดความพร้อมไม่สำเร็จ',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ),
          TextButton(
            onPressed: () => _loadVenueDetail(venue.id),
            child: const Text('ลองใหม่'),
          ),
        ],
      );
    }
    final detail = _venueDetails[venue.id];
    if (detail == null) return const SizedBox.shrink();

    final missing = (detail['setup_missing'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    final business = detail['owner_business_name']?.toString() ?? '';
    final courtCount = (detail['court_count'] as num?)?.toInt() ?? 0;
    final activeCourts = (detail['active_court_count'] as num?)?.toInt() ?? 0;
    final hoursCount = (detail['hours_count'] as num?)?.toInt() ?? 0;
    final amenitiesConfirmed = detail['amenities_confirmed'] == true;
    final platformTerms = detail['uses_platform_terms'] == true;
    final termsVersion = (detail['terms_version'] as num?)?.toInt();
    final sportsCount = (detail['sports'] as List? ?? const []).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (business.isNotEmpty)
          Text(
            'เจ้าของ: $business',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        const SizedBox(height: 4),
        Text(
          'กีฬา $sportsCount · รายการ $activeCourts/$courtCount เปิดใช้งาน · '
          'เวลา $hoursCount/7 วัน · '
          'สิ่งอำนวยความสะดวก${amenitiesConfirmed ? 'ยืนยันแล้ว' : 'ยังไม่ยืนยัน'} · '
          'เงื่อนไข${termsVersion != null
              ? ' v$termsVersion'
              : platformTerms
              ? 'แพลตฟอร์ม'
              : '-'}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 4),
        if (missing.isEmpty)
          Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                'ตั้งค่าครบ พร้อมอนุมัติ',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          )
        else
          Text(
            'ยังขาด: ${missing.map((m) => _missingLabels[m] ?? m).join(', ')}',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
          ),
      ],
    );
  }

  Future<void> _toggleProvider(
    SlipVerificationProvider p,
    bool enabled,
  ) async {
    final adminId = _adminId;
    if (adminId == null) return;
    try {
      await widget.repo.adminUpsertSlipProvider(
        adminId: adminId,
        code: p.code,
        displayName: p.displayName,
        isEnabled: enabled,
      );
      _toast(enabled ? 'เปิดผู้ให้บริการแล้ว' : 'ปิดผู้ให้บริการแล้ว');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Future<void> _editProvider(SlipVerificationProvider p) async {
    final adminId = _adminId;
    if (adminId == null) return;
    final endpoint = TextEditingController(text: p.endpointUrl ?? '');
    final keyRef = TextEditingController();
    final cost = TextEditingController(
      text: p.costPerCheck.toStringAsFixed(2),
    );
    final timeout = TextEditingController(
      text: '${p.verifyTimeoutMinutes}',
    );
    final priority = TextEditingController(text: '${p.priority}');
    final notes = TextEditingController(text: p.notes ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ตั้งค่า ${p.displayName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: endpoint,
                decoration: const InputDecoration(
                  labelText: 'Endpoint URL',
                ),
              ),
              TextField(
                controller: keyRef,
                decoration: InputDecoration(
                  labelText: 'Secret-store key ref',
                  helperText: p.hasApiKey
                      ? 'เว้นว่างเพื่อคงค่าเดิม'
                      : 'ชื่อ env บนเซิร์ฟเวอร์ เช่น SLIPOK',
                ),
              ),
              TextField(
                controller: cost,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ค่าใช้จ่ายต่อครั้ง',
                ),
              ),
              TextField(
                controller: timeout,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Timeout (นาที)',
                ),
              ),
              TextField(
                controller: priority,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ลำดับความสำคัญ (น้อย=ก่อน)',
                ),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'หมายเหตุ'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await widget.repo.adminUpsertSlipProvider(
        adminId: adminId,
        code: p.code,
        displayName: p.displayName,
        endpointUrl: endpoint.text.trim().isEmpty
            ? null
            : endpoint.text.trim(),
        apiKeyRef: keyRef.text.trim().isEmpty ? null : keyRef.text.trim(),
        costPerCheck: double.tryParse(cost.text.trim()),
        verifyTimeoutMinutes: int.tryParse(timeout.text.trim()),
        priority: int.tryParse(priority.text.trim()),
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      );
      _toast('บันทึกผู้ให้บริการแล้ว');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Widget _buildProviderCard(SlipVerificationProvider p) {
    return NeumorphicContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      depth: 4,
      blur: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${p.displayName} (${p.code})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Switch(
                value: p.isEnabled,
                onChanged: p.adapterKnown
                    ? (v) => _toggleProvider(p, v)
                    : null,
              ),
            ],
          ),
          Text(
            [
              'priority ${p.priority}',
              '฿${p.costPerCheck.toStringAsFixed(2)}/ครั้ง',
              'timeout ${p.verifyTimeoutMinutes} นาที',
              p.hasApiKey ? 'มี API key' : 'ยังไม่ตั้ง API key',
            ].join(' · '),
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
          if (!p.adapterKnown)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 15,
                    color: Colors.orange.shade800,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'ยังไม่มี adapter บนเซิร์ฟเวอร์สำหรับผู้ให้บริการนี้'
                      ' — เปิดใช้ไม่ได้จนกว่าจะ deploy adapter',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (p.notes?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                p.notes!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _editProvider(p),
              child: const Text('แก้ไข'),
            ),
          ),
        ],
      ),
    );
  }

  static const _globalScopeLabels = {
    'disabled': 'ปิดการตรวจอัตโนมัติ',
    'whitelist': 'เฉพาะสถานที่ใน allowlist',
    'all': 'ทุกสถานที่ที่อนุมัติ',
  };

  static const _bearerLabels = {
    'platform': 'แพลตฟอร์มรับภาระ',
    'owner': 'เจ้าของรับภาระ',
  };

  Future<void> _setGlobalVerifyScope(String scope) async {
    final adminId = _adminId;
    final current = _globalVerifyPolicy;
    if (adminId == null || current == null || _savingGlobalPolicy) return;
    if (scope == current.scope) return;
    if (scope != 'disabled') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ยืนยันขอบเขตตรวจสลิป'),
          content: Text(
            scope == 'all'
                ? 'จะอนุญาตให้ทุกสถานที่ที่อนุมัติและเปิด auto_verify ใช้ผู้ให้บริการที่เปิดอยู่ '
                      'ขณะนี้มี ${current.approvedVenueCount} สถานที่ที่อนุมัติ '
                      'และผู้ให้บริการที่ตั้งค่า ${current.configuredProviderCount} รายการ '
                      'อาจเกิดค่าใช้จ่ายตาม quota ของแต่ละสถานที่'
                : 'จะอนุญาตเฉพาะสถานที่ที่เปิด allowlist และเจ้าของเลือก auto_verify '
                      'ขณะนี้มี ${current.allowlistedVenueCount} สถานที่ใน allowlist '
                      'และผู้ให้บริการที่ตั้งค่า ${current.configuredProviderCount} รายการ',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ยืนยัน'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _savingGlobalPolicy = true);
    try {
      await widget.repo.adminSetGlobalVerifyScope(
        adminId: adminId,
        scope: scope,
      );
      _toast('บันทึกขอบเขตตรวจสลิปแล้ว');
      await Future.wait([_loadGlobalVerifyPolicy(), _loadVerifyPolicies()]);
    } catch (e) {
      _toast(_mapError(e));
    } finally {
      if (mounted) setState(() => _savingGlobalPolicy = false);
    }
  }

  Widget _buildGlobalVerifyPolicyCard() {
    final policy = _globalVerifyPolicy;
    return NeumorphicContainer(
      key: const ValueKey('admin-global-verify-policy'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      depth: 4,
      blur: 8,
      child: _globalPolicyLoading
          ? const Center(child: CircularProgressIndicator())
          : policy == null
          ? Row(
              children: [
                const Expanded(child: Text('โหลดการตั้งค่าระบบไม่สำเร็จ')),
                TextButton(
                  onPressed: _loadGlobalVerifyPolicy,
                  child: const Text('ลองใหม่'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  key: const ValueKey('admin-global-verify-scope'),
                  initialValue: policy.scope,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'ขอบเขตทั่วระบบ',
                    helperText:
                        'ปิดเป็นค่าเริ่มต้น; allowlist และ quota รายสถานที่ยังมีผล',
                  ),
                  items: [
                    for (final entry in _globalScopeLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: _savingGlobalPolicy
                      ? null
                      : (value) {
                          if (value != null) _setGlobalVerifyScope(value);
                        },
                ),
                const SizedBox(height: 6),
                Text(
                  '${policy.approvedVenueCount} สถานที่อนุมัติ · '
                  '${policy.allowlistedVenueCount} ใน allowlist · '
                  '${policy.configuredProviderCount} provider พร้อม config',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
                if (policy.configuredProviderCount == 0 &&
                    policy.scope != 'disabled')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'ยังไม่มี provider ที่ตั้ง endpoint และ secret reference ครบ — ระบบจะส่งให้เจ้าของตรวจแทน',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _setVenueAllowlist(
    AdminVenueVerifyPolicy venue,
    bool allowlisted,
  ) async {
    final adminId = _adminId;
    if (adminId == null) return;
    try {
      await widget.repo.adminSetVenueVerifyControls(
        adminId: adminId,
        venueId: venue.venueId,
        isAllowlisted: allowlisted,
      );
      _toast(
        allowlisted
            ? 'เพิ่ม ${venue.name} ใน allowlist แล้ว'
            : 'นำ ${venue.name} ออกจาก allowlist แล้ว',
      );
      await _loadVerifyPolicies();
      await _loadGlobalVerifyPolicy();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  /// Admin-only per-venue allowlist and cost policy.
  Widget _buildVerifyPolicyCard(AdminVenueVerifyPolicy v) {
    final quotaLabel = v.monthlyQuota == null
        ? 'ไม่จำกัดโควตา'
        : 'ใช้/จอง ${v.callsThisMonth}/${v.monthlyQuota} ครั้งเดือนนี้';
    final scopeLabel = switch (v.globalScope) {
      'all' => v.status == 'approved' ? 'อยู่ใน scope ทั่วระบบ' : 'รออนุมัติสถานที่',
      'whitelist' => v.isAllowlisted ? 'อยู่ใน allowlist' : 'ไม่อยู่ใน allowlist',
      _ => 'ปิดทั่วระบบ',
    };
    return NeumorphicContainer(
      key: ValueKey('admin-verify-policy-${v.venueId}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      depth: 4,
      blur: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  v.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: v.isAutoVerifyAllowed
                      ? Colors.green.shade50
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  v.isAutoVerifyAllowed ? 'ตรวจอัตโนมัติได้' : scopeLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: v.isAutoVerifyAllowed
                        ? Colors.green.shade800
                        : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          SwitchListTile.adaptive(
            key: ValueKey('admin-verify-allowlist-${v.venueId}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('อนุญาต venue นี้ใน allowlist'),
            subtitle: Text(
              v.globalScope == 'all'
                  ? 'ขณะนี้ scope เปิดทุกสถานที่ที่อนุมัติ; ค่านี้ใช้เมื่อเปลี่ยนเป็น allowlist'
                  : 'มีผลเมื่อขอบเขตทั่วระบบเป็น allowlist',
              style: const TextStyle(fontSize: 11.5),
            ),
            value: v.isAllowlisted,
            onChanged: (value) => _setVenueAllowlist(v, value),
          ),
          Text(
            [
              _bearerLabels[v.costBearer] ?? v.costBearer,
              quotaLabel,
              v.verifyTimeoutMinutes == null
                  ? 'timeout ตามผู้ให้บริการ'
                  : 'timeout ${v.verifyTimeoutMinutes} นาที',
            ].join(' · '),
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
          Text(
            'ประมาณการค่าใช้จ่ายเดือนนี้ ฿${v.costEstimateThisMonth.toStringAsFixed(2)}'
            '${v.pendingCallsThisMonth > 0 ? ' · ${v.pendingCallsThisMonth} รายการกำลังตรวจ' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (v.isScopeEnabled && v.configuredProviderCount == 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'ยังไม่มี provider ที่เปิดและตั้ง endpoint/secret reference ครบ — สลิปจะตกไปให้เจ้าของตรวจแทน',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            )
          else if (v.isQuotaExhausted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'โควตาเดือนนี้ใช้ครบแล้ว — สลิปจะตกไปให้เจ้าของตรวจแทน',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            )
          else if (v.isScopeEnabled && !v.hasEvidencePolicy)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'สถานที่นี้ยังไม่เปิดนโยบายหลักฐาน — เจ้าของต้องตั้งค่าก่อนจึงใช้ได้',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _editVenueVerifyPolicy(v),
              child: const Text('ตั้งค่าค่าใช้จ่าย'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editVenueVerifyPolicy(AdminVenueVerifyPolicy v) async {
    final adminId = _adminId;
    if (adminId == null) return;
    var bearer = v.costBearer;
    final quota = TextEditingController(
      text: v.monthlyQuota?.toString() ?? '',
    );
    final timeout = TextEditingController(
      text: v.verifyTimeoutMinutes?.toString() ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('ตรวจสลิปอัตโนมัติ — ${v.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'การเปิดตรวจอัตโนมัติควบคุมที่ระดับระบบและ allowlist แยกจากค่าใช้จ่ายของสถานที่นี้',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const ValueKey('admin-verify-bearer'),
                  initialValue: bearer,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'ผู้รับภาระค่าใช้จ่าย',
                  ),
                  items: [
                    for (final entry in _bearerLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => bearer = value);
                  },
                ),
                TextField(
                  key: const ValueKey('admin-verify-quota'),
                  controller: quota,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'โควตาต่อเดือน (ครั้ง)',
                    helperText: 'เว้นว่าง = ไม่จำกัด',
                  ),
                ),
                TextField(
                  key: const ValueKey('admin-verify-timeout'),
                  controller: timeout,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'หมดเวลาเรียกผู้ให้บริการ (นาที)',
                    helperText: 'เว้นว่าง = ใช้ค่าของผู้ให้บริการ',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              key: const ValueKey('admin-verify-save'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final quotaText = quota.text.trim();
    final timeoutText = timeout.text.trim();
    final quotaValue = quotaText.isEmpty ? null : int.tryParse(quotaText);
    final timeoutValue = timeoutText.isEmpty
        ? null
        : int.tryParse(timeoutText);
    if ((quotaText.isNotEmpty && quotaValue == null) ||
        (timeoutText.isNotEmpty && timeoutValue == null)) {
      _toast('โควตาและเวลาหมดต้องเป็นตัวเลข');
      return;
    }
    try {
      await widget.repo.adminSetVenueVerifyControls(
        adminId: adminId,
        venueId: v.venueId,
        isAllowlisted: v.isAllowlisted,
        costBearer: bearer,
        monthlyQuota: quotaValue,
        verifyTimeoutMinutes: timeoutValue,
        clearQuota: quotaText.isEmpty,
        clearTimeout: timeoutText.isEmpty,
      );
      _toast('บันทึกนโยบายตรวจสลิปของ ${v.name} แล้ว');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    ),
  );

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
    ),
  );

  static String _mapError(Object e) {
    final raw = e.toString();
    if (raw.contains('UNAUTHORIZED') || raw.contains('NOT_ADMIN')) {
      return 'เฉพาะผู้ดูแลระบบเท่านั้น';
    }
    if (raw.contains('VENUE_NOT_READY')) {
      return 'สถานที่ยังตั้งค่าไม่ครบ — ตรวจรายการความพร้อมก่อนอนุมัติ';
    }
    if (raw.contains('REASON_REQUIRED')) {
      return 'กรุณาระบุเหตุผล';
    }
    if (raw.contains('INVALID_STATUS')) {
      return 'สถานะสถานที่ไม่อนุญาตให้ทำรายการนี้';
    }
    if (raw.contains('ADAPTER_NOT_AVAILABLE')) {
      return 'ยังไม่มี adapter สำหรับผู้ให้บริการนี้บนเซิร์ฟเวอร์'
          ' — deploy adapter ก่อนเปิดใช้งาน';
    }
    if (raw.contains('INVALID_PROVIDER') ||
        raw.contains('INVALID_VERIFY_POLICY')) {
      return 'ค่าที่ตั้งไม่ถูกต้อง กรุณาตรวจสอบอีกครั้ง';
    }
    if (raw.contains('VENUE_NOT_FOUND')) {
      return 'ไม่พบสถานที่นี้ กรุณารีเฟรช';
    }
    return 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }
}
