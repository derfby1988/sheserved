import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../../services/auth_service.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';
import '../../../find_buddies/presentation/widgets/position_lineup.dart';

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

  Future<void> _approve(Map<String, dynamic> sport) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    final initialLayout = sport['field_layout']?.toString() ?? 'none';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        final ctrl = TextEditingController(text: sport['icon']?.toString() ?? '');
        String selectedLayout = (initialLayout == 'single' || initialLayout == 'double') ? initialLayout : 'none';

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text('อนุมัติกีฬา: ${sport['name_th'] ?? ''}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        labelText: 'ไอคอนประจำกีฬา',
                        hintText: 'วางอีโมจิ เช่น ⚽ 🏀 🎾',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('ยืนยันรูปแบบสนาม (Field Layout):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'none', label: Text('ไม่ใช้')),
                        ButtonSegment(value: 'single', label: Text('1 ฝั่ง')),
                        ButtonSegment(value: 'double', label: Text('2 ฝั่ง')),
                      ],
                      selected: {selectedLayout},
                      onSelectionChanged: (set) => setDialogState(() => selectedLayout = set.first),
                    ),
                    if (selectedLayout != 'none') ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          height: 100,
                          child: CustomPaint(
                            painter: FieldCanvasPainter(layout: selectedLayout),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, {
                    'icon': ctrl.text.trim(),
                    'field_layout': selectedLayout,
                  }),
                  child: const Text('อนุมัติ'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null) return;
    final icon = result['icon'] ?? '';
    final layout = result['field_layout'] ?? 'none';
    await _repo.approveSport(
      sportId: sport['id'].toString(),
      reviewedBy: user.id,
      icon: icon.isEmpty ? null : icon,
      fieldLayout: layout,
    );
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
                  final layout = s['field_layout']?.toString() ?? 'none';
                  final layoutLabel = layout == 'double' ? 'สนาม 2 ฝั่ง' : (layout == 'single' ? 'สนาม 1 ฝั่ง' : 'ไม่ใช้สนาม');

                  return Card(
                    child: ListTile(
                      leading: Text.rich(
                        TextSpan(
                          text: s['icon']?.toString() ?? '🏅',
                          style: _emojiTextStyle(context).merge(const TextStyle(fontSize: 24)),
                        ),
                      ),
                      title: Text(s['name_th']?.toString() ?? ''),
                      subtitle: Text('${s['name_en'] ?? ''} • แนะนำ: $layoutLabel'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(onPressed: () => _reject(s['id'].toString()), icon: const Icon(Icons.close, color: Colors.red)),
                          IconButton(onPressed: () => _approve(s), icon: const Icon(Icons.check, color: Colors.green)),
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
