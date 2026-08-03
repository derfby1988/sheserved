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
    await _repo.approveSport(sportId: id, reviewedBy: user.id);
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
