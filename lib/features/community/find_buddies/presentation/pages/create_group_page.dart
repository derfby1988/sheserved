import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../../config/app_config.dart';
import '../../../../../../services/auth_service.dart';
import '../../../../../../services/platform_service.dart';
import '../../../../../../shared/widgets/image_upload_field.dart';
import '../../../../../../core/constants/app_colors.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';
import '../../../../../../shared/widgets/tlz_app_top_bar.dart';
import '../../../../../../shared/widgets/thai_address_picker/thai_address_picker.dart';

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
  bool _showImageSection = false;
  bool _showSettingsSection = false;
  gm.GoogleMapController? _mapController;
  bool _mapLoadLogged = false;
  final _searchPlaceCtrl = TextEditingController();
  bool _isSearchingPlace = false;
  List<Map<String, dynamic>> _placeSearchResults = [];
  String? _placeSearchMessage;

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
        !_ownerAutoJoin;
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
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _searchPlaceCtrl.dispose();
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

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่ได้รับอนุญาตให้เข้าถึงตำแหน่ง')),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController?.animateCamera(
          gm.CameraUpdate.newLatLngZoom(
            gm.LatLng(pos.latitude, pos.longitude),
            15,
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ไม่สามารถดึงตำแหน่ง: $e')));
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
      Navigator.pushNamed(
        context,
        '/login',
        arguments: {'redirect': '/community/sport-club/group/create'},
      );
      return;
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
      );
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
        backgroundColor: AppColors.background,
        body: Container(
          decoration: BoxDecoration(gradient: AppColors.primaryGradient),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: TlzAppTopBar.onPrimary(
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => _handleBackRequest(),
                    ),
                    middle: const FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'สร้างก๊วนกีฬา',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
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
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                          children: [
                            _buildModernSection(
                              title: 'ข้อมูลพื้นฐาน',
                              icon: Icons.info_outline,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                              title: 'รูปภาพ',
                              icon: Icons.image_outlined,
                              expanded: _showImageSection,
                              onToggle: () => setState(
                                () => _showImageSection = !_showImageSection,
                              ),
                              child: Column(
                                children: [
                                  ImageUploadField(
                                    label: 'ภาพปกก๊วน',
                                    bucket: 'fitness-group-covers',
                                    pathPrefix: 'covers/',
                                    initialUrl: _coverImageUrl,
                                    onUploaded: (url) =>
                                        setState(() => _coverImageUrl = url),
                                    onRemoved: () =>
                                        setState(() => _coverImageUrl = null),
                                  ),
                                  const SizedBox(height: 16),
                                  ImageUploadField(
                                    label: 'ภาพถ่ายสนาม',
                                    bucket: 'fitness-group-venues',
                                    pathPrefix: 'venues/',
                                    initialUrl: _venuePhotoUrl,
                                    onUploaded: (url) =>
                                        setState(() => _venuePhotoUrl = url),
                                    onRemoved: () =>
                                        setState(() => _venuePhotoUrl = null),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [

                                  const SizedBox(height: 20),
                                  const Text(
                                    'เพศที่ต้องการชวนเข้าร่วม',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _buildModernGenderPicker(),
                                  const SizedBox(height: 20),
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
                                    onChanged: (v) =>
                                        setState(() => _ownerAutoJoin = v),
                                  ),
                                                                        const Divider(height: 24),                              _buildModernTextField(
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
                            _buildSubmitButton(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.backgroundCream.withOpacity(0.3),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.primary.withOpacity(0.1)),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _buildCollapsibleSection({
    required String title,
    required IconData icon,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (!expanded) ...[
                    const Text(
                      'แตะเพื่อเปิด',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.backgroundCream.withOpacity(0.3),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.primary.withOpacity(0.1)),
            ),
            child: child,
          ),
      ],
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
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      validator: validator,
      buildCounter:
          (context, {required currentLength, required isFocused, maxLength}) {
            if (maxLength == null) return null;
            return Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Text(
                '$currentLength/$maxLength',
                style: TextStyle(
                  fontSize: 11,
                  color: currentLength > maxLength
                      ? Colors.redAccent
                      : Colors.grey,
                ),
              ),
            );
          },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white.withOpacity(0.8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.primary.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.primary.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildModernSportDropdown() {
    return FormField<String>(
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
            GestureDetector(
              onTap: () => _showSportsSelector(field),
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hasError
                        ? Colors.redAccent
                        : AppColors.primary.withOpacity(0.2),
                  ),
                ),
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
                      if (icon.isNotEmpty) const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ] else
                      Expanded(
                        child: Text(
                          'เลือกประเภทกีฬา *',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    Icon(
                      Icons.keyboard_arrow_down,
                      color: hasError ? Colors.redAccent : Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
            if (hasError) ...[
              const SizedBox(height: 6),
              Text(
                field.errorText!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                height: MediaQuery.of(ctx).size.height * 0.6,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'เลือกประเภทกีฬา',
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
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'ค้นหากีฬา',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      onChanged: (value) {
                        setSheetState(() => query = value);
                      },
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
                                style: TextStyle(color: Colors.grey),
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
                                contentPadding: EdgeInsets.zero,
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
                                        ? AppColors.primary
                                        : null,
                                  ),
                                ),
                                trailing: isSelected
                                    ? Icon(
                                        Icons.check_circle,
                                        color: AppColors.primary,
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
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          const Spacer(),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ),
    );
  }

  Widget _buildSportsErrorField() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'โหลดรายการกีฬาไม่สำเร็จ',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
          TextButton.icon(
            onPressed: _loadSports,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('โหลดใหม่', style: TextStyle(fontSize: 13)),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentNames() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _recentGroupNames.take(8).map((n) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              backgroundColor: AppColors.primary.withOpacity(0.05),
              side: BorderSide(color: AppColors.primary.withOpacity(0.1)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              label: Text(n, style: const TextStyle(fontSize: 12)),
              onPressed: () {
                setState(() {
                  _nameCtrl.text = n;
                  _nameCtrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: n.length),
                  );
                });
              },
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.primary.withOpacity(0.2),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          activeColor: AppColors.primary,
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
    setState(() => _isGeocoding = true);
    try {
      final query = Uri.encodeComponent(
        '${address.district} ${address.province} Thailand',
      );
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&limit=1&q=$query',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'SheservedApp/1.0'},
      );
      if (response.statusCode != 200) return;
      final list = jsonDecode(response.body) as List<dynamic>;
      if (list.isEmpty) return;
      final first = list.first as Map<String, dynamic>;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lng = double.tryParse(first['lon']?.toString() ?? '');
      if (lat == null || lng == null) return;
      setState(() {
        _lat = lat;
        _lng = lng;
      });
      _mapController?.animateCamera(
        gm.CameraUpdate.newLatLngZoom(gm.LatLng(lat, lng), 14),
      );
    } catch (_) {
      // Silently ignore geocoding errors; user can still pick manually.
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  gm.LatLng? _tryParseCoordinates(String text) {
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
        return gm.LatLng(lat, lng);
      }
    }
    return null;
  }

  Future<void> _searchPlace(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();

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

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController?.animateCamera(
          gm.CameraUpdate.newLatLngZoom(parsedCoord, 16),
        );
      });
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
      final osmResponse = await http.get(
        osmUrl,
        headers: {'User-Agent': 'SheservedApp/1.0'},
      );

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
          final gResponse = await http.get(googleUrl);
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

      if (!mounted) return;
      setState(() {
        _isSearchingPlace = false;
        _placeSearchResults = results;
        if (results.isEmpty) {
          _placeSearchMessage =
              'ไม่พบสถานที่ ลองค้นหาด้วยคำอื่น หรือปักหมุดบนแผนที่โดยตรง';
        }
      });
    } catch (e) {
      if (!mounted) return;
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

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController?.animateCamera(
          gm.CameraUpdate.newLatLngZoom(gm.LatLng(lat, lng), 16),
        );
      });
    }
  }

  Widget _buildUnifiedLocationInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withOpacity(0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.search, color: Colors.grey, size: 20),
              ),
              Expanded(
                child: TextField(
                  controller: _searchPlaceCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _searchPlace,
                  decoration: const InputDecoration(
                    hintText: 'รหัสไปรษณีย์ | ชื่อสถานที่',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (_isSearchingPlace)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_searchPlaceCtrl.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                  onPressed: () {
                    setState(() {
                      _searchPlaceCtrl.clear();
                      _placeSearchResults = [];
                      _placeSearchMessage = null;
                    });
                  },
                ),
              IconButton(
                icon: const Icon(
                  Icons.arrow_forward,
                  size: 18,
                  color: AppColors.primary,
                ),
                tooltip: 'ค้นหา',
                onPressed: () => _searchPlace(_searchPlaceCtrl.text),
              ),
              Container(height: 24, width: 1, color: Colors.grey[200]),
              IconButton(
                icon: const Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
                tooltip: 'เลือกที่อยู่ทีละขั้นตอน (ต./อ./จ.)',
                onPressed: _showThaiAddressPicker,
              ),
            ],
          ),
        ),
        if (_selectedAddress != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: AppColors.primary,
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
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        _selectedAddress!.fullAddress,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _showThaiAddressPicker,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('แก้ไข', style: TextStyle(fontSize: 12)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.grey),
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
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _placeSearchResults.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
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
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    place['address']?.toString() ?? '',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
    final showLiveMap = PlatformService.shouldShowLiveMap(
      pageName: 'group_create',
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                const Text(
                  'ตำแหน่งสนาม',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                if (_isGeocoding) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
                const Spacer(),
                if (_lat != null && _lng != null)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _lat = null;
                      _lng = null;
                    }),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text(
                      'ล้างพิกัด',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                    ),
                  ),
                TextButton.icon(
                  onPressed: _isGettingLocation ? null : _getCurrentLocation,
                  icon: _isGettingLocation
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location, size: 16),
                  label: const Text(
                    'ใช้ตำแหน่งฉัน',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                ),
                if (showLiveMap)
                  TextButton.icon(
                    onPressed: _showFullscreenMapPicker,
                    icon: const Icon(Icons.fullscreen, size: 16),
                    label: const Text('ขยาย', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 180,
            child: KeyedSubtree(
              key: const ValueKey('create_group_map_subtree'),
              child: showLiveMap ? _buildGoogleMap() : _buildWebMapFallback(),
            ),
          ),
          if (_lat != null && _lng != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.backgroundCream.withOpacity(0.5),
              child: Text(
                'พิกัด: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
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

  Widget _buildGoogleMap() {
    final initialTarget = _lat != null && _lng != null
        ? gm.LatLng(_lat!, _lng!)
        : const gm.LatLng(13.7563, 100.5018);
    final initialZoom = _lat != null ? 15.0 : 6.0;

    return gm.GoogleMap(
      key: const ValueKey('create_group_google_map'),
      onMapCreated: (controller) {
        _mapController = controller;
        if (!_mapLoadLogged) {
          _mapLoadLogged = true;
          PlatformService.logMapLoad(pageName: 'group_create');
        }
      },
      initialCameraPosition: gm.CameraPosition(
        target: initialTarget,
        zoom: initialZoom,
      ),
      markers: _buildMarkers(),
      onTap: (pos) => setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      }),
      myLocationButtonEnabled: false,
      myLocationEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
    );
  }

  Set<gm.Marker> _buildMarkers() {
    if (_lat == null || _lng == null) return const <gm.Marker>{};
    return {
      gm.Marker(
        markerId: const gm.MarkerId('venue'),
        position: gm.LatLng(_lat!, _lng!),
        icon: gm.BitmapDescriptor.defaultMarkerWithHue(
          gm.BitmapDescriptor.hueRed,
        ),
      ),
    };
  }

  Future<void> _showFullscreenMapPicker() async {
    if (!PlatformService.shouldShowLiveMap(pageName: 'group_create')) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ไม่รองรับบนเว็บ'),
          content: const Text(
            'การปักหมุดบนแผนที่โต้ตอบไม่รองรับในเบราว์เซอร์ กรุณาใช้งานผ่านแอปพลิเคชันมือถือ',
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

    gm.GoogleMapController? dialogController;
    gm.LatLng? picked;
    gm.LatLng? tempPicked;
    if (_lat != null && _lng != null) {
      picked = gm.LatLng(_lat!, _lng!);
      tempPicked = picked;
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      pageBuilder: (ctx, _, __) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final markers = tempPicked == null
                ? const <gm.Marker>{}
                : <gm.Marker>{
                    gm.Marker(
                      markerId: const gm.MarkerId('picked'),
                      position: tempPicked!,
                      icon: gm.BitmapDescriptor.defaultMarkerWithHue(
                        gm.BitmapDescriptor.hueRed,
                      ),
                    ),
                  };

            return Scaffold(
              appBar: AppBar(
                title: const Text('เลือกตำแหน่งสนาม'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
              body: gm.GoogleMap(
                onMapCreated: (controller) {
                  dialogController = controller;
                },
                initialCameraPosition: gm.CameraPosition(
                  target: picked ?? const gm.LatLng(13.7563, 100.5018),
                  zoom: picked != null ? 17 : 13,
                ),
                markers: markers,
                onTap: (pos) => setSheetState(() => tempPicked = pos),
                myLocationButtonEnabled: true,
                myLocationEnabled: true,
                zoomControlsEnabled: true,
                mapToolbarEnabled: false,
              ),
              floatingActionButton: tempPicked != null
                  ? FloatingActionButton.extended(
                      onPressed: () {
                        this.setState(() {
                          _lat = tempPicked!.latitude;
                          _lng = tempPicked!.longitude;
                        });
                        Navigator.of(ctx).pop();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _mapController?.animateCamera(
                            gm.CameraUpdate.newLatLngZoom(
                              gm.LatLng(_lat!, _lng!),
                              17,
                            ),
                          );
                        });
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('เลือกพิกัดนี้'),
                    )
                  : null,
            );
          },
        );
      },
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _submitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: _submitting
            ? const CircularProgressIndicator(color: Colors.white)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.check_circle_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Text(
                    'สร้างก๊วนใหม่',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
