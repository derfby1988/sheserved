import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../../services/auth_service.dart';
import '../../../../../../shared/widgets/image_upload_field.dart';
import '../../../../../../core/constants/app_colors.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';
import '../../../../../../shared/widgets/tlz_app_top_bar.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  late final FitnessBuddiesRepository _repo;
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _coverImageUrl;
  String? _venuePhotoUrl;
  final _provinceCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  String? _sportId;
  String _genderPreference = 'any';
  bool _requiresOwnerApproval = false;
  bool _ownerAutoJoin = true;
  double? _lat;
  double? _lng;
  bool _isGettingLocation = false;
  bool _submitting = false;
  List<Map<String, dynamic>> _sports = [];
  bool _didReadInitialArgs = false;
  bool _isSportsLoading = true;
  List<String> _recentGroupNames = [];
  static const _prefsRecentGroupNamesKey = 'recent_group_names';
  static const _prefsDraftKey = 'create_group_draft';
  static const _draftTtlHours = 1;

  @override
  void initState() {
    super.initState();
    _repo = FitnessBuddiesRepository(Supabase.instance.client);
    _loadSports();
    _loadRecentNames();
    _restoreDraft();
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
    setState(() => _isSportsLoading = true);
    try {
      final userId = AuthService.instance.currentUser?.id;
      final sports = await _repo.getApprovedSports(userId: userId);
      if (!mounted) return;
      setState(() {
        _sports = sports;
        _isSportsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSportsLoading = false);
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
    if (_sportId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กรุณาเลือกกีฬา')));
      return;
    }
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
        province: _provinceCtrl.text.trim().isEmpty
            ? null
            : _provinceCtrl.text.trim(),
        district: _districtCtrl.text.trim().isEmpty
            ? null
            : _districtCtrl.text.trim(),
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
        'sportId': _sportId,
        'genderPreference': _genderPreference,
        'requiresOwnerApproval': _requiresOwnerApproval,
        'ownerAutoJoin': _ownerAutoJoin,
        'province': _provinceCtrl.text,
        'district': _districtCtrl.text,
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
        if (draft['sportId'] != null) _sportId = draft['sportId'].toString();
        _genderPreference = draft['genderPreference']?.toString() ?? 'any';
        _requiresOwnerApproval = draft['requiresOwnerApproval'] == true;
        _ownerAutoJoin = draft['ownerAutoJoin'] != false;
        _provinceCtrl.text = draft['province']?.toString() ?? '';
        _districtCtrl.text = draft['district']?.toString() ?? '';
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: TlzAppTopBar.onPrimary(
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
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
                    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                    child: Form(
                      key: _formKey,
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
                                  validator: (v) => (v == null || v.trim().isEmpty)
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
                                const SizedBox(height: 16),
                                _buildModernTextField(
                                  controller: _descCtrl,
                                  label: 'คำอธิบาย (ไม่บังคับ)',
                                  hint: 'รายละเอียดเพิ่มเติม เช่น ระดับฝีมือ อุปกรณ์...',
                                  maxLines: 3,
                                  maxLength: 500,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildModernSection(
                            title: 'รูปภาพ',
                            icon: Icons.image_outlined,
                            child: Column(
                              children: [
                                ImageUploadField(
                                  label: 'ภาพปกก๊วน',
                                  bucket: 'fitness-group-covers',
                                  pathPrefix: 'covers/',
                                  initialUrl: _coverImageUrl,
                                  onUploaded: (url) => setState(() => _coverImageUrl = url),
                                  onRemoved: () => setState(() => _coverImageUrl = null),
                                ),
                                const SizedBox(height: 16),
                                ImageUploadField(
                                  label: 'ภาพถ่ายสนาม',
                                  bucket: 'fitness-group-venues',
                                  pathPrefix: 'venues/',
                                  initialUrl: _venuePhotoUrl,
                                  onUploaded: (url) => setState(() => _venuePhotoUrl = url),
                                  onRemoved: () => setState(() => _venuePhotoUrl = null),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildModernSection(
                            title: 'การตั้งค่าก๊วน',
                            icon: Icons.settings_outlined,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                                  subtitle: 'ต้องรอให้เจ้าของอนุมัติก่อนจึงจะจองได้',
                                  value: _requiresOwnerApproval,
                                  onChanged: (v) => setState(() => _requiresOwnerApproval = v),
                                ),
                                const Divider(height: 24),
                                _buildModernSwitch(
                                  title: 'เข้าร่วมอัตโนมัติ',
                                  subtitle: 'เจ้าของก๊วนจะอยู่ในรายชื่อจองทุกรอบนัด',
                                  value: _ownerAutoJoin,
                                  onChanged: (v) => setState(() => _ownerAutoJoin = v),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildModernSection(
                            title: 'สถานที่และพิกัด',
                            icon: Icons.location_on_outlined,
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildModernTextField(
                                        controller: _provinceCtrl,
                                        label: 'จังหวัด',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildModernTextField(
                                        controller: _districtCtrl,
                                        label: 'อำเภอ/เขต',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
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
            border: Border.all(
              color: AppColors.primary.withOpacity(0.1),
            ),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        counterText: '',
      ),
    );
  }

  Widget _buildModernSportDropdown() {
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: AppColors.primary.withOpacity(0.2)),
          ),
        ),
      ),
      child: DropdownMenu<String>(
        key: ValueKey('${_sportId ?? 'none'}:${_sports.length}'),
        initialSelection: _sportId,
        width: MediaQuery.of(context).size.width - 72, // Adjust for padding
        menuHeight: MediaQuery.of(context).size.height * 0.4,
        label: const Text('เลือกประเภทกีฬา *'),
        onSelected: (v) => setState(() => _sportId = v),
        dropdownMenuEntries: _sports.map((s) {
          return DropdownMenuEntry<String>(
            value: s['id'].toString(),
            label: s['name_th']?.toString() ?? 'กีฬา',
            leadingIcon: (s['icon']?.toString() ?? '').isNotEmpty
                ? Text(
                    s['icon']!.toString(),
                    style: _emojiTextStyle(context).copyWith(fontSize: 18),
                  )
                : null,
          );
        }).toList(),
      ),
    );
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        _buildGenderChip('male', 'ช.'),
        const SizedBox(width: 8),
        _buildGenderChip('female', 'ญ.'),
        const SizedBox(width: 8),
        _buildGenderChip('any', 'เสรี'),
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
            color: isSelected ? AppColors.primary : AppColors.primary.withOpacity(0.2),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
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
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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

  Widget _buildModernMapCard() {
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
                const Spacer(),
                TextButton.icon(
                  onPressed: _isGettingLocation ? null : _getCurrentLocation,
                  icon: _isGettingLocation
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location, size: 16),
                  label: const Text('ใช้ตำแหน่งฉัน', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 180,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _lat != null && _lng != null
                    ? LatLng(_lat!, _lng!)
                    : const LatLng(13.7563, 100.5018),
                initialZoom: _lat != null ? 15 : 6,
                onTap: (tapPosition, point) {
                  setState(() {
                    _lat = point.latitude;
                    _lng = point.longitude;
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.treeLawZoo',
                ),
                if (_lat != null && _lng != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(_lat!, _lng!),
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_on, color: Colors.red, size: 32),
                      ),
                    ],
                  ),
              ],
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
