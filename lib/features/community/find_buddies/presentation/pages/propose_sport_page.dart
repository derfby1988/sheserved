import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../../config/app_config.dart';
import '../../../../../../core/network/authenticated_http_client.dart';
import '../../../../../../services/auth_service.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';
import '../../../find_buddies/presentation/widgets/position_lineup.dart';

class ProposeSportPage extends StatefulWidget {
  const ProposeSportPage({super.key});

  @override
  State<ProposeSportPage> createState() => _ProposeSportPageState();
}

class _ProposeSportPageState extends State<ProposeSportPage> {
  late final FitnessBuddiesRepository _repo;
  final _formKey = GlobalKey<FormState>();
  final _nameThCtrl = TextEditingController();
  final _nameEnCtrl = TextEditingController();
  String _fieldLayout = 'none'; // 'none', 'single', 'double'
  FieldStyle _fieldStyle = FieldStyle.fallback;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _repo = FitnessBuddiesRepository(Supabase.instance.client);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        '/login',
        arguments: {'redirect': '/community/sport-club/sport/propose'},
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final nameTh = _nameThCtrl.text.trim();
      final nameEn = _nameEnCtrl.text.trim().isEmpty
          ? null
          : _nameEnCtrl.text.trim();
      final fieldStyle = _fieldLayout == 'none' ? null : _fieldStyle.toJson();

      // Gateway path: writes the pending sport row and notifies every active
      // admin (in-app notification + realtime toast) in one request.
      // Legacy mode keeps the direct Supabase insert during compatibility —
      // admins then see the request once they refresh the review page.
      if (AppConfig.useBackendAuth) {
        AuthenticatedHttpClient.instance.configure(
          baseUrl: AppConfig.backendApiUrl,
        );
        await AuthenticatedHttpClient.instance.proposeSportType(
          nameTh: nameTh,
          nameEn: nameEn,
          fieldLayout: _fieldLayout,
          fieldStyle: fieldStyle,
        );
      } else {
        await _repo.proposeSport(
          nameTh: nameTh,
          nameEn: nameEn,
          proposedBy: user.id,
          fieldLayout: _fieldLayout,
          fieldStyle: fieldStyle,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งคำขอเพิ่มประเภทกีฬาสำเร็จ')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ส่งคำขอไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เสนอประเภทกีฬาใหม่')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _nameThCtrl,
                decoration: const InputDecoration(labelText: 'ชื่อกีฬา (ไทย)'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'กรุณาระบุชื่อกีฬา'
                    : null,
                maxLength: 60,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameEnCtrl,
                decoration: const InputDecoration(
                  labelText: 'ชื่อกีฬา (อังกฤษ) - ไม่บังคับ',
                ),
                maxLength: 60,
              ),
              const SizedBox(height: 16),
              const Text(
                'รูปแบบสนามจำลองที่แนะนำ (แอดมินจะพิจารณาอนุมัติ):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'none', label: Text('ไม่ใช้ตำแหน่ง')),
                  ButtonSegment(value: 'single', label: Text('สนาม 1 ฝั่ง')),
                  ButtonSegment(value: 'double', label: Text('สนาม 2 ฝั่ง')),
                ],
                selected: {_fieldLayout},
                onSelectionChanged: (set) =>
                    setState(() => _fieldLayout = set.first),
              ),
              if (_fieldLayout != 'none') ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 140,
                    child: CustomPaint(
                      painter: FieldCanvasPainter(
                        layout: _fieldLayout,
                        style: _fieldStyle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FieldStylePicker(
                  value: _fieldStyle,
                  sportName: _nameThCtrl.text.trim(),
                  onChanged: (s) => setState(() => _fieldStyle = s),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('ส่งคำขอ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
