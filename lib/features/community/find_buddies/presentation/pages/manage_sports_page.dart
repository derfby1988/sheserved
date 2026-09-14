import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../../core/constants/app_colors.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';
import '../../../find_buddies/presentation/widgets/position_lineup.dart';

/// Admin page to manage field_layout of already-approved sports.
/// Lets admin set/clear `single` or `double` layout so that the
/// Phase 15 position feature becomes available for a given sport.
class ManageSportsPage extends StatefulWidget {
  const ManageSportsPage({super.key});

  @override
  State<ManageSportsPage> createState() => _ManageSportsPageState();
}

class _ManageSportsPageState extends State<ManageSportsPage> {
  late final FitnessBuddiesRepository _repo;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  final Map<String, bool> _updating = {};

  @override
  void initState() {
    super.initState();
    _repo = FitnessBuddiesRepository(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _repo.getApprovedSports();
      if (!mounted) return;
      setState(() {
        _items = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _layoutLabel(String? layout) {
    switch (layout) {
      case 'single':
        return 'สนาม 1 ฝั่ง';
      case 'double':
        return 'สนาม 2 ฝั่ง';
      case 'none':
        return 'ไม่ใช้สนาม';
      default:
        return 'ยังไม่กำหนด (NULL)';
    }
  }

  Color _layoutColor(String? layout) {
    switch (layout) {
      case 'single':
        return Colors.blue.shade700;
      case 'double':
        return Colors.green.shade700;
      case 'none':
        return Colors.grey.shade600;
      default:
        return Colors.orange.shade700; // NULL
    }
  }

  Future<void> _editLayout(Map<String, dynamic> sport) async {
    final sportId = sport['id'].toString();
    final current = sport['field_layout']?.toString();
    String selected = (current == 'single' || current == 'double' || current == 'none')
        ? current!
        : 'none';
    FieldStyle selectedStyle = FieldStyle.fromJson(sport['field_style']);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final previewLayout = selected == 'none' ? 'single' : selected;
            return AlertDialog(
              title: Row(
                children: [
                  Text(sport['icon']?.toString() ?? '🏅',
                      style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ตั้งค่าสนาม: ${sport['name_th'] ?? ''}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'รูปแบบสนามจำลอง (Field Layout)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'NULL = ปิดใช้งานระบบตำแหน่ง\nnone = ไม่มีสนาม\nsingle = สนาม 1 ฝั่ง\ndouble = สนาม 2 ฝั่ง',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'none', label: Text('ไม่ใช้')),
                        ButtonSegment(value: 'single', label: Text('1 ฝั่ง')),
                        ButtonSegment(value: 'double', label: Text('2 ฝั่ง')),
                      ],
                      selected: {selected},
                      onSelectionChanged: (set) =>
                          setDialogState(() => selected = set.first),
                    ),
                    if (selected != 'none') ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: double.infinity,
                          height: 110,
                          child: CustomPaint(
                            painter: FieldCanvasPainter(
                              layout: previewLayout,
                              style: selectedStyle,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FieldStylePicker(
                        value: selectedStyle,
                        onChanged: (s) =>
                            setDialogState(() => selectedStyle = s),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, {
                    'field_layout': selected,
                    'field_style': selectedStyle.toJson(),
                  }),
                  child: const Text('บันทึก'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    final newLayout = result['field_layout']?.toString() ?? 'none';
    final newStyle = result['field_style'] is Map
        ? Map<String, dynamic>.from(result['field_style'] as Map)
        : null;
    final styleChanged =
        (sport['field_style'] is Map ? FieldStyle.fromJson(sport['field_style']).toJson().toString() : '') !=
            (newStyle != null ? newStyle.toString() : '');
    if (newLayout == current && !styleChanged) return;

    setState(() => _updating[sportId] = true);
    try {
      await _repo.updateSportFieldConfig(
        sportId: sportId,
        fieldLayout: newLayout,
        fieldStyle: newStyle,
      );
      if (!mounted) return;
      setState(() {
        final idx = _items.indexWhere((s) => s['id'].toString() == sportId);
        if (idx >= 0) {
          _items[idx] = {
            ..._items[idx],
            'field_layout': newLayout,
            'field_style': newStyle,
          };
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('อัปเดตเป็น "${_layoutLabel(newLayout)}" แล้ว')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('อัปเดตไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) setState(() => _updating[sportId] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการรูปแบบสนามกีฬา'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'รีเฟรช',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text('โหลดไม่สำเร็จ', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('ลองใหม่'),
                      ),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? const Center(child: Text('ยังไม่มีกีฬาที่อนุมัติแล้ว'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final s = _items[i];
                          final sportId = s['id'].toString();
                          final layout = s['field_layout']?.toString();
                          final isUpdating = _updating[sportId] == true;
                          final isNull = layout == null;

                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: isNull
                                  ? BorderSide(color: Colors.orange.shade200, width: 1)
                                  : BorderSide.none,
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    s['icon']?.toString() ?? '🏅',
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                ),
                              ),
                              title: Text(
                                s['name_th']?.toString() ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: 6,
                                  children: [
                                    if (s['name_en'] != null && s['name_en'].toString().isNotEmpty)
                                      Text(
                                        s['name_en'].toString(),
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _layoutColor(layout).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _layoutLabel(layout),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _layoutColor(layout),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: isUpdating
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : IconButton(
                                      onPressed: () => _editLayout(s),
                                      icon: const Icon(Icons.tune_rounded),
                                      tooltip: 'แก้ไขรูปแบบสนาม',
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
