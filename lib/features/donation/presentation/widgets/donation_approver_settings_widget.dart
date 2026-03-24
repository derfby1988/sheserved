import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/repositories/donation_repository.dart';
import '../../models/donation_models.dart';
import '../../../../core/constants/app_text_styles.dart';

/// Widget การตั้งค่าผู้อนุมัติบริจาค
/// แสดงในแถบ "อนุมัติบริจาค" ของหน้าโปรไฟล์
/// - ผู้ใช้ที่มีสิทธิ์อนุมัติ (ตามหมวดหมู่ผู้ใช้ที่ถูกกำหนด can_approve_donation=true)
///   จะเห็นหมวดหมู่บริจาคทั้งหมดที่ระบุว่าหมวดหมู่ผู้ใช้นั้นต้องอนุมัติ
///   และสามารถเปิด/ปิดการรับผิดชอบแต่ละหมวดหมู่ได้
class DonationApproverSettingsWidget extends StatefulWidget {
  final DonationRepository repository;
  final String? userId;

  const DonationApproverSettingsWidget({
    super.key,
    required this.repository,
    required this.userId,
  });

  @override
  State<DonationApproverSettingsWidget> createState() =>
      _DonationApproverSettingsWidgetState();
}

class _DonationApproverSettingsWidgetState
    extends State<DonationApproverSettingsWidget> {
  List<DonationCategory> _relevantCategories = []; // หมวดหมู่ที่หมวดผู้ใช้นี้ต้องอนุมัติ
  Map<String, bool> _categoryToggles = {};
  int _approvalRadius = 500;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant DonationApproverSettingsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userId != oldWidget.userId) _loadData();
  }

  Future<void> _loadData() async {
    if (widget.userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      // 1. โหลด 3 อย่างแบบ parallel โดยแยก type ให้ชัดเจน
      final catsFuture = widget.repository.getCategories();
      final regFuture = Supabase.instance.client
          .from('user_registration_data')
          .select()
          .eq('user_id', widget.userId!)
          .withConverter<List<dynamic>>((data) => data);
      final userFuture = Supabase.instance.client
          .from('users')
          .select('profession_id')
          .eq('id', widget.userId!)
          .maybeSingle();

      final cats = await catsFuture;
      final regRows = await regFuture;
      final userRow = await userFuture;

      // 2. หา userCategoryId ผ่าน profession
      String? userCatId;
      if (userRow?['profession_id'] != null) {
        final profRow = await Supabase.instance.client
            .from('professions')
            .select('category')
            .eq('id', userRow!['profession_id'] as String)
            .maybeSingle();
        userCatId = profRow?['category'] as String?;
      }

      // 3. Parse saved settings
      int radius = 500;
      final Map<String, bool> toggles = {};
      for (var row in regRows) {
        final key = row['field_id'] as String;
        final val = row['field_value'] as String?;
        if (key == 'approval_radius' && val != null) {
          radius = int.tryParse(val) ?? 500;
        } else if (key.startsWith('approver_enabled_') && val != null) {
          final catId = key.replaceAll('approver_enabled_', '');
          toggles[catId] = (val == 'true');
        }
      }

      // 4. กรองเฉพาะหมวดหมู่บริจาคที่ user category นี้ต้องอนุมัติ
      //    approverProfessionIds ใน donation_categories จริงๆ เก็บ user_category IDs
      List<DonationCategory> relevant = [];
      if (userCatId != null) {
        relevant = cats
            .where((c) => c.approverProfessionIds.contains(userCatId))
            .toList();
      }

      // default toggle = true ถ้ายังไม่เคยบันทึก
      for (final cat in relevant) {
        if (!toggles.containsKey(cat.id)) {
          toggles[cat.id] = true;
        }
      }

      if (mounted) {
        setState(() {
          _relevantCategories = relevant;
          _categoryToggles = toggles;
          _approvalRadius = radius;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('DonationApproverSettingsWidget: Error loading: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSetting(String key, String value) async {
    if (widget.userId == null) return;
    try {
      await Supabase.instance.client.from('user_registration_data').upsert(
        {
          'user_id': widget.userId,
          'field_id': key,
          'field_value': value,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,field_id',
      );
    } catch (e) {
      debugPrint('DonationApproverSettingsWidget: Error saving $key: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_relevantCategories.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(Icons.admin_panel_settings_outlined,
                size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'ไม่มีหมวดหมู่บริจาคที่ต้องรับผิดชอบอนุมัติ',
              style: AppTextStyles.bodyMedium.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'ผู้ดูแลระบบสามารถกำหนด Flow การอนุมัติได้ที่หน้าจัดการระบบบริจาค',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey.shade400),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.admin_panel_settings, color: Colors.teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('สถานะผู้อนุมัติของคุณ',
                        style: AppTextStyles.heading3.copyWith(color: Colors.teal)),
                    Text('เลือกรับผิดชอบดูแลคำร้องตามหมวดหมู่',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: Colors.grey.shade600)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.teal, size: 20),
                onPressed: _loadData,
                tooltip: 'โหลดใหม่',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // Toggle ต่อหมวดหมู่
          ..._relevantCategories.map((cat) {
            final isEnabled = _categoryToggles[cat.id] ?? false;
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'เข้าร่วมอนุมัติหมวด: ${cat.name}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: cat.nameEn != null
                  ? Text(cat.nameEn!,
                      style: const TextStyle(fontSize: 11, color: Colors.grey))
                  : null,
              value: isEnabled,
              activeThumbColor: Colors.teal,
              onChanged: (val) {
                setState(() => _categoryToggles[cat.id] = val);
                _saveSetting('approver_enabled_${cat.id}', val.toString());
              },
            );
          }),

          const SizedBox(height: 16),

          // Radius Slider
          Text('พื้นที่อนุมัติการบริจาค',
              style: AppTextStyles.bodyMedium
                  .copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('ระยะจากที่อยู่ปัจจุบันถึงสถานที่ใช้บริจาค',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _approvalRadius.toDouble().clamp(500, 100000),
                  min: 500,
                  max: 100000,
                  divisions: 199,
                  activeColor: Colors.teal,
                  onChanged: (val) =>
                      setState(() => _approvalRadius = val.toInt()),
                  onChangeEnd: (val) =>
                      _saveSetting('approval_radius', val.toInt().toString()),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12)),
                child: Text(
                  _approvalRadius >= 1000
                      ? '${(_approvalRadius / 1000).toStringAsFixed(1)} กม.'
                      : '$_approvalRadius ม.',
                  style: const TextStyle(
                      color: Colors.teal, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
