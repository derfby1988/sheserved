import 'package:flutter/material.dart';
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
  String _visibility = 'public';
  String _genderPreference = 'any';
  bool _requiresOwnerApproval = false;
  int _capacity = 5;
  bool _submitting = false;
  List<Map<String, dynamic>> _sports = [];
  bool _didReadInitialArgs = false;
  bool _isSportsLoading = true;
  List<String> _recentGroupNames = [];
  static const _prefsRecentGroupNamesKey = 'recent_group_names';

  @override
  void initState() {
    super.initState();
    _repo = FitnessBuddiesRepository(Supabase.instance.client);
    _loadSports();
    _loadRecentNames();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.pushNamed(context, '/login', arguments: {'redirect': '/community/find-buddies/group/create'});
      return;
    }
    setState(() => _submitting = true);
    try {
      final groupId = await _repo.createGroup(
        userId: user.id,
        name: _nameCtrl.text.trim(),
        sportId: _sportId,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        visibility: _visibility,
        requiresOwnerApproval: _requiresOwnerApproval,
        capacity: _capacity,
        coverImageUrl: _coverImageUrl,
        venuePhotoUrl: _venuePhotoUrl,
        genderPreference: _genderPreference,
        province: _provinceCtrl.text.trim().isEmpty ? null : _provinceCtrl.text.trim(),
        district: _districtCtrl.text.trim().isEmpty ? null : _districtCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สร้างก๊วนสำเร็จ')));
      await _saveRecentName(_nameCtrl.text.trim());
      if (!mounted) return;
      Navigator.pop(context, groupId);
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
                      : DropdownMenu<String?>(
                          key: ValueKey('${_sportId ?? 'none'}:${_sports.length}'),
                          initialSelection: _sportId,
                          width: MediaQuery.of(context).size.width * 0.5,
                          menuHeight: MediaQuery.of(context).size.height * 0.5,
                          label: const Text('กีฬา'),
                          onSelected: (v) => setState(() => _sportId = v),
                          dropdownMenuEntries: [
                            const DropdownMenuEntry<String?>(value: null, label: 'ไม่ระบุ'),
                            ..._sports.map((s) => DropdownMenuEntry<String?>(
                                  value: s['id'].toString(),
                                  label: s['name_th']?.toString() ?? 'กีฬา',
                                  leadingIcon: (s['icon']?.toString() ?? '').isNotEmpty
                                      ? Text(s['icon']!.toString(), style: _emojiTextStyle(context))
                                      : null,
                                )),
                          ],
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('สาธารณะ'),
                      value: 'public',
                      groupValue: _visibility,
                      onChanged: (v) => setState(() => _visibility = v ?? 'public'),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('ส่วนตัว'),
                      value: 'private',
                      groupValue: _visibility,
                      onChanged: (v) => setState(() => _visibility = v ?? 'public'),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                title: const Text('ต้องการการอนุมัติจากเจ้าของก๊วน'),
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
