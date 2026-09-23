import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../../core/constants/app_colors.dart';
import '../../../../erp/data/models/app_notification.dart';
import '../../../../../../services/auth_service.dart';
import '../../../../../../shared/widgets/tlz_app_top_bar.dart';
import '../../../../../../shared/widgets/tlz_bottom_navigation_bar.dart';
import '../../../../erp/presentation/providers/notification_provider.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';
import '../../../find_buddies/presentation/widgets/position_lineup.dart';

class ReviewProposedSportsPage extends ConsumerStatefulWidget {
  const ReviewProposedSportsPage({super.key});

  @override
  ConsumerState<ReviewProposedSportsPage> createState() =>
      _ReviewProposedSportsPageState();
}

class _ReviewProposedSportsPageState
    extends ConsumerState<ReviewProposedSportsPage>
    with TlzNavBarScrollMixin {
  late final FitnessBuddiesRepository _repo;
  bool _loading = true;
  String? _error;
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
      fontFamilyFallback: [
        'Apple Color Emoji',
        'Noto Color Emoji',
        'Segoe UI Emoji',
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _repo.listProposedSports();
      if (!mounted) return;
      setState(() {
        _items = res;
        _loading = false;
      });
      ref
          .read(notificationProvider.notifier)
          .syncLocalNotifications(
            res.map(
              (sport) => AppNotification(
                id: 'sport_proposal_${sport['id']}',
                professionId: '',
                recipientId: '',
                category: 'sport',
                eventType: 'sport.proposal_submitted',
                title: 'มีคำขอเพิ่มประเภทกีฬาใหม่',
                body: 'เสนอประเภทกีฬา "${sport['name_th'] ?? ''}"',
                payload: {
                  'route': '/community/sport-club/sport/review',
                  'sportId': sport['id'].toString(),
                },
                createdAt:
                    DateTime.tryParse(sport['proposed_at']?.toString() ?? '') ??
                    DateTime.now(),
              ),
            ),
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _approve(Map<String, dynamic> sport) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    final initialLayout = sport['field_layout']?.toString() ?? 'none';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        final ctrl = TextEditingController(
          text: sport['icon']?.toString() ?? '',
        );
        String selectedLayout =
            (initialLayout == 'single' || initialLayout == 'double')
            ? initialLayout
            : 'none';
        FieldStyle selectedStyle = FieldStyle.fromJson(sport['field_style']);

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final previewLayout = selectedLayout == 'none'
                ? 'single'
                : selectedLayout;
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
                    const Text(
                      'ยืนยันรูปแบบสนาม (Field Layout):',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'none', label: Text('ไม่ใช้')),
                        ButtonSegment(value: 'single', label: Text('1 ฝั่ง')),
                        ButtonSegment(value: 'double', label: Text('2 ฝั่ง')),
                      ],
                      selected: {selectedLayout},
                      onSelectionChanged: (set) =>
                          setDialogState(() => selectedLayout = set.first),
                    ),
                    if (selectedLayout != 'none') ...[
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
                        sportName: sport['name_th']?.toString(),
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
                    'icon': ctrl.text.trim(),
                    'field_layout': selectedLayout,
                    'field_style': selectedStyle.toJson(),
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
    final icon = result['icon']?.toString() ?? '';
    final layout = result['field_layout']?.toString() ?? 'none';
    final style = result['field_style'] is Map
        ? Map<String, dynamic>.from(result['field_style'] as Map)
        : null;
    await _repo.approveSport(
      sportId: sport['id'].toString(),
      reviewedBy: user.id,
      icon: icon.isEmpty ? null : icon,
      fieldLayout: layout,
      fieldStyle: style,
    );
    await _load();
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
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('ยืนยัน'),
            ),
          ],
        );
      },
    );
    if (reason == null || reason.isEmpty) return;
    await _repo.rejectSport(sportId: id, reviewedBy: user.id, reason: reason);
    await _load();
  }

  void _goBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, '/community/sport-club');
    }
  }

  void _onNavIndexChanged(int index) {
    if (index == 2) return;
    Navigator.pushReplacementNamed(
      context,
      '/main-app',
      arguments: {'index': index},
    );
  }

  void _onAddPressed() {
    if (AuthService.instance.currentUser == null) {
      Navigator.pushNamed(context, '/login', arguments: '/emergency-live');
      return;
    }
    Navigator.pushNamed(context, '/emergency-live');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      extendBody: true,
      bottomNavigationBar: TlzBottomNavigationBar(
        currentIndex: -1,
        isVisible: isNavBarVisible,
        onIndexChanged: _onNavIndexChanged,
        onAddPressed: _onAddPressed,
      ),
      body: Column(
        children: [
          // Custom Header matching sport club page style
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: TlzAppTopBar.onPrimary(
                  leading: IconButton(
                    tooltip: 'ย้อนกลับ',
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                    ),
                    onPressed: _goBack,
                  ),
                  middle: const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'ตรวจคำขอเพิ่มประเภทกีฬา',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'รีเฟรช',
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _load,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Body content
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
              ),
              child: wrapScrollNotification(child: _buildBody()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text(
              'โหลดไม่สำเร็จ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 48,
              color: Colors.green,
            ),
            const SizedBox(height: 12),
            const Text(
              'ไม่มีคำขอที่รอตรวจ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('รีเฟรช'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => _load(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final s = _items[i];
          final layout = s['field_layout']?.toString() ?? 'none';
          final layoutLabel = layout == 'double'
              ? 'สนาม 2 ฝั่ง'
              : (layout == 'single' ? 'สนาม 1 ฝั่ง' : 'ไม่ใช้สนาม');

          return Card(
            child: ListTile(
              leading: Text.rich(
                TextSpan(
                  text: s['icon']?.toString() ?? '🏅',
                  style: _emojiTextStyle(
                    context,
                  ).merge(const TextStyle(fontSize: 24)),
                ),
              ),
              title: Text(s['name_th']?.toString() ?? ''),
              subtitle: Text('${s['name_en'] ?? ''} • แนะนำ: $layoutLabel'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _reject(s['id'].toString()),
                    icon: const Icon(Icons.close, color: Colors.red),
                  ),
                  IconButton(
                    onPressed: () => _approve(s),
                    icon: const Icon(Icons.check, color: Colors.green),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
