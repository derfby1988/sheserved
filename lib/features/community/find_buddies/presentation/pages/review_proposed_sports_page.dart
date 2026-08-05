import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../../services/auth_service.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';

class ReviewProposedSportsPage extends StatefulWidget {
  const ReviewProposedSportsPage({super.key});

  @override
  State<ReviewProposedSportsPage> createState() => _ReviewProposedSportsPageState();
}

class _ReviewProposedSportsPageState extends State<ReviewProposedSportsPage> {
  late final FitnessBuddiesRepository _repo;
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _repo = FitnessBuddiesRepository(Supabase.instance.client);
    _load();
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

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _repo.listProposedSports();
    if (!mounted) return;
    setState(() {
      _items = res;
      _loading = false;
    });
  }

  Future<void> _approve(String id) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    final icon = await showDialog<String>(
      context: context,
      builder: (context) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('เลือกไอคอนประจำกีฬา (ไม่บังคับ)'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'วางอีโมจิ เช่น ⚽ 🏀 🎾'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('ข้าม')),
            ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('อนุมัติ')),
          ],
        );
      },
    );
    if (icon == null) return;
    await _repo.approveSport(sportId: id, reviewedBy: user.id, icon: icon.isEmpty ? null : icon);
    _load();
  }

  Future<void> _reject(String id) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('ระบุเหตุผลในการปฏิเสธ'),
          content: TextField(controller: ctrl),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
            ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('ยืนยัน')),
          ],
        );
      },
    );
    if (reason == null || reason.isEmpty) return;
    await _repo.rejectSport(sportId: id, reviewedBy: user.id, reason: reason);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ตรวจคำขอเพิ่มประเภทกีฬา')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final s = _items[i];
                  return Card(
                    child: ListTile(
                      leading: Text.rich(
                        TextSpan(
                          text: s['icon']?.toString() ?? '🏅',
                          style: _emojiTextStyle(context).merge(const TextStyle(fontSize: 24)),
                        ),
                      ),
                      title: Text(s['name_th']?.toString() ?? ''),
                      subtitle: Text(s['name_en']?.toString() ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(onPressed: () => _reject(s['id'].toString()), icon: const Icon(Icons.close, color: Colors.red)),
                          IconButton(onPressed: () => _approve(s['id'].toString()), icon: const Icon(Icons.check, color: Colors.green)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
