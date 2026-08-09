import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../../services/auth_service.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';

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
      Navigator.pushNamed(context, '/login', arguments: {'redirect': '/community/sport-club/sport/propose'});
      return;
    }
    setState(() => _submitting = true);
    try {
      await _repo.proposeSport(
        nameTh: _nameThCtrl.text.trim(),
        nameEn: _nameEnCtrl.text.trim().isEmpty ? null : _nameEnCtrl.text.trim(),
        proposedBy: user.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ส่งคำขอเพิ่มประเภทกีฬาสำเร็จ')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ส่งคำขอไม่สำเร็จ: $e')));
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
                validator: (v) => (v == null || v.trim().isEmpty) ? 'กรุณาระบุชื่อกีฬา' : null,
                maxLength: 60,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameEnCtrl,
                decoration: const InputDecoration(labelText: 'ชื่อกีฬา (อังกฤษ) - ไม่บังคับ'),
                maxLength: 60,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                label: const Text('ส่งคำขอ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
