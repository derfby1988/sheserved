import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../../config/app_config.dart';
import '../../../../../../services/auth_service.dart';
import '../../../../../../services/map_config_service.dart';
import '../../../../../../services/platform_service.dart';
import '../../../../../../shared/map/map_controller.dart';
import '../../../../../../shared/map/map_types.dart';
import '../../../../../../shared/widgets/image_upload_field.dart';
import '../../../../../../core/constants/app_colors.dart';
import '../../../../admin/models/map_provider_config.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';
import '../../../find_buddies/domain/models/sport_skill_level.dart';
import '../../../find_buddies/presentation/widgets/cost_editors.dart';
import '../../../find_buddies/presentation/widgets/position_lineup.dart';
import '../../../find_buddies/presentation/widgets/skill_level_chips.dart';
import '../../../find_buddies/presentation/widgets/venue_location_picker.dart';
import '../../../../../../shared/widgets/thai_address_picker/thai_address_picker.dart';
import '../../../../../../shared/widgets/neumorphic/neumorphic.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage>
    with AutomaticKeepAliveClientMixin {
  late final FitnessBuddiesRepository _repo;
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _coverImageUrl;
  String? _venuePhotoUrl;
  ThaiAddress? _selectedAddress;
  String? _sportId;
  String _genderPreference = 'any';
  bool _requiresOwnerApproval = false;
  bool _ownerAutoJoin = true;
  double? _lat;
  double? _lng;
  bool _isGettingLocation = false;
  bool _submitting = false;
  bool _isGeocoding = false;
  List<Map<String, dynamic>> _sports = [];
  bool _didReadInitialArgs = false;
  bool _isSportsLoading = true;
  bool _allowPop = false;
  bool _sportsLoadFailed = false;
  List<String> _recentGroupNames = [];
  bool _showMembershipSection = true;
  bool _showImageSection = false;
  bool _showSettingsSection = false;
  bool _showSkillSection = false;
  bool _showFieldSection = false;
  bool _showCostsSection = false;
  // Phase 9.1: draft cost standards, written to DB after the group exists.
  List<Map<String, dynamic>> _groupFeeDrafts = [];
  List<Map<String, dynamic>> _roundExpenseDrafts = [];
  // Phase 16: Sport Skill Levels
  List<String> _targetSkillLevels = ['all'];
  final _skillNoteCtrl = TextEditingController();
  // Phase 15: draft player positions on field
  List<Map<String, dynamic>> _positionDrafts = [];
  SheservedMapController? _mapController;
  bool _mapLoadLogged = false;
  // Phase 3 (map provider rollout): resolved provider config for group_create.
  MapConfigSnapshot? _mapSnapshot;
  final _searchPlaceCtrl = TextEditingController();

  bool _isSearchingPlace = false;
  List<Map<String, dynamic>> _placeSearchResults = [];
  String? _placeSearchMessage;
  int _placeSearchRequestId = 0;

  String? _customFieldLayout;

  Map<String, dynamic>? get _selectedSportData {
    if (_sportId == null) return null;
    return _sports.cast<Map<String, dynamic>?>().firstWhere(
      (s) => s?['id']?.toString() == _sportId,
      orElse: () => null,
    );
  }

  String? get _fieldLayout {
    if (_customFieldLayout != null) return _customFieldLayout;
    final s = _selectedSportData;
    final layout = s?['field_layout']?.toString();
    if (layout == 'single' || layout == 'double') return layout;
    return null;
  }

  FieldStyle get _fieldStyle =>
      FieldStyle.fromJson(_selectedSportData?['field_style']);

  bool _hasUnsavedChanges() {
    return _nameCtrl.text.trim().isNotEmpty ||
        _descCtrl.text.trim().isNotEmpty ||
        _searchPlaceCtrl.text.trim().isNotEmpty ||
        _sportId != null ||
        _coverImageUrl != null ||
        _venuePhotoUrl != null ||
        _selectedAddress != null ||
        _lat != null ||
        _lng != null ||
        _genderPreference != 'any' ||
        _requiresOwnerApproval ||
        !_ownerAutoJoin ||
        _groupFeeDrafts.isNotEmpty ||
        _roundExpenseDrafts.isNotEmpty ||
        _positionDrafts.isNotEmpty;
  }

  Future<void> _handleBackRequest() async {
    if (_allowPop) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    if (!_hasUnsavedChanges()) {
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return;
    }
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ละทิ้งการสร้างก๊วน?'),
        content: const Text(
          'ข้อมูลที่กรอกไว้จะไม่ถูกบันทึก คุณต้องการละทิ้งหรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'ละทิ้ง',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (shouldLeave == true && mounted) {
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  static const _prefsRecentGroupNamesKey = 'recent_group_names';
  static const _prefsDraftKey = 'create_group_draft';
  static const _draftTtlHours = 1;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _repo = FitnessBuddiesRepository(Supabase.instance.client);
    _loadSports();
    _loadRecentNames();
    _restoreDraft();
    _loadMapConfig();
  }

  /// Phase 3: the venue map is driven by the persisted provider config.
  /// Until it loads — or when the server is unreachable — the embedded app
  /// default applies (web disabled, mobile Google), matching the old
  /// `PlatformService.shouldShowLiveMap` behaviour.
  Future<void> _loadMapConfig() async {
    try {
      final snapshot = await MapConfigService().load();
      if (mounted) setState(() => _mapSnapshot = snapshot);
    } catch (_) {
      // MapConfigService already falls back to the app default.
    }
  }

  MapTarget get _mapTarget =>
      (_mapSnapshot?.config ?? MapProviderConfig.appDefault()).resolveTarget(
        MapFeature.groupCreate,
        PlatformService.mapPlatform,
      );

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _searchPlaceCtrl.dispose();
    _skillNoteCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didReadInitialArgs) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['sportId'] is String?) {
      // Set initial selected sport if provided from previous page
      setState(() {
        _sportId = args['sportId'] as String?;
      });
    }
    _didReadInitialArgs = true;
  }

  TextStyle _emojiTextStyle(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return const TextStyle(fontFamily: 'Apple Color Emoji');
    }
    if (platform == TargetPlatform.android) {
      return const TextStyle(fontFamily: 'Noto Color Emoji');
    }
    if (platform == TargetPlatform.windows) {
      return const TextStyle(fontFamily: 'Segoe UI Emoji');
    }
    return const TextStyle(
      fontFamilyFallback: [
        'Apple Color Emoji',
        'Noto Color Emoji',
        'Segoe UI Emoji',
      ],
    );
  }

  Future<void> _loadSports() async {
    setState(() {
      _isSportsLoading = true;
      _sportsLoadFailed = false;
    });
    try {
      final userId = AuthService.instance.currentUser?.id;
      final sports = await _repo.getApprovedSports(userId: userId);
      if (!mounted) return;
      setState(() {
        _sports = sports;
        _isSportsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSportsLoading = false;
        _sportsLoadFailed = true;
      });
    }
  }

  /// Permission + position fix shared by the card button and the fullscreen
  /// picker's my-location overlay. Returns null when permission is denied.
  Future<MapLatLng?> _acquireUserLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final pos = await Geolocator.getCurrentPosition();
    return MapLatLng(pos.latitude, pos.longitude);
  }

  Future<MapLatLng?> _resolveUserLocation() async {
    try {
      final point = await _acquireUserLocation();
      if (point == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่ได้รับอนุญาตให้เข้าถึงตำแหน่ง')),
        );
      }
      return point;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ไม่สามารถดึงตำแหน่ง: $e')));
      }
      return null;
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      final point = await _resolveUserLocation();
      if (point == null || !mounted) return;
      setState(() {
        _lat = point.latitude;
        _lng = point.longitude;
      });
      _animateMapTo(point, zoom: 15);
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      await _saveDraft();
      if (!mounted) return;
      await Navigator.pushNamed(
        context,
        '/login',
        arguments: {'returnAfterLogin': true},
      );
      if (!mounted || AuthService.instance.currentUser == null) return;
      return _submit();
    }
    setState(() => _submitting = true);
    try {
      final groupId = await _repo.createGroup(
        userId: user.id,
        name: _nameCtrl.text.trim(),
        sportId: _sportId,
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        requiresOwnerApproval: _requiresOwnerApproval,
        ownerAutoJoin: _ownerAutoJoin,
        coverImageUrl: _coverImageUrl,
        venuePhotoUrl: _venuePhotoUrl,
        genderPreference: _genderPreference,
        province: _selectedAddress?.province,
        district: _selectedAddress?.district,
        subdistrict: _selectedAddress?.subDistrict,
        postalCode: _selectedAddress?.postalCode,
        lat: _lat,
        lng: _lng,
        targetSkillLevels: _targetSkillLevels,
        skillLevelNote: _skillNoteCtrl.text.trim().isEmpty
            ? null
            : _skillNoteCtrl.text.trim(),
        fieldLayout: _customFieldLayout,
      );
      // Phase 9.1: persist drafted cost standards now that group_id exists.
      for (final fee in _groupFeeDrafts) {
        await _repo.createGroupCostStandard(
          groupId: groupId,
          actorUserId: user.id,
          standardType: 'group_fee',
          category: 'membership',
          name: fee['name'].toString(),
          amount: (fee['amount'] as num).toDouble(),
          billingPeriod: fee['billing_period']?.toString(),
          paymentTiming: fee['payment_timing'].toString(),
        );
      }
      for (final tpl in _roundExpenseDrafts) {
        await _repo.createGroupCostStandard(
          groupId: groupId,
          actorUserId: user.id,
          standardType: 'round_expense',
          category: tpl['category'].toString(),
          name: tpl['name'].toString(),
          amount: (tpl['amount'] as num).toDouble(),
          pricingUnit: tpl['pricing_unit']?.toString(),
          defaultQuantity: (tpl['default_quantity'] as num?)?.toDouble() ?? 1,
          paymentTiming: tpl['payment_timing'].toString(),
        );
      }
      // Phase 15: persist drafted positions on pitch layout atomically
      if (_fieldLayout != null && _positionDrafts.isNotEmpty) {
        await _repo.replaceGroupPositions(
          groupId: groupId,
          actorUserId: user.id,
          positions: _positionDrafts,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('สร้างก๊วนสำเร็จ')));
      await _clearDraft();
      await _saveRecentName(_nameCtrl.text.trim());
      if (!mounted) return;
      // กลับไปหน้าก่อนหน้า พร้อมส่ง groupId + sportId เพื่อให้หน้า SportClub เลือกแถบกีฬาและ scroll ไปการ์ดใหม่
      Navigator.pop(context, {'groupId': groupId, 'sportId': _sportId});
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('สร้างก๊วนไม่สำเร็จ: $e')));
    }
  }

  Future<void> _loadRecentNames() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsRecentGroupNamesKey) ?? [];
      if (!mounted) return;
      setState(() => _recentGroupNames = list);
    } catch (_) {}
  }

  Future<void> _saveRecentName(String name) async {
    if (name.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsRecentGroupNamesKey) ?? [];
      final updated = [name, ...list.where((n) => n != name)];
      if (updated.length > 10) {
        updated.removeRange(10, updated.length);
      }
      await prefs.setStringList(_prefsRecentGroupNamesKey, updated);
      if (!mounted) return;
      setState(() => _recentGroupNames = updated);
    } catch (_) {}
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = {
        'name': _nameCtrl.text,
        'description': _descCtrl.text,
        'searchPlace': _searchPlaceCtrl.text,
        'sportId': _sportId,
        'genderPreference': _genderPreference,
        'requiresOwnerApproval': _requiresOwnerApproval,
        'ownerAutoJoin': _ownerAutoJoin,
        'postalCode': _selectedAddress?.postalCode,
        'province': _selectedAddress?.province,
        'district': _selectedAddress?.district,
        'subdistrict': _selectedAddress?.subDistrict,
        'lat': _lat,
        'lng': _lng,
        'coverImageUrl': _coverImageUrl,
        'venuePhotoUrl': _venuePhotoUrl,
        'groupFees': _groupFeeDrafts,
        'roundExpenses': _roundExpenseDrafts,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_prefsDraftKey, jsonEncode(draft));
    } catch (_) {}
  }

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsDraftKey);
      if (raw == null || raw.isEmpty) return;
      final draft = jsonDecode(raw) as Map<String, dynamic>;
      final ts = draft['timestamp'] as int?;
      if (ts != null) {
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(ts),
        );
        if (age.inHours >= _draftTtlHours) {
          await prefs.remove(_prefsDraftKey);
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = draft['name']?.toString() ?? '';
        _descCtrl.text = draft['description']?.toString() ?? '';
        _searchPlaceCtrl.text = draft['searchPlace']?.toString() ?? '';
        if (draft['sportId'] != null) _sportId = draft['sportId'].toString();
        _genderPreference = draft['genderPreference']?.toString() ?? 'any';
        _requiresOwnerApproval = draft['requiresOwnerApproval'] == true;
        _ownerAutoJoin = draft['ownerAutoJoin'] != false;
        final postalCode = draft['postalCode']?.toString();
        final province = draft['province']?.toString();
        final district = draft['district']?.toString();
        final subdistrict = draft['subdistrict']?.toString();
        if (postalCode != null &&
            province != null &&
            district != null &&
            subdistrict != null) {
          _selectedAddress = ThaiAddress(
            postalCode: postalCode,
            province: province,
            district: district,
            subDistrict: subdistrict,
          );
        }
        _lat = (draft['lat'] as num?)?.toDouble();
        _lng = (draft['lng'] as num?)?.toDouble();
        _coverImageUrl = draft['coverImageUrl']?.toString();
        _venuePhotoUrl = draft['venuePhotoUrl']?.toString();
        _groupFeeDrafts =
            (draft['groupFees'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];
        _roundExpenseDrafts =
            (draft['roundExpenses'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];
      });
      await prefs.remove(_prefsDraftKey);
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsDraftKey);
    } catch (_) {}
  }

  Widget _buildBackgroundCircle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: NeumorphicTheme.baseColor,
        boxShadow: [
          BoxShadow(
            color: NeumorphicTheme.shadowDark.withValues(alpha: 0.35),
            offset: const Offset(12, 12),
            blurRadius: 24,
          ),
          BoxShadow(
            color: NeumorphicTheme.shadowLight,
            offset: const Offset(-12, -12),
            blurRadius: 24,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackRequest();
      },
      child: Scaffold(
        backgroundColor: NeumorphicTheme.baseColor,
        body: Stack(
          children: [
            // Ambient Neumorphic Background Circles
            Positioned(top: -60, left: -60, child: _buildBackgroundCircle(200)),
            Positioned(
              bottom: 120,
              right: -80,
              child: _buildBackgroundCircle(240),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Neumorphic Top Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: NeumorphicTheme.baseColor,
                            boxShadow: NeumorphicTheme.smallShadows(
                              distance: 4,
                              blur: 8,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(21),
                              onTap: () => _handleBackRequest(),
                              child: const Icon(
                                Icons.arrow_back,
                                color: NeumorphicTheme.textPrimary,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'สร้างก๊วนกีฬา',
                            style: TextStyle(
                              color: NeumorphicTheme.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Column(
                          children: [
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  8,
                                  20,
                                  24,
                                ),
                                children: [
                                  _buildModernSection(
                                    title: 'ข้อมูลพื้นฐาน',
                                    icon: Icons.info_outline,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _isSportsLoading
                                                  ? _buildLoadingField('กีฬา')
                                                  : _sportsLoadFailed
                                                  ? _buildSportsErrorField()
                                                  : _buildModernSportDropdown(),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        _buildModernTextField(
                                          controller: _nameCtrl,
                                          label: 'ชื่อก๊วน',
                                          hint: 'ระบุชื่อที่สื่อถึงกิจกรรม',
                                          maxLength: 60,
                                          validator: (v) =>
                                              (v == null || v.trim().isEmpty)
                                              ? 'กรุณาระบุชื่อก๊วน'
                                              : null,
                                        ),
                                        if (_recentGroupNames.isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          const Text(
                                            'ใช้ชื่อที่เคยใช้ล่าสุด:',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          _buildRecentNames(),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  _buildCollapsibleSection(
                                    title: 'การเข้าร่วมก๊วน',
                                    icon: Icons.group_outlined,
                                    expanded: _showMembershipSection,
                                    onToggle: () => setState(
                                      () => _showMembershipSection =
                                          !_showMembershipSection,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildModernSwitch(
                                          title: 'ก๊วนส่วนตัว',
                                          subtitle:
                                              'ต้องรอให้เจ้าของอนุมัติก่อนจึงจะจองได้',
                                          value: _requiresOwnerApproval,
                                          onChanged: (v) => setState(
                                            () => _requiresOwnerApproval = v,
                                          ),
                                        ),
                                        const Divider(height: 24),
                                        _buildModernSwitch(
                                          title: 'เข้าร่วมอัตโนมัติ',
                                          subtitle:
                                              'เจ้าของก๊วนจะอยู่ในรายชื่อจองทุกรอบนัด',
                                          value: _ownerAutoJoin,
                                          onChanged: (v) => setState(
                                            () => _ownerAutoJoin = v,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  _buildCollapsibleSection(
                                    title: 'รูปภาพ',
                                    icon: Icons.image_outlined,
                                    expanded: _showImageSection,
                                    onToggle: () => setState(
                                      () => _showImageSection =
                                          !_showImageSection,
                                    ),
                                    child: Column(
                                      children: [
                                        ImageUploadField(
                                          label: 'หน้าปกก๊วน',
                                          bucket: 'fitness-group-covers',
                                          pathPrefix: 'covers/',
                                          initialUrl: _coverImageUrl,
                                          onUploaded: (url) => setState(
                                            () => _coverImageUrl = url,
                                          ),
                                          onRemoved: () => setState(
                                            () => _coverImageUrl = null,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        ImageUploadField(
                                          label: 'ถ่ายสนาม',
                                          bucket: 'fitness-group-venues',
                                          pathPrefix: 'venues/',
                                          initialUrl: _venuePhotoUrl,
                                          onUploaded: (url) => setState(
                                            () => _venuePhotoUrl = url,
                                          ),
                                          onRemoved: () => setState(
                                            () => _venuePhotoUrl = null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  _buildCollapsibleSection(
                                    title: 'เงื่อนไขเพิ่มเติม',
                                    icon: Icons.settings_outlined,
                                    expanded: _showSettingsSection,
                                    onToggle: () => setState(
                                      () => _showSettingsSection =
                                          !_showSettingsSection,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildModernTextField(
                                          controller: _descCtrl,
                                          label: 'คำอธิบาย (ไม่บังคับ)',
                                          hint:
                                              'รายละเอียดเพิ่มเติม เช่น ระดับฝีมือ อุปกรณ์...',
                                          maxLines: 3,
                                          maxLength: 500,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  _buildCollapsibleSection(
                                    title: 'ระดับฝีมือผู้เล่น',
                                    icon: Icons.school_outlined,
                                    expanded: _showSkillSection,
                                    onToggle: () => setState(
                                      () => _showSkillSection =
                                          !_showSkillSection,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SkillLevelSelector(
                                          availableLevels:
                                              resolveSkillLevelsForSport(
                                                sportData: _selectedSportData,
                                              ),
                                          selectedLevels: _targetSkillLevels,
                                          onLevelsChanged: (levels) {
                                            setState(() {
                                              _targetSkillLevels = levels;
                                            });
                                          },
                                          noteController: _skillNoteCtrl,
                                        ),
                                        const Divider(height: 24),
                                        const Text(
                                          'เพศที่ต้องการชวนเข้าร่วม',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        _buildModernGenderPicker(),
                                      ],
                                    ),
                                  ),
                                  if (_fieldLayout != null) ...[
                                    const SizedBox(height: 32),
                                    _buildCollapsibleSection(
                                      title: 'รูปแบบสนาม',
                                      icon: Icons.sports_handball_outlined,
                                      expanded: _showFieldSection,
                                      onToggle: () => setState(
                                        () => _showFieldSection =
                                            !_showFieldSection,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.06),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.2),
                                              ),
                                            ),
                                            child: const Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  Icons.info_outline,
                                                  size: 16,
                                                  color: AppColors.primaryDark,
                                                ),
                                                SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    'ไม่บังคับ — หากยังไม่กำหนดตำแหน่ง '
                                                    'ก๊วนจะนับจำนวนผู้เข้าร่วมตามปกติ '
                                                    'และเพิ่มหรือแก้ไขตำแหน่งภายหลังได้จากหน้าแก้ไขก๊วน',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: AppColors
                                                          .textSecondary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          const Text(
                                            'ตำแหน่งผู้เล่นที่ต้องการบนสนาม',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'กำหนดตำแหน่งผู้เล่นล่วงหน้าเพื่อให้สมาชิกเลือกตำแหน่งที่ต้องการเล่นเมื่อจองรอบนัด',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          if (_selectedSportData?['field_layout'] !=
                                                  null &&
                                              _selectedSportData?['field_layout'] !=
                                                  'none') ...[
                                            _buildFieldLayoutSelector(),
                                            const SizedBox(height: 16),
                                          ],
                                          PositionLineupEditor(
                                            layout: _fieldLayout!,
                                            fieldStyle: _fieldStyle,
                                            positions: _positionDrafts,
                                            onChanged: (newPositions) {
                                              setState(() {
                                                _positionDrafts = newPositions;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 32),
                                  _buildCollapsibleSection(
                                    title: 'ค่าใช้จ่ายมาตรฐานของก๊วน',
                                    icon: Icons.payments_outlined,
                                    expanded: _showCostsSection,
                                    onToggle: () => setState(
                                      () => _showCostsSection =
                                          !_showCostsSection,
                                    ),
                                    child: _buildCostStandardsEditor(),
                                  ),
                                  const SizedBox(height: 32),
                                  _buildModernSection(
                                    title: 'สถานที่ตั้งสนาม',
                                    icon: Icons.location_on_outlined,
                                    child: Column(
                                      children: [
                                        _buildUnifiedLocationInput(),
                                        const SizedBox(height: 12),
                                        _buildModernMapCard(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                ],
                              ),
                            ),
                            SafeArea(
                              top: false,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  16,
                                ),
                                decoration: BoxDecoration(
                                  color: NeumorphicTheme.baseColor,
                                  boxShadow: [
                                    BoxShadow(
                                      color: NeumorphicTheme.shadowDark
                                          .withValues(alpha: 0.35),
                                      offset: const Offset(0, -4),
                                      blurRadius: 12,
                                    ),
                                    const BoxShadow(
                                      color: NeumorphicTheme.shadowLight,
                                      offset: Offset(0, -1),
                                      blurRadius: 2,
                                    ),
                                  ],
                                ),
                                child: _buildSubmitButton(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return NeumorphicContainer(
      color: NeumorphicTheme.baseColor,
      borderRadius: 24,
      depth: 8,
      blur: 16,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NeumorphicTheme.baseColor,
                  boxShadow: NeumorphicTheme.smallShadows(distance: 3, blur: 6),
                ),
                child: Icon(icon, size: 18, color: NeumorphicTheme.primaryBlue),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: NeumorphicTheme.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildCollapsibleSection({
    required String title,
    required IconData icon,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return NeumorphicContainer(
      color: NeumorphicTheme.baseColor,
      borderRadius: 24,
      depth: expanded ? 8 : 5,
      blur: expanded ? 16 : 12,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: NeumorphicTheme.baseColor,
                        boxShadow: NeumorphicTheme.smallShadows(
                          distance: 3,
                          blur: 6,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 18,
                        color: expanded
                            ? NeumorphicTheme.primaryBlue
                            : NeumorphicTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: NeumorphicTheme.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (!expanded) ...[
                      const Text(
                        'แตะเพื่อเปิด',
                        style: TextStyle(
                          fontSize: 12,
                          color: NeumorphicTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: NeumorphicTheme.baseColor,
                        boxShadow: NeumorphicTheme.smallShadows(
                          distance: expanded ? 1.5 : 2.5,
                          blur: expanded ? 3 : 5,
                        ),
                      ),
                      child: Center(
                        child: AnimatedRotation(
                          turns: expanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            color: expanded
                                ? NeumorphicTheme.primaryBlue
                                : NeumorphicTheme.textSecondary,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFD4DAE3)),
            const SizedBox(height: 16),
            child,
          ],
        ],
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int? maxLength,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return _NeumorphicModernTextField(
      controller: controller,
      label: label,
      hint: hint,
      maxLength: maxLength,
      maxLines: maxLines,
      validator: validator,
    );
  }

  Widget _buildModernSportDropdown() {
    return FormField<String>(
      key: ValueKey(_sportId),
      initialValue: _sportId,
      validator: (v) => v == null ? 'กรุณาเลือกประเภทกีฬา' : null,
      builder: (field) {
        final hasError = field.hasError;
        final selectedSport = _sportId == null
            ? null
            : _sports.firstWhere(
                (s) => s['id'].toString() == _sportId,
                orElse: () => <String, dynamic>{},
              );
        final icon = selectedSport != null
            ? (selectedSport['icon']?.toString() ?? '')
            : '';
        final name = selectedSport != null
            ? (selectedSport['name_th']?.toString() ?? 'กีฬา')
            : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'กีฬา *',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: NeumorphicTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showSportsSelector(field),
              child: CustomPaint(
                painter: NeumorphicInsetPainter(
                  borderRadius: 16,
                  distance: 4.0,
                  blur: 6.0,
                  border: hasError
                      ? const BorderSide(color: Colors.redAccent, width: 1.5)
                      : BorderSide(
                          color: Colors.white.withValues(alpha: 0.7),
                          width: 1.0,
                        ),
                ),
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      if (name != null) ...[
                        if (icon.isNotEmpty)
                          Text(
                            icon,
                            style: _emojiTextStyle(
                              context,
                            ).copyWith(fontSize: 18),
                          ),
                        if (icon.isNotEmpty) const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: NeumorphicTheme.textPrimary,
                            ),
                          ),
                        ),
                      ] else
                        Expanded(
                          child: Text(
                            'เลือกประเภทกีฬา *',
                            style: TextStyle(
                              fontSize: 14,
                              color: NeumorphicTheme.textSecondary.withValues(
                                alpha: 0.65,
                              ),
                            ),
                          ),
                        ),
                      Icon(
                        Icons.keyboard_arrow_down,
                        color: hasError
                            ? Colors.redAccent
                            : NeumorphicTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (hasError) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  field.errorText!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _showSportsSelector(FormFieldState<String> field) async {
    final selectedId = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NeumorphicTheme.baseColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                height: MediaQuery.of(ctx).size.height * 0.65,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCAD1DC),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'เลือกประเภทกีฬา',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: NeumorphicTheme.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: NeumorphicTheme.textSecondary,
                          ),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    CustomPaint(
                      painter: NeumorphicInsetPainter(
                        borderRadius: 16,
                        distance: 3.0,
                        blur: 5.0,
                      ),
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: TextField(
                          autofocus: true,
                          style: const TextStyle(
                            color: NeumorphicTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: 'ค้นหากีฬา',
                            hintStyle: TextStyle(
                              color: NeumorphicTheme.textSecondary.withValues(
                                alpha: 0.65,
                              ),
                            ),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: NeumorphicTheme.textSecondary,
                            ),
                            filled: true,
                            fillColor: Colors.transparent,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                          onChanged: (value) {
                            setSheetState(() => query = value);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Builder(
                        builder: (ctx) {
                          final q = query.toLowerCase();
                          final filtered = _sports.where((s) {
                            final th = (s['name_th']?.toString() ?? '')
                                .toLowerCase();
                            final en = (s['name_en']?.toString() ?? '')
                                .toLowerCase();
                            return th.contains(q) || en.contains(q);
                          }).toList();
                          if (filtered.isEmpty) {
                            return const Center(
                              child: Text(
                                'ไม่พบกีฬาที่ค้นหา',
                                style: TextStyle(
                                  color: NeumorphicTheme.textSecondary,
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final s = filtered[i];
                              final id = s['id'].toString();
                              final icon = s['icon']?.toString() ?? '';
                              final isSelected = id == _sportId;
                              return ListTile(
                                leading: icon.isNotEmpty
                                    ? Text(
                                        icon,
                                        style: _emojiTextStyle(
                                          ctx,
                                        ).copyWith(fontSize: 22),
                                      )
                                    : const SizedBox(width: 28),
                                title: Text(
                                  s['name_th']?.toString() ?? 'กีฬา',
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? NeumorphicTheme.primaryBlue
                                        : NeumorphicTheme.textPrimary,
                                  ),
                                ),
                                trailing: isSelected
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: NeumorphicTheme.primaryBlue,
                                      )
                                    : null,
                                onTap: () => Navigator.of(ctx).pop(id),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selectedId == null) return;
    setState(() => _sportId = selectedId);
    field.didChange(selectedId);
  }

  Widget _buildLoadingField(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: NeumorphicTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        CustomPaint(
          painter: NeumorphicInsetPainter(
            borderRadius: 16,
            distance: 4.0,
            blur: 6.0,
          ),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'กำลังโหลด...',
                  style: TextStyle(
                    color: NeumorphicTheme.textSecondary.withValues(
                      alpha: 0.65,
                    ),
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSportsErrorField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'กีฬา',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: NeumorphicTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        CustomPaint(
          painter: NeumorphicInsetPainter(
            borderRadius: 16,
            distance: 4.0,
            blur: 6.0,
            border: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'โหลดรายการกีฬาไม่สำเร็จ',
                    style: TextStyle(
                      color: NeumorphicTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _loadSports,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('โหลดใหม่', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(
                    foregroundColor: NeumorphicTheme.primaryBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentNames() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _recentGroupNames.take(8).map((n) {
          return Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    _nameCtrl.text = n;
                    _nameCtrl.selection = TextSelection.fromPosition(
                      TextPosition(offset: n.length),
                    );
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: NeumorphicTheme.baseColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: NeumorphicTheme.smallShadows(
                      distance: 2,
                      blur: 4,
                    ),
                  ),
                  child: Text(
                    n,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: NeumorphicTheme.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildModernGenderPicker() {
    return Row(
      children: [
        Expanded(child: _buildGenderChip('male', 'ชาย')),
        const SizedBox(width: 8),
        Expanded(child: _buildGenderChip('female', 'หญิง')),
        const SizedBox(width: 8),
        Expanded(child: _buildGenderChip('any', 'ไม่ระบุ')),
      ],
    );
  }

  Widget _buildGenderChip(String value, String label) {
    final isSelected = _genderPreference == value;
    return GestureDetector(
      onTap: () => setState(() => _genderPreference = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected ? null : NeumorphicTheme.baseColor,
          gradient: isSelected ? NeumorphicTheme.buttonGradient : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? NeumorphicTheme.glowShadows()
              : NeumorphicTheme.smallShadows(distance: 3, blur: 6),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : NeumorphicTheme.textPrimary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: NeumorphicTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: NeumorphicTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          activeTrackColor: NeumorphicTheme.accentCyan,
          activeThumbColor: Colors.white,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Future<void> _showThaiAddressPicker({String? initialPostalCode}) async {
    final result = await showModalBottomSheet<ThaiAddress?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final maxHeight = MediaQuery.of(ctx).size.height * 0.7;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: maxHeight,
              minHeight: MediaQuery.of(ctx).size.height * 0.4,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'เลือกที่อยู่',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      child: ThaiAddressPicker(
                        initialAddress: initialPostalCode == null
                            ? _selectedAddress
                            : null,
                        initialPostalCode: initialPostalCode,
                        onAddressSelected: (address) {
                          Navigator.of(ctx).pop(address);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (result == null) return;
    setState(() {
      _selectedAddress = result;
      _searchPlaceCtrl.text = result.fullAddress;
      _placeSearchMessage = 'ระบุพิกัดสำเร็จ: ${result.fullAddress}';
    });
    _centerMapOnAddress(result);
  }

  Future<void> _centerMapOnAddress(ThaiAddress address) async {
    if (!mounted) return;
    setState(() => _isGeocoding = true);
    try {
      final query = Uri.encodeComponent(
        '${address.district} ${address.province} Thailand',
      );
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&limit=1&q=$query',
      );
      final response = await http
          .get(url, headers: {'User-Agent': 'SheservedApp/1.0'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final list = jsonDecode(response.body) as List<dynamic>;
      if (list.isEmpty) return;
      final first = list.first as Map<String, dynamic>;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lng = double.tryParse(first['lon']?.toString() ?? '');
      if (lat == null || lng == null || !mounted) return;
      setState(() {
        _lat = lat;
        _lng = lng;
      });
      _animateMapTo(MapLatLng(lat, lng), zoom: 14);
    } catch (_) {
      // Silently ignore geocoding errors; user can still pick manually.
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  void _animateMapTo(MapLatLng target, {required double zoom}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController?.animateTo(target, zoom: zoom);
    });
  }

  MapLatLng? _tryParseCoordinates(String text) {
    final cleaned = text.trim();
    // ตรวจสอบรูปแบบ: "13.7563, 100.5018" หรือ "13.7563 100.5018"
    final match = RegExp(
      r'^([+-]?[0-9]+(?:\.[0-9]+)?)[,\s]+([+-]?[0-9]+(?:\.[0-9]+)?)$',
    ).firstMatch(cleaned);

    if (match != null) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat != null &&
          lng != null &&
          lat >= -90 &&
          lat <= 90 &&
          lng >= -180 &&
          lng <= 180) {
        return MapLatLng(lat, lng);
      }
    }
    return null;
  }

  Future<void> _searchPlace(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _placeSearchResults = [];
          _placeSearchMessage = 'กรุณาระบุชื่อสถานที่ รหัสไปรษณีย์ หรือพิกัด';
        });
      }
      return;
    }
    if (_isSearchingPlace) return;

    // Dismiss the IME before changing the result area. This avoids rebuilding
    // the GoogleMap platform view during the Android keyboard transition.
    FocusManager.instance.primaryFocus?.unfocus();
    final requestId = ++_placeSearchRequestId;
    // Reserve the search slot immediately, before waiting for the keyboard
    // transition, so repeated taps cannot start concurrent requests.
    _isSearchingPlace = true;
    // Let the keyboard/platform-view transition finish before changing the
    // widget tree or opening the address sheet.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || requestId != _placeSearchRequestId) return;

    // 1. ตรวจสอบว่าเป็นรหัสไปรษณีย์ 5 หลักหรือไม่ -> เปิดตัวเลือกที่อยู่รูปแบบเดิม
    final isZip = RegExp(r'^\d{5}$').hasMatch(query);
    if (isZip) {
      setState(() {
        _isSearchingPlace = false;
        _placeSearchResults = [];
        _placeSearchMessage = null;
      });
      PlatformService.logPlaceSearch(provider: 'osm');
      await _showThaiAddressPicker(initialPostalCode: query);
      return;
    }

    // 2. ตรวจสอบว่าเป็นพิกัด (ละติจูด, ลองจิจูด) หรือไม่
    final parsedCoord = _tryParseCoordinates(query);
    if (parsedCoord != null) {
      setState(() {
        _lat = parsedCoord.latitude;
        _lng = parsedCoord.longitude;
        _isSearchingPlace = false;
        _placeSearchResults = [];
        _placeSearchMessage =
            'ระบุพิกัดสำเร็จ: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}';
      });

      _animateMapTo(parsedCoord, zoom: 16);
      return;
    }

    // 3. ค้นหาด้วยชื่อสถานที่
    setState(() {
      _isSearchingPlace = true;
      _placeSearchResults = [];
      _placeSearchMessage = null;
    });

    try {
      final encodedQuery = Uri.encodeComponent(query);
      final results = <Map<String, dynamic>>[];

      // ขั้นตอนที่ 1: ค้นหาผ่าน OpenStreetMap (Nominatim) - ฟรี 100%
      final osmUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&limit=5&countrycodes=th&q=$encodedQuery',
      );
      final osmResponse = await http
          .get(osmUrl, headers: {'User-Agent': 'SheservedApp/1.0'})
          .timeout(const Duration(seconds: 10));

      if (osmResponse.statusCode == 200) {
        final osmList = jsonDecode(osmResponse.body) as List<dynamic>;
        for (final item in osmList) {
          final lat = double.tryParse(item['lat']?.toString() ?? '');
          final lng = double.tryParse(item['lon']?.toString() ?? '');
          final displayName = item['display_name']?.toString() ?? '';
          if (lat != null && lng != null && displayName.isNotEmpty) {
            final parts = displayName.split(',');
            final name = parts.first.trim();
            final address = parts.skip(1).take(3).join(',').trim();
            results.add({
              'name': name,
              'address': address.isEmpty ? displayName : address,
              'lat': lat,
              'lng': lng,
              'source': 'OSM (ฟรี)',
            });
          }
        }
      }

      if (results.isNotEmpty) {
        PlatformService.logPlaceSearch(provider: 'osm');
      } else {
        // ขั้นตอนที่ 2: Fallback ด้วย Google Places API หากเปิดใช้งานและมี API Key
        final apiKey = AppConfig.googleMapsApiKey;
        if (PlatformService.isGooglePlacesFallbackEnabled &&
            apiKey.isNotEmpty) {
          final googleUrl = Uri.parse(
            'https://maps.googleapis.com/maps/api/place/textsearch/json?query=$encodedQuery&language=th&key=$apiKey',
          );
          final gResponse = await http
              .get(googleUrl)
              .timeout(const Duration(seconds: 10));
          if (gResponse.statusCode == 200) {
            final gData = jsonDecode(gResponse.body) as Map<String, dynamic>;
            final gResults = gData['results'] as List<dynamic>? ?? [];
            for (final item in gResults.take(5)) {
              final name = item['name']?.toString() ?? '';
              final formattedAddress =
                  item['formatted_address']?.toString() ?? '';
              final loc = item['geometry']?['location'];
              final lat = (loc?['lat'] as num?)?.toDouble();
              final lng = (loc?['lng'] as num?)?.toDouble();
              if (lat != null && lng != null && name.isNotEmpty) {
                results.add({
                  'name': name,
                  'address': formattedAddress,
                  'lat': lat,
                  'lng': lng,
                  'source': 'Google Places',
                });
              }
            }
            if (results.isNotEmpty) {
              PlatformService.logPlaceSearch(provider: 'google_places');
            }
          }
        }
      }

      if (!mounted || requestId != _placeSearchRequestId) return;
      setState(() {
        _isSearchingPlace = false;
        _placeSearchResults = results;
        if (results.isEmpty) {
          _placeSearchMessage =
              'ไม่พบสถานที่ ลองค้นหาด้วยคำอื่น หรือปักหมุดบนแผนที่โดยตรง';
        }
      });
    } catch (e) {
      if (!mounted || requestId != _placeSearchRequestId) return;
      setState(() {
        _isSearchingPlace = false;
        _placeSearchMessage = 'ค้นหาไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
      });
    }
  }

  void _selectPlaceResult(Map<String, dynamic> place) async {
    final isPostal = place['isPostal'] == true;

    if (isPostal && place['subDistrict'] != null) {
      final addr = ThaiAddress(
        postalCode: place['postalCode'] as String,
        province: place['province'] as String,
        district: place['district'] as String,
        subDistrict: place['subDistrict'] as String,
      );
      setState(() {
        _selectedAddress = addr;
        _searchPlaceCtrl.text = addr.fullAddress;
        _placeSearchResults = [];
        _placeSearchMessage = 'ระบุพิกัดสำเร็จ: ${addr.fullAddress}';
      });
      await _centerMapOnAddress(addr);
      return;
    }

    final lat = (place['lat'] as num?)?.toDouble();
    final lng = (place['lng'] as num?)?.toDouble();
    final name = place['name']?.toString() ?? '';

    if (lat != null && lng != null) {
      setState(() {
        _lat = lat;
        _lng = lng;
        _searchPlaceCtrl.text = name;
        _placeSearchResults = [];
        _placeSearchMessage = 'ระบุพิกัดสำเร็จ: $name';
      });

      _animateMapTo(MapLatLng(lat, lng), zoom: 16);
    }
  }

  Widget _buildUnifiedLocationInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomPaint(
          painter: NeumorphicInsetPainter(
            borderRadius: 16,
            distance: 4.0,
            blur: 6.0,
            border: BorderSide(
              color: Colors.white.withValues(alpha: 0.7),
              width: 1.0,
            ),
          ),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(
                    Icons.search,
                    color: NeumorphicTheme.textSecondary,
                    size: 20,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchPlaceCtrl,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: _searchPlace,
                    style: const TextStyle(
                      color: NeumorphicTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.transparent,
                      hintText: 'รหัสไปรษณีย์ | ชื่อสถานที่',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: NeumorphicTheme.textSecondary.withValues(
                          alpha: 0.65,
                        ),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (_isSearchingPlace)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_searchPlaceCtrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(
                      Icons.clear,
                      size: 18,
                      color: NeumorphicTheme.textSecondary,
                    ),
                    onPressed: () {
                      setState(() {
                        _searchPlaceCtrl.clear();
                        _placeSearchResults = [];
                        _placeSearchMessage = null;
                      });
                    },
                  ),
                IconButton(
                  icon: _isSearchingPlace
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.arrow_forward,
                          size: 18,
                          color: NeumorphicTheme.primaryBlue,
                        ),
                  tooltip: 'ค้นหา',
                  onPressed: _isSearchingPlace
                      ? null
                      : () => _searchPlace(_searchPlaceCtrl.text),
                ),
                Container(height: 22, width: 1, color: const Color(0xFFCAD1DC)),
                IconButton(
                  icon: const Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: NeumorphicTheme.primaryBlue,
                  ),
                  tooltip: 'เลือกที่อยู่ทีละขั้นตอน (ต./อ./จ.)',
                  onPressed: _showThaiAddressPicker,
                ),
              ],
            ),
          ),
        ),
        if (_selectedAddress != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFDFE5ED),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: NeumorphicTheme.primaryBlue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ที่อยู่ที่เลือก',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: NeumorphicTheme.primaryBlue,
                        ),
                      ),
                      Text(
                        _selectedAddress!.fullAddress,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: NeumorphicTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _showThaiAddressPicker,
                  style: TextButton.styleFrom(
                    foregroundColor: NeumorphicTheme.primaryBlue,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('แก้ไข', style: TextStyle(fontSize: 12)),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 16,
                    color: NeumorphicTheme.textSecondary,
                  ),
                  tooltip: 'ล้างที่อยู่',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _selectedAddress = null),
                ),
              ],
            ),
          ),
        ],
        if (_placeSearchMessage != null) ...[
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final isSuccess = _placeSearchMessage!.startsWith(
                'ระบุพิกัดสำเร็จ',
              );
              final bgColor = isSuccess
                  ? Colors.green.shade50
                  : Colors.amber.shade50;
              final borderColor = isSuccess
                  ? Colors.green.shade200
                  : Colors.amber.shade200;
              final textColor = isSuccess
                  ? Colors.green.shade900
                  : Colors.amber.shade900;
              final iconColor = isSuccess
                  ? Colors.green.shade700
                  : Colors.amber.shade800;
              final iconData = isSuccess
                  ? Icons.check_circle_outline
                  : Icons.info_outline;

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Icon(iconData, size: 16, color: iconColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _placeSearchMessage!,
                        style: TextStyle(fontSize: 12, color: textColor),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        if (_placeSearchResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          NeumorphicContainer(
            color: NeumorphicTheme.baseColor,
            borderRadius: 16,
            depth: 4,
            blur: 10,
            padding: EdgeInsets.zero,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _placeSearchResults.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: Color(0xFFD4DAE3)),
              itemBuilder: (ctx, i) {
                final place = _placeSearchResults[i];
                final isPostal = place['isPostal'] == true;
                final isGoogle = place['source'] == 'Google Places';
                final avatarBg = isPostal
                    ? Colors.orange.shade50
                    : isGoogle
                    ? Colors.blue.shade50
                    : Colors.green.shade50;
                final avatarIcon = isPostal
                    ? Icons.markunread_mailbox_outlined
                    : Icons.place;
                final avatarColor = isPostal
                    ? Colors.orange.shade700
                    : isGoogle
                    ? Colors.blue.shade700
                    : Colors.green.shade700;
                final badgeBg = isPostal
                    ? Colors.orange.shade50
                    : isGoogle
                    ? Colors.blue.shade50
                    : Colors.green.shade50;
                final badgeColor = isPostal
                    ? Colors.orange.shade800
                    : isGoogle
                    ? Colors.blue.shade800
                    : Colors.green.shade800;

                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: avatarBg,
                    child: Icon(avatarIcon, size: 16, color: avatarColor),
                  ),
                  title: Text(
                    place['name']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: NeumorphicTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    place['address']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 11,
                      color: NeumorphicTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      place['source']?.toString() ?? '',
                      style: TextStyle(
                        fontSize: 10,
                        color: badgeColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  onTap: () => _selectPlaceResult(place),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModernMapCard() {
    // Phase 3: resolved provider config drives this map (feature override →
    // platform default → embedded app default).
    final mapTarget = _mapTarget;
    final showLiveMap = mapTarget.enabled;

    return NeumorphicContainer(
      color: NeumorphicTheme.baseColor,
      borderRadius: 20,
      depth: 6,
      blur: 14,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                const Text(
                  'ตำแหน่งสนาม',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: NeumorphicTheme.textPrimary,
                  ),
                ),
                if (_isGeocoding) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      if (_lat != null && _lng != null)
                        InkWell(
                          onTap: () => setState(() {
                            _lat = null;
                            _lng = null;
                          }),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: NeumorphicTheme.baseColor,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: NeumorphicTheme.smallShadows(
                                distance: 2,
                                blur: 4,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.clear,
                                  size: 14,
                                  color: Colors.redAccent,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'ล้างพิกัด',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      InkWell(
                        onTap: _isGettingLocation ? null : _getCurrentLocation,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: NeumorphicTheme.baseColor,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: NeumorphicTheme.smallShadows(
                              distance: 2,
                              blur: 4,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _isGettingLocation
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.my_location,
                                      size: 14,
                                      color: NeumorphicTheme.primaryBlue,
                                    ),
                              const SizedBox(width: 4),
                              const Text(
                                'ใช้ตำแหน่งฉัน',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: NeumorphicTheme.primaryBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (showLiveMap)
                        InkWell(
                          onTap: _showFullscreenMapPicker,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: NeumorphicTheme.baseColor,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: NeumorphicTheme.smallShadows(
                                distance: 2,
                                blur: 4,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.fullscreen,
                                  size: 14,
                                  color: NeumorphicTheme.primaryBlue,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'ขยาย',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: NeumorphicTheme.primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(20),
            ),
            child: SizedBox(
              height: 180,
              child: KeyedSubtree(
                key: const ValueKey('create_group_map_subtree'),
                child: showLiveMap ? _buildVenueMap() : _buildWebMapFallback(),
              ),
            ),
          ),
          if (_lat != null && _lng != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFDFE5ED),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Text(
                'พิกัด: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: NeumorphicTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWebMapFallback() {
    return Container(
      color: Colors.grey[50],
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'แผนที่ถูกปิดใช้งานบนเบราว์เซอร์',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'เพื่อประหยัดโควต้า Google Maps กรุณาปักหมุดผ่านแอปพลิเคชันมือถือ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (_lat != null && _lng != null) ...[
                const SizedBox(height: 8),
                Text(
                  'พิกัดปัจจุบัน: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVenueMap() {
    return VenueLocationMap(
      key: const ValueKey('create_group_venue_map'),
      target: _mapTarget,
      registry: _mapSnapshot?.registry,
      picked: _lat != null && _lng != null ? MapLatLng(_lat!, _lng!) : null,
      onPicked: (pos) => setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      }),
      onMapCreated: (controller) {
        _mapController = controller;
        if (!_mapLoadLogged) {
          _mapLoadLogged = true;
          PlatformService.logMapLoad(pageName: 'group_create');
        }
      },
    );
  }

  Future<void> _showFullscreenMapPicker() async {
    final target = _mapTarget;
    if (!target.enabled) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ไม่รองรับบนแพลตฟอร์มนี้'),
          content: const Text(
            'การปักหมุดบนแผนที่โต้ตอบถูกปิดสำหรับแพลตฟอร์มนี้ กรุณาใช้งานผ่านแอปพลิเคชันมือถือ',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('เข้าใจแล้ว'),
            ),
          ],
        ),
      );
      return;
    }

    final picked = await VenueLocationPicker.show(
      context,
      target: target,
      registry: _mapSnapshot?.registry,
      initial: _lat != null && _lng != null ? MapLatLng(_lat!, _lng!) : null,
      getUserLocation: _resolveUserLocation,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _lat = picked.latitude;
      _lng = picked.longitude;
    });
    _animateMapTo(picked, zoom: 17);
  }

  Widget _buildSubmitButton() {
    return NeumorphicVerifyButton(
      text: 'สร้างก๊วนใหม่',
      isLoading: _submitting,
      isEnabled: !_submitting,
      height: 54,
      icon: const Icon(
        Icons.check_circle_outline,
        color: Colors.white,
        size: 22,
      ),
      onPressed: _submitting ? null : _submit,
    );
  }

  // ── Phase 9.1: ค่าใช้จ่ายมาตรฐานของก๊วน (drafts, saved after create) ──

  Widget _buildCostStandardsEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NeumorphicTheme.baseColor,
                boxShadow: NeumorphicTheme.smallShadows(distance: 2, blur: 4),
              ),
              child: const Icon(
                Icons.card_membership_rounded,
                size: 16,
                color: NeumorphicTheme.primaryBlue,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'ค่าก๊วน / ค่าสมาชิก',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: NeumorphicTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_groupFeeDrafts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFDFE5ED),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: const [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: NeumorphicTheme.textSecondary,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ยังไม่ได้กำหนดค่าก๊วน/ค่าสมาชิก (ไม่บังคับ)',
                    style: TextStyle(
                      fontSize: 13,
                      color: NeumorphicTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < _groupFeeDrafts.length; i++)
            _buildCostDraftCard(
              title: _groupFeeDrafts[i]['name']?.toString() ?? '',
              category: 'membership',
              amountText: formatBaht(_groupFeeDrafts[i]['amount'] as num?),
              unitText: billingPeriodLabel(
                _groupFeeDrafts[i]['billing_period']?.toString(),
              ),
              timing: _groupFeeDrafts[i]['payment_timing']?.toString(),
              onEdit: () => _editGroupFeeDraft(i),
              onDelete: () => setState(() => _groupFeeDrafts.removeAt(i)),
            ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: _addGroupFeeDraft,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: NeumorphicTheme.baseColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: NeumorphicTheme.smallShadows(distance: 3, blur: 6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: NeumorphicTheme.primaryBlue,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'เพิ่มค่าก๊วน / ค่าสมาชิก',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: NeumorphicTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Divider(height: 1, color: Color(0xFFD4DAE3)),
        const SizedBox(height: 20),
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NeumorphicTheme.baseColor,
                boxShadow: NeumorphicTheme.smallShadows(distance: 2, blur: 4),
              ),
              child: const Icon(
                Icons.sports_tennis_rounded,
                size: 16,
                color: NeumorphicTheme.primaryBlue,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Template ค่าใช้จ่ายรอบ',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: NeumorphicTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_roundExpenseDrafts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFDFE5ED),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: const [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: NeumorphicTheme.textSecondary,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ยังไม่ได้กำหนดแม่แบบค่าใช้จ่ายรอบ (ไม่บังคับ)',
                    style: TextStyle(
                      fontSize: 13,
                      color: NeumorphicTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < _roundExpenseDrafts.length; i++)
            _buildCostDraftCard(
              title: _roundExpenseDrafts[i]['name']?.toString() ?? '',
              category: _roundExpenseDrafts[i]['category']?.toString(),
              amountText: formatBaht(_roundExpenseDrafts[i]['amount'] as num?),
              unitText: pricingUnitLabel(
                _roundExpenseDrafts[i]['pricing_unit']?.toString(),
              ),
              timing: _roundExpenseDrafts[i]['payment_timing']?.toString(),
              onEdit: () => _editRoundExpenseDraft(i),
              onDelete: () => setState(() => _roundExpenseDrafts.removeAt(i)),
            ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: _addRoundExpenseDraft,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: NeumorphicTheme.baseColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: NeumorphicTheme.smallShadows(distance: 3, blur: 6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: NeumorphicTheme.primaryBlue,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'เพิ่ม Template ค่าใช้จ่ายรอบ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: NeumorphicTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCostDraftCard({
    required String title,
    required String? category,
    required String amountText,
    required String unitText,
    required String? timing,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NeumorphicTheme.baseColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: NeumorphicTheme.smallShadows(distance: 2, blur: 5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NeumorphicTheme.baseColor,
              boxShadow: NeumorphicTheme.smallShadows(distance: 2, blur: 4),
            ),
            child: Icon(
              costCategoryIcon(category),
              color: NeumorphicTheme.primaryBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: NeumorphicTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      amountText,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: NeumorphicTheme.primaryBlue,
                      ),
                    ),
                    Text(
                      ' / $unitText',
                      style: const TextStyle(
                        fontSize: 12,
                        color: NeumorphicTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                paymentTimingBadge(timing),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 19),
                color: NeumorphicTheme.textSecondary,
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
                tooltip: 'แก้ไข',
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 19,
                  color: Colors.redAccent,
                ),
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                tooltip: 'ลบ',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addGroupFeeDraft() async {
    final result = await showGroupFeeEditor(context);
    if (result != null && mounted) {
      setState(() => _groupFeeDrafts.add(result));
    }
  }

  Future<void> _editGroupFeeDraft(int index) async {
    final result = await showGroupFeeEditor(
      context,
      existing: _groupFeeDrafts[index],
    );
    if (result != null && mounted) {
      setState(() => _groupFeeDrafts[index] = result);
    }
  }

  Future<void> _addRoundExpenseDraft() async {
    final result = await showRoundExpenseTemplateEditor(context);
    if (result != null && mounted) {
      setState(() => _roundExpenseDrafts.add(result));
    }
  }

  Future<void> _editRoundExpenseDraft(int index) async {
    final result = await showRoundExpenseTemplateEditor(
      context,
      existing: _roundExpenseDrafts[index],
    );
    if (result != null && mounted) {
      setState(() => _roundExpenseDrafts[index] = result);
    }
  }

  Widget _buildFieldLayoutSelector() {
    final layout = _fieldLayout ?? 'double';
    if (layout == 'none') return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'รูปแบบสนาม',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: NeumorphicTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _customFieldLayout = 'single';
                    _positionDrafts.clear();
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: layout == 'single'
                        ? null
                        : NeumorphicTheme.baseColor,
                    gradient: layout == 'single'
                        ? NeumorphicTheme.buttonGradient
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: layout == 'single'
                        ? NeumorphicTheme.glowShadows()
                        : NeumorphicTheme.smallShadows(distance: 2, blur: 5),
                  ),
                  child: Center(
                    child: Text(
                      'ครึ่งสนาม (1 ฝั่ง)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: layout == 'single'
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: layout == 'single'
                            ? Colors.white
                            : NeumorphicTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _customFieldLayout = 'double';
                    _positionDrafts.clear();
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: layout == 'double'
                        ? null
                        : NeumorphicTheme.baseColor,
                    gradient: layout == 'double'
                        ? NeumorphicTheme.buttonGradient
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: layout == 'double'
                        ? NeumorphicTheme.glowShadows()
                        : NeumorphicTheme.smallShadows(distance: 2, blur: 5),
                  ),
                  child: Center(
                    child: Text(
                      'เต็มสนาม (2 ฝั่ง)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: layout == 'double'
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: layout == 'double'
                            ? Colors.white
                            : NeumorphicTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NeumorphicModernTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int? maxLength;
  final int maxLines;
  final String? Function(String?)? validator;

  const _NeumorphicModernTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLength,
    this.maxLines = 1,
    this.validator,
  });

  @override
  State<_NeumorphicModernTextField> createState() =>
      _NeumorphicModernTextFieldState();
}

class _NeumorphicModernTextFieldState
    extends State<_NeumorphicModernTextField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isFocused = _focusNode.hasFocus;

    return FormField<String>(
      initialValue: widget.controller.text,
      validator: widget.validator != null
          ? (_) => widget.validator!(widget.controller.text)
          : null,
      builder: (field) {
        final hasError = field.hasError;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: NeumorphicTheme.textPrimary,
                  ),
                ),
                if (widget.maxLength != null)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder: (context, val, _) {
                      final len = val.text.characters.length;
                      return Text(
                        '$len/${widget.maxLength}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: len > widget.maxLength!
                              ? Colors.redAccent
                              : NeumorphicTheme.textSecondary,
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: isFocused ? NeumorphicTheme.glowShadows() : null,
              ),
              child: CustomPaint(
                painter: NeumorphicInsetPainter(
                  borderRadius: 16,
                  distance: 4.0,
                  blur: 6.0,
                  border: isFocused
                      ? const BorderSide(
                          color: NeumorphicTheme.accentCyan,
                          width: 2.0,
                        )
                      : (hasError
                            ? const BorderSide(
                                color: Colors.redAccent,
                                width: 1.5,
                              )
                            : BorderSide(
                                color: Colors.white.withValues(alpha: 0.7),
                                width: 1.0,
                              )),
                ),
                child: widget.maxLines > 1
                    ? TextField(
                        controller: widget.controller,
                        focusNode: _focusNode,
                        maxLines: widget.maxLines,
                        style: const TextStyle(
                          color: NeumorphicTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        onChanged: (text) {
                          if (hasError) field.didChange(text);
                        },
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.transparent,
                          hintText: widget.hint,
                          hintStyle: TextStyle(
                            color: NeumorphicTheme.textSecondary.withValues(
                              alpha: 0.65,
                            ),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      )
                    : SizedBox(
                        height: 52,
                        child: Center(
                          child: TextField(
                            controller: widget.controller,
                            focusNode: _focusNode,
                            maxLines: 1,
                            style: const TextStyle(
                              color: NeumorphicTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            onChanged: (text) {
                              if (hasError) field.didChange(text);
                            },
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.transparent,
                              hintText: widget.hint,
                              hintStyle: TextStyle(
                                color: NeumorphicTheme.textSecondary.withValues(
                                  alpha: 0.65,
                                ),
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            if (hasError) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  field.errorText ?? '',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
