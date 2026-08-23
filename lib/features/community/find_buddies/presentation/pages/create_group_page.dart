import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../../services/auth_service.dart';
import '../../../../../../shared/widgets/image_upload_field.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';

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
  int _capacity = 5;
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
      fontFamilyFallback: ['Apple Color Emoji', 'Noto Color Emoji', 'Segoe UI Emoji'],
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
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถดึงตำแหน่ง: $e')),
      );
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _submit() async {
    if (_sportId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาเลือกกีฬา')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      await _saveDraft();
      if (!mounted) return;
      Navigator.pushNamed(context, '/login', arguments: {'redirect': '/community/sport-club/group/create'});
      return;
    }
    setState(() => _submitting = true);
    try {
      final groupId = await _repo.createGroup(
        userId: user.id,
        name: _nameCtrl.text.trim(),
        sportId: _sportId,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        requiresOwnerApproval: _requiresOwnerApproval,
        capacity: _capacity,
        coverImageUrl: _coverImageUrl,
        venuePhotoUrl: _venuePhotoUrl,
        genderPreference: _genderPreference,
        province: _provinceCtrl.text.trim().isEmpty ? null : _provinceCtrl.text.trim(),
        district: _districtCtrl.text.trim().isEmpty ? null : _districtCtrl.text.trim(),
        lat: _lat,
        lng: _lng,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สร้างก๊วนสำเร็จ')));
      await _clearDraft();
      await _saveRecentName(_nameCtrl.text.trim());
      if (!mounted) return;
      // กลับไปหน้าก่อนหน้า พร้อมส่ง groupId + sportId เพื่อให้หน้า SportClub เลือกแถบกีฬาและ scroll ไปการ์ดใหม่
      Navigator.pop(context, {'groupId': groupId, 'sportId': _sportId});
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('สร้างก๊วนไม่สำเร็จ: $e')));
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
        'province': _provinceCtrl.text,
        'district': _districtCtrl.text,
        'capacity': _capacity,
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
        final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts));
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
        _provinceCtrl.text = draft['province']?.toString() ?? '';
        _districtCtrl.text = draft['district']?.toString() ?? '';
        _capacity = (draft['capacity'] as int?) ?? 5;
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
      appBar: AppBar(title: const Text('สร้างก๊วนกีฬา')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.5,
                  child: _isSportsLoading
                      ? TextField(
                          enabled: false,
                          decoration: InputDecoration(
                            labelText: 'กีฬา',
                            suffixIcon: Padding(
                              padding: const EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        )
                      : DropdownMenu<String>(
                          key: ValueKey('${_sportId ?? 'none'}:${_sports.length}'),
                          initialSelection: _sportId,
                          width: MediaQuery.of(context).size.width * 0.5,
                          menuHeight: MediaQuery.of(context).size.height * 0.5,
                          label: const Text('กีฬา *'),
                          onSelected: (v) => setState(() => _sportId = v),
                          dropdownMenuEntries: _sports.map((s) => DropdownMenuEntry<String>(
                                value: s['id'].toString(),
                                label: s['name_th']?.toString() ?? 'กีฬา',
                                leadingIcon: (s['icon']?.toString() ?? '').isNotEmpty
                                    ? Text(s['icon']!.toString(), style: _emojiTextStyle(context))
                                    : null,
                              )).toList(),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'ชื่อก๊วน (สูงสุด 60 ตัวอักษร)'),
                maxLength: 60,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'กรุณาระบุชื่อก๊วน' : null,
              ),
              const SizedBox(height: 8),
              if (_recentGroupNames.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _recentGroupNames
                        .take(8)
                        .map((n) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                label: Text(n, overflow: TextOverflow.ellipsis),
                                onPressed: () {
                                  setState(() {
                                    _nameCtrl.text = n;
                                    _nameCtrl.selection = TextSelection.fromPosition(
                                      TextPosition(offset: n.length),
                                    );
                                  });
                                },
                              ),
                            ))
                        .toList(),
                  ),
                ),
              if (_recentGroupNames.isNotEmpty) const SizedBox(height: 8),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'คำอธิบาย (ไม่บังคับ)'),
                maxLines: 3,
                maxLength: 500,
              ),
              const SizedBox(height: 8),
              ImageUploadField(
                label: 'ภาพปกก๊วน',
                bucket: 'fitness-group-covers',
                pathPrefix: 'covers/',
                initialUrl: _coverImageUrl,
                onUploaded: (url) => setState(() => _coverImageUrl = url),
                onRemoved: () => setState(() => _coverImageUrl = null),
              ),
              const SizedBox(height: 12),
              ImageUploadField(
                label: 'ภาพถ่ายสนาม',
                bucket: 'fitness-group-venues',
                pathPrefix: 'venues/',
                initialUrl: _venuePhotoUrl,
                onUploaded: (url) => setState(() => _venuePhotoUrl = url),
                onRemoved: () => setState(() => _venuePhotoUrl = null),
              ),
              const SizedBox(height: 12),
              const Text('เพศที่ต้องการชวนเข้าร่วม'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('ช.'),
                    selected: _genderPreference == 'male',
                    onSelected: (_) => setState(() => _genderPreference = 'male'),
                  ),
                  ChoiceChip(
                    label: const Text('ญ.'),
                    selected: _genderPreference == 'female',
                    onSelected: (_) => setState(() => _genderPreference = 'female'),
                  ),
                  ChoiceChip(
                    label: const Text('เสรี'),
                    selected: _genderPreference == 'any',
                    onSelected: (_) => setState(() => _genderPreference = 'any'),
                  ),
                ],
              ),
              SwitchListTile(
                title: const Text('ก๊วนส่วนตัว (ต้องให้เจ้าของก๊วนอนุมัติก่อนจึงมีผลต่อการจอง)'),
                subtitle: const Text('ปิด = ก๊วนเปิด (ยอมรับอัตโนมัติ) · เปิด = ก๊วนส่วนตัว (รออนุมัติ)'),
                value: _requiresOwnerApproval,
                onChanged: (v) => setState(() => _requiresOwnerApproval = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _provinceCtrl,
                      decoration: const InputDecoration(labelText: 'จังหวัด (ไม่บังคับ)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _districtCtrl,
                      decoration: const InputDecoration(labelText: 'อำเภอ/เขต (ไม่บังคับ)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('ตำแหน่งสนาม (ไม่บังคับ)', style: TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _isGettingLocation ? null : _getCurrentLocation,
                            icon: _isGettingLocation
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.my_location, size: 18),
                            label: const Text('ใช้ตำแหน่งฉัน'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 200,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
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
                                      child: const Icon(Icons.location_on, color: Colors.red, size: 36),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (_lat != null && _lng != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'พิกัด: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('จำนวนสมาชิกสูงสุด'),
                  Text('$_capacity คน'),
                ],
              ),
              Slider(
                value: _capacity.toDouble(),
                min: 2,
                max: 30,
                divisions: 28,
                label: '$_capacity',
                onChanged: (v) => setState(() => _capacity = v.toInt()),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                label: const Text('บันทึก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
