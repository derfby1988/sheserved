import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../services/websocket_service.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../admin/models/profession.dart';
import '../../../admin/data/repositories/profession_repository.dart';
import '../../data/repositories/donation_repository.dart';
import '../../models/donation_models.dart';
import '../../../../features/video/data/repositories/video_repository.dart';
import '../../../../features/video/presentation/pages/emergency_live_page.dart';
import '../../../../features/video/models/video_models.dart';
import '../../../../config/app_config.dart';
import '../../../../shared/widgets/thai_buddhist_date_picker.dart';

class DonationAdminPage extends StatefulWidget {
  const DonationAdminPage({super.key});

  @override
  State<DonationAdminPage> createState() => _DonationAdminPageState();
}

class _DonationAdminPageState extends State<DonationAdminPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DonationRepository _repository;
  String? _currentUserId;
  bool _isStorageAdmin = false;

  @override
  void initState() {
    super.initState();
    // ดึงค่า tab index เริ่มต้นจาก arguments (ถ้ามี)
    int initialIndex = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is int) {
        _tabController.animateTo(args);
      } else if (args is Map<String, dynamic> && args.containsKey('initialIndex')) {
        _tabController.animateTo(args['initialIndex'] as int);
      }
    });

    _tabController = TabController(length: 4, vsync: this, initialIndex: initialIndex);
    _repository = DonationRepository(Supabase.instance.client);
    _loadUserContext();
  }

  Future<void> _loadUserContext() async {
    // ✅ ใช้ ServiceLocator ตาม Auth Data Guidelines (ห้ามใช้ Supabase Auth โดยตรง)
    final user = ServiceLocator.instance.currentUser;
    if (user != null) {
      // ✅ Bug #4 Fix: ตรวจสอบ role จาก DB จริง แทน hardcode true
      final isAdmin = await _repository.isStorageAdmin(user.id);
      if (mounted) {
        setState(() {
          _currentUserId = user.id;
          _isStorageAdmin = isAdmin;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 60),
        child: Container(
          color: AppColors.primary,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'จัดการระบบบริจาค',
                        style: AppTextStyles.heading3.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  isScrollable: true,
                  tabs: const [
                    Tab(text: 'หมวดหมู่'),
                    Tab(text: 'ศูนย์อนุมัติ'),
                    Tab(text: 'ช่วยเหลือฉุกเฉิน'),
                    Tab(text: 'ประวัติ'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _CategoryManagementPanel(repository: _repository),
          _ApprovalCenterPanel(repository: _repository, userId: _currentUserId, isStorageAdmin: _isStorageAdmin),
          _ResponderHelpPanel(userId: _currentUserId),
          _ContributionHistoryPanel(repository: _repository),
        ],
      ),
    );
  }
}

/// แผงจัดการหมวดหมู่
class _CategoryManagementPanel extends StatefulWidget {
  final DonationRepository repository;
  const _CategoryManagementPanel({required this.repository});

  @override
  State<_CategoryManagementPanel> createState() => _CategoryManagementPanelState();
}

class _CategoryManagementPanelState extends State<_CategoryManagementPanel> {
  List<DonationCategory> _categories = [];
  List<Profession> _volunteerProfessions = []; // สำหรับ dialog สิทธิ์จิตอาสา
  List<UserCategory> _userCategories = [];      // สำหรับ dialog Flow อนุมัติ
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadProfessions();
  }

  Future<void> _loadProfessions() async {
    try {
      final repo = ProfessionRepository(Supabase.instance.client);
      final profList = await repo.getAllProfessions();
      final catList = await repo.getAllUserCategories();
      if (mounted) {
        setState(() {
          _volunteerProfessions = profList.where((p) => p.isVolunteer).toList();
          _userCategories = catList;
        });
      }
    } catch (e) {
      debugPrint('Error loading professions/categories: $e');
    }
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    try {
      final cats = await widget.repository.getCategories();
      setState(() {
        _categories = cats;
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
    }
  }

  void _showCategoryDialog([DonationCategory? category]) {
    final nameController = TextEditingController(text: category?.name);
    final iconController = TextEditingController(text: category?.iconName);
    bool isEmergency = category?.isEmergency ?? false;
    bool isSaving = false;

    final List<Map<String, dynamic>> availableIcons = [
      {'name': 'emergency_share', 'icon': Icons.emergency_share, 'label': 'ฉุกเฉิน / แชร์'},
      {'name': 'gavel', 'icon': Icons.gavel, 'label': 'กฎหมาย / ค้อน'},
      {'name': 'local_fire_department', 'icon': Icons.local_fire_department, 'label': 'ไฟไหม้ / ดับเพลิง'},
      {'name': 'water_damage', 'icon': Icons.water_damage, 'label': 'น้ำท่วม'},
      {'name': 'payments', 'icon': Icons.payments, 'label': 'การเงิน'},
      {'name': 'inventory_2', 'icon': Icons.inventory_2, 'label': 'สิ่งของ / กล่อง'},
      {'name': 'restaurant', 'icon': Icons.restaurant, 'label': 'อาหาร'},
      {'name': 'favorite', 'icon': Icons.favorite, 'label': 'ความรัก / หัวใจ'},
      {'name': 'home', 'icon': Icons.home, 'label': 'ที่พัก / บ้าน'},
      {'name': 'local_shipping', 'icon': Icons.local_shipping, 'label': 'เดินทาง / ขนส่ง'},
      {'name': 'elderly', 'icon': Icons.elderly, 'label': 'ผู้สูงอายุ / ผู้ป่วย'},
      {'name': 'healing', 'icon': Icons.healing, 'label': 'ปฐมพยาบาล / การแพทย์'},
      {'name': 'pets', 'icon': Icons.pets, 'label': 'สัตว์เลี้ยง'},
      {'name': 'warning', 'icon': Icons.warning_amber_rounded, 'label': 'แจ้งเตือน / ระวัง'},
    ];

    String selectedIcon = category?.iconName ?? 'favorite';
    if (!availableIcons.any((i) => i['name'] == selectedIcon)) {
      selectedIcon = 'favorite'; // Default fallback
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(category == null ? 'เพิ่มหมวดหมู่' : 'แก้ไขหมวดหมู่', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'ชื่อหมวดหมู่')),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedIcon,
                  decoration: InputDecoration(
                    labelText: 'สัญลักษณ์/ไอคอน',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  items: availableIcons.map((i) => DropdownMenuItem(
                    value: i['name'] as String,
                    child: Row(
                      children: [
                        Icon(i['icon'] as IconData, color: Colors.teal),
                        const SizedBox(width: 12),
                        Text(i['label'] as String),
                      ]
                    )
                  )).toList(),
                  onChanged: (val) {
                     if (val != null) {
                       setDialogState(() {
                         selectedIcon = val;
                         iconController.text = val;
                       });
                     }
                  }
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('เป็นเหตุฉุกเฉิน?', style: TextStyle(fontWeight: FontWeight.w500)),
                  value: isEmergency,
                  activeColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Colors.grey.shade50,
                  onChanged: isSaving ? null : (val) => setDialogState(() => isEmergency = val),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('กรุณากรอกชื่อหมวดหมู่')),
                        );
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      try {
                        final data = {
                          'name': nameController.text.trim(),
                          'icon_name': selectedIcon, // Save the selected icon
                          'is_emergency': isEmergency,
                          'volunteer_profession_ids': category?.volunteerProfessionIds ?? [],
                          // ไม่แตะ approver_profession_ids — จัดการใน Flow อนุมัติ dialog
                          'approver_profession_ids': category?.approverProfessionIds ?? [],
                        };
                        if (category == null) {
                          await widget.repository.createCategory(data);
                        } else {
                          await widget.repository.updateCategory(category.id, data);
                        }
                        await _loadCategories();
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(category == null
                                  ? 'เพิ่มหมวดหมู่ "${nameController.text.trim()}" สำเร็จ ✓'
                                  : 'บันทึกหมวดหมู่ "${nameController.text.trim()}" สำเร็จ ✓'),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      } catch (e) {
                        debugPrint('Error saving category: $e');
                        setDialogState(() => isSaving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('บันทึกไม่สำเร็จ: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  void _showVolunteerProfessionsDialog(DonationCategory category) {
    if (_volunteerProfessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีข้อมูลวิชาชีพจิตอาสาในระบบ')),
      );
      return;
    }

    List<String> selectedVolunteers = List.from(category.volunteerProfessionIds);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.volunteer_activism, color: Colors.blue),
              const SizedBox(width: 8),
              const Expanded(child: Text('สิทธิ์จิตอาสา', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('เลือกวิชาชีพที่มีสิทธิ์ให้ความช่วยเหลือในหมวด "${category.name}"',
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 16),
                ..._volunteerProfessions.map((prof) {
                  final isSelected = selectedVolunteers.contains(prof.id);
                  return Card(
                    elevation: 0,
                    color: isSelected ? Colors.blue.withValues(alpha: 0.05) : Colors.grey.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: isSelected ? Colors.blue.withValues(alpha: 0.3) : Colors.transparent),
                    ),
                    child: CheckboxListTile(
                      title: Text(prof.name, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      value: isSelected,
                      activeColor: Colors.blue,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: isSaving ? null : (val) {
                        setDialogState(() {
                          if (val == true) selectedVolunteers.add(prof.id);
                          else selectedVolunteers.remove(prof.id);
                        });
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        final data = {
                          'volunteer_profession_ids': selectedVolunteers,
                        };
                        await widget.repository.updateCategory(category.id, data);
                        await _loadCategories();
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('อัปเดตสิทธิ์จิตอาสาสำเร็จ ✓'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('บันทึก', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog แยกสำหรับการกำหนด Flow การอนุมัติ + ลากเรียงลำดับ (approver_profession_ids)
  void _showApproverDialog(DonationCategory category) {
    List<String> orderedApprovers = List.from(category.approverProfessionIds);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // หาชื่อหมวดหมู่จาก ID
          String catName(String id) {
            final c = _userCategories.where((c) => c.id == id).firstOrNull;
            return c?.name ?? id;
          }

          // โหลดข้อมูล icon
          IconData catIcon(String id) {
            final c = _userCategories.where((c) => c.id == id).firstOrNull;
            switch (c?.iconName) {
              case 'gavel': return Icons.gavel;
              case 'store': return Icons.store;
              case 'shopping_cart': return Icons.shopping_cart;
              case 'local_hospital': return Icons.local_hospital;
              default: return Icons.group;
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.account_tree, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Flow การอนุมัติ',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      Text(category.name,
                          style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.normal)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // — Header —
                    Row(children: [
                      const Icon(Icons.add_circle_outline, size: 14, color: Colors.teal),
                      const SizedBox(width: 4),
                      Text('เลือกหมวดหมู่ผู้ใช้ที่ต้องอนุมัติ',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal[800])),
                    ]),
                    const SizedBox(height: 2),
                    const Text('ผู้ใช้ที่มีอาชีพอยู่ในหมวดหมู่นี้จะได้รับสิทธิ์เป็นผู้อนุมัติตามสถานะจากตารางจริง',
                        style: TextStyle(fontSize: 10, color: Colors.grey)),
                    const SizedBox(height: 8),
                    // — Checklist หมวดหมู่ผู้ใช้ —
                    if (_userCategories.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('ได้รับข้อมูลหมวดหมู่ที่ใช้งานไม่มี (โหลดอยู่...)',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                      )
                    else
                      ..._userCategories.map((uc) {
                        final isSelected = orderedApprovers.contains(uc.id);
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: Colors.teal,
                          secondary: Icon(catIcon(uc.id), color: Colors.teal, size: 20),
                          title: Text(uc.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: uc.description != null && uc.description!.isNotEmpty
                              ? Text(uc.description!, style: const TextStyle(fontSize: 10, color: Colors.grey))
                              : null,
                          value: isSelected,
                          onChanged: isSaving ? null : (val) {
                            setDialogState(() {
                              if (val == true) orderedApprovers.add(uc.id);
                              else orderedApprovers.remove(uc.id);
                            });
                          },
                        );
                      }),
                    // — Reorder —
                    if (orderedApprovers.isNotEmpty) ...[
                      const Divider(height: 24),
                      Row(children: [
                        const Icon(Icons.drag_indicator, size: 14, color: Colors.teal),
                        const SizedBox(width: 4),
                        Text('ลำดับการอนุมัติ (ลากเพื่อเรียง)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal[800])),
                      ]),
                      const SizedBox(height: 2),
                      const Text('ลำดับ 1 → อนุมัติก่อน, ตามด้วยลำดับถัดไป',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: (orderedApprovers.length * 56.0).clamp(56.0, 280.0),
                        child: ReorderableListView(
                          shrinkWrap: true,
                          onReorder: isSaving
                              ? (a, b) {}
                              : (oldIndex, newIndex) {
                                  setDialogState(() {
                                    if (newIndex > oldIndex) newIndex--;
                                    final item = orderedApprovers.removeAt(oldIndex);
                                    orderedApprovers.insert(newIndex, item);
                                  });
                                },
                          children: List.generate(orderedApprovers.length, (i) {
                            final id = orderedApprovers[i];
                            return ListTile(
                              key: ValueKey(id),
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                              leading: Container(
                                width: 28, height: 28,
                                decoration: const BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
                                child: Center(
                                  child: Text('${i + 1}',
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              title: Text(catName(id), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              trailing: const Icon(Icons.drag_handle, color: Colors.grey),
                            );
                          }),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text('ยกเลิก'),
              ),
              ElevatedButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        try {
                          await widget.repository.updateCategory(category.id, {
                            'approver_profession_ids': orderedApprovers,
                          });
                          await _loadCategories();
                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('บันทึก Flow การอนุมัติสำเร็จ ✓'),
                                backgroundColor: Colors.teal,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('บันทึกไม่สำเร็จ: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                icon: isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, size: 16),
                label: const Text('บันทึก Flow'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCustomFieldsDialog(DonationCategory category) {
    List<DonationCategoryField> fields = List.from(category.customFields);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('จัดการฟิลด์เพิ่มเติม'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (fields.isEmpty) const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('ยังไม่มีฟิลด์เพิ่มเติม'),
                  ),
                  if (fields.isNotEmpty) Expanded(
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      itemCount: fields.length,
                      onReorder: (oldIndex, newIndex) {
                        setDialogState(() {
                          if (newIndex > oldIndex) {
                            newIndex -= 1;
                          }
                          final item = fields.removeAt(oldIndex);
                          fields.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final field = fields[index];
                        return ListTile(
                          key: ValueKey(field.id),
                          leading: const Icon(Icons.drag_handle, color: Colors.grey),
                          title: Text(field.label),
                          subtitle: Text('ID: ${field.id} | Type: ${field.type} | Required: ${field.isRequired}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                tooltip: 'แก้ไข',
                                onPressed: () async {
                                  final editedField = await _showAddFieldDialog(existingField: field);
                                  if (editedField != null) {
                                    setDialogState(() {
                                      fields[index] = editedField;
                                    });
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  setDialogState(() {
                                    fields.removeAt(index);
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final newField = await _showAddFieldDialog();
                      if (newField != null) {
                        setDialogState(() {
                          fields.add(newField);
                        });
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มฟิลด์'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
              TextButton(
                onPressed: () async {
                  try {
                    await widget.repository.updateCategory(category.id, {
                      'custom_fields': fields.map((e) => e.toJson()).toList(),
                    });
                    if (context.mounted) Navigator.pop(context);
                    _loadCategories();
                  } catch (e) {
                    debugPrint('Error saving custom fields: $e');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('บันทึกไม่สำเร็จ: $e'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  }
                },
                child: const Text('บันทึก'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showGlobalFieldsDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final fields = await widget.repository.getGlobalFields();
      if (context.mounted) Navigator.pop(context); // close loading

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.settings, color: Colors.teal),
                    SizedBox(width: 8),
                    Text('จัดการฟอร์มพื้นฐาน'),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'ข้อมูลเหล่านี้คือช่องที่ผู้ร้องขอทุกคนต้องกรอกเป็นพื้นฐาน คุณสามารถแก้ไข ลบ หรือเพิ่มให้ตรงกับความต้องการของระบบได้',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                      if (fields.isEmpty) const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('ไม่มีฟอร์มพื้นฐาน'),
                      ),
                      if (fields.isNotEmpty) Expanded(
                        child: ReorderableListView.builder(
                          shrinkWrap: true,
                          itemCount: fields.length,
                          onReorder: (oldIndex, newIndex) {
                            setDialogState(() {
                              if (newIndex > oldIndex) newIndex -= 1;
                              final item = fields.removeAt(oldIndex);
                              fields.insert(newIndex, item);
                            });
                          },
                          itemBuilder: (context, index) {
                            final field = fields[index];
                            return ListTile(
                              key: ValueKey(field.id),
                              leading: const Icon(Icons.drag_handle, color: Colors.grey),
                              title: Text(field.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('ID: ${field.id} | Type: ${field.type} | Required: ${field.isRequired}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    tooltip: 'แก้ไข',
                                    onPressed: () async {
                                      final updatedField = await _showAddFieldDialog(existingField: field);
                                      if (updatedField != null) {
                                        setDialogState(() {
                                          fields[index] = updatedField;
                                        });
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    tooltip: 'ลบฟิลด์นี้',
                                    onPressed: () {
                                      setDialogState(() {
                                        fields.removeAt(index);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(),
                      TextButton.icon(
                        onPressed: () async {
                          final newField = await _showAddFieldDialog();
                          if (newField != null) {
                            setDialogState(() {
                              fields.add(newField);
                            });
                          }
                        },
                        icon: const Icon(Icons.add_circle, color: Colors.teal),
                        label: const Text('เพิ่มช่องข้อมูลใหม่', style: TextStyle(color: Colors.teal)),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey))),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await widget.repository.saveGlobalFields(fields);
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกฟอร์มพื้นฐานเรียบร้อยแล้ว'), backgroundColor: Colors.green));
                        }
                      } catch (e) {
                        debugPrint('Error saving global fields: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e'), backgroundColor: Colors.red));
                        }
                      }
                    },
                    icon: const Icon(Icons.save, color: Colors.white, size: 18),
                    label: const Text('บันทึกการจัดเรียง', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  ),
                ],
              );
            },
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // close loading
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    }
  }

  Future<DonationCategoryField?> _showAddFieldDialog({DonationCategoryField? existingField}) {
    final labelController = TextEditingController(text: existingField?.label ?? '');
    final idController = TextEditingController(text: existingField?.id ?? '');
    String type = existingField?.type ?? 'text';
    bool isRequired = existingField?.isRequired ?? false;

    return showDialog<DonationCategoryField>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(existingField == null ? 'เพิ่มฟิลด์ใหม่' : 'แก้ไขฟิลด์'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: idController, decoration: const InputDecoration(labelText: 'ID (ภาษาอังกฤษห้ามเว้นวรรค)')),
                TextField(controller: labelController, decoration: const InputDecoration(labelText: 'ชื่อฟิลด์ (Label)')),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'ประเภทข้อมูล'),
                  items: const [
                    DropdownMenuItem(value: 'text', child: Text('ข้อความสั้น (Text)')),
                    DropdownMenuItem(value: 'long_text', child: Text('ข้อความยาว (Long Text)')),
                    DropdownMenuItem(value: 'number', child: Text('ตัวเลข (Number)')),
                    DropdownMenuItem(value: 'date', child: Text('วันที่ (Date)')),
                    DropdownMenuItem(value: 'community_dropdown', child: Text('เลือกชุมชน (Community Dropdown)')),
                    DropdownMenuItem(value: 'address_picker', child: Text('ที่อยู่แบบละเอียดยืนยันพื้นที่ (Address)')),
                    DropdownMenuItem(value: 'boolean', child: Text('สวิตช์เปิด/ปิด (Switch Boolean)')),
                    DropdownMenuItem(value: 'image', child: Text('รูปภาพอัปโหลด (Image Upload)')),
                  ],
                  onChanged: (val) => setDialogState(() => type = val!),
                ),
                SwitchListTile(
                  title: const Text('จำเป็นต้องกรอก?'),
                  value: isRequired,
                  onChanged: (val) => setDialogState(() => isRequired = val),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
              TextButton(
                onPressed: () {
                  if (idController.text.isEmpty || labelController.text.isEmpty) return;
                  Navigator.pop(context, DonationCategoryField(
                    id: idController.text,
                    label: labelController.text,
                    type: type,
                    isRequired: isRequired,
                  ));
                },
                child: const Text('เพิ่ม'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showGlobalFieldsDialog(),
                  icon: const Icon(Icons.settings_applications, color: Colors.white),
                  label: const Text('ตั้งค่าข้อมูลพื้นฐาน', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showCategoryDialog(),
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('เพิ่มหมวดหมู่ใหม่', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _categories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.category_outlined, size: 56, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text('ยังไม่มีหมวดหมู่', style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[100]!),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // ไอคอนหมวดหมู่
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: cat.isEmergency ? Colors.red.shade50 : AppColors.primary.withOpacity(0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    cat.isEmergency ? Icons.emergency : Icons.category,
                                    color: cat.isEmergency ? Colors.red : AppColors.primary,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // ชื่อหมวดหมู่
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cat.name,
                                        style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                      if (cat.nameEn != null)
                                        Text(
                                          cat.nameEn!,
                                          style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[500]),
                                        ),
                                    ],
                                  ),
                                ),
                                // ลำดับ
                                Text(
                                  '#${cat.displayOrder}',
                                  style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[400]),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Badge + Approval Stepper
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (cat.isEmergency)
                                  _buildBadge('🚨 ฉุกเฉิน', Colors.red.shade50, Colors.red),
                                if (cat.volunteerProfessionIds.isNotEmpty)
                                  _buildBadge('👥 จิตอาสา ${cat.volunteerProfessionIds.length} อาชีพ', Colors.blue.shade50, Colors.blue),
                                if (cat.customFields.isNotEmpty)
                                  _buildBadge('📋 ${cat.customFields.length} ฟิลด์', Colors.orange.shade50, Colors.orange),
                              ],
                            ),
                            // Approval Stepper — แสดงเมื่อมีกลุ่มอาชีพที่ต้องอนุมัติ
                            if (cat.approverProfessionIds.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _buildApprovalStepper(cat.approverProfessionIds),
                            ],
                            const Divider(height: 18),
                            // ปุ่มจัดการ
                            Align(
                              alignment: Alignment.centerRight,
                              child: Scrollbar(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.only(bottom: 8), // เพิ่มพื้นที่ให้ scrollbar เล็กน้อย
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min, // ให้ Row มีขนาดเท่ากับปุ่มรวมกัน
                                    children: [
                                      _actionBtn(
                                        icon: Icons.list_alt_rounded,
                                        label: 'ฟิลด์บริจาค(เฉพาะ)',
                                        color: Colors.green,
                                        onTap: () => _showCustomFieldsDialog(cat),
                                      ),
                                      const SizedBox(width: 8),
                                      _actionBtn(
                                        icon: Icons.account_tree_rounded,
                                        label: 'ผู้อนุมัติบริจาค',
                                        color: Colors.teal,
                                        onTap: () => _showApproverDialog(cat),
                                      ),
                                      const SizedBox(width: 8),
                                      _actionBtn(
                                        icon: Icons.volunteer_activism_rounded,
                                        label: 'สิทธิ์อาสา',
                                        color: Colors.blue,
                                        onTap: () => _showVolunteerProfessionsDialog(cat),
                                      ),
                                      const SizedBox(width: 8),
                                      _actionBtn(
                                        icon: Icons.edit_rounded,
                                        label: 'แก้ไขหมวดหมู่',
                                        color: AppColors.primary,
                                        onTap: () => _showCategoryDialog(cat),
                                      ),
                                      const SizedBox(width: 8),
                                      _actionBtn(
                                        icon: Icons.delete_rounded,
                                        label: 'ลบหมวดหมู่', // แก้คำผิดหมวดหมุ่เป็นหมวดหมู่ด้วย
                                        color: Colors.red,
                                        onTap: () async {
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                              title: const Text('ยืนยันการลบ'),
                                              content: Text('ลบหมวดหมู่ "${cat.name}" ใช่หรือไม่?\nการกระทำนี้ไม่สามารถยกเลิกได้'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                  onPressed: () => Navigator.pop(ctx, true),
                                                  child: const Text('ลบ', style: TextStyle(color: Colors.white)),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirmed == true) {
                                            await widget.repository.deleteCategory(cat.id);
                                            _loadCategories();
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildApprovalStepper(List<String> approverIds) {
    if (_userCategories.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.teal.shade100),
        ),
        child: Shimmer.fromColors(
          baseColor: Colors.teal.shade200.withOpacity(0.5),
          highlightColor: Colors.teal.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 150, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 10),
              Row(
                children: List.generate(
                  approverIds.isNotEmpty ? approverIds.length : 2,
                  (index) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(height: 4, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  approverIds.isNotEmpty ? approverIds.length : 2,
                  (index) => Container(width: 40, height: 10, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // หาชื่อหมวดหมู่จาก _userCategories
    final steps = approverIds.map((id) {
      final cat = _userCategories.where((c) => c.id == id).firstOrNull;
      return cat?.name ?? id;
    }).toList();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.how_to_vote, size: 13, color: Colors.teal),
              const SizedBox(width: 4),
              Text(
                'ต้องผ่าน ${steps.length} กลุ่มอาชีพจึงเปิดรับบริจาคได้',
                style: const TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(steps.length, (i) {
              final isLast = i == steps.length - 1;
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          // Step circle + connector line
                          Row(
                            children: [
                              // Connector line ทางซ้าย
                              if (i > 0)
                                Expanded(
                                  child: Container(
                                    height: 2,
                                    color: Colors.teal.shade200,
                                  ),
                                ),
                              // Step circle
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.teal,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.teal.withValues(alpha: 0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              // Connector line ทางขวา
                              if (!isLast)
                                Expanded(
                                  child: Container(
                                    height: 2,
                                    color: Colors.teal.shade200,
                                  ),
                                )
                              else
                                const Expanded(child: SizedBox()),
                            ],
                          ),
                          const SizedBox(height: 5),
                          // ชื่ออาชีพ
                          Text(
                            steps[i],
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.teal,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _actionBtn({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// แผงศูนย์อนุมัติ (Approval Center)
class _ApprovalCenterPanel extends StatefulWidget {
  final DonationRepository repository;
  final String? userId;
  final bool isStorageAdmin;
  const _ApprovalCenterPanel({required this.repository, this.userId, required this.isStorageAdmin});

  @override
  State<_ApprovalCenterPanel> createState() => _ApprovalCenterPanelState();
}

class _ApprovalCenterPanelState extends State<_ApprovalCenterPanel> {
  List<DonationRequest> _pendingRequests = [];
  // ✅ Bug #2 Fix: เก็บ professionIds ของผู้ใช้ เพื่อส่งไปใน approveRequest()
  List<String> _userProfessionIds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    if (widget.userId == null) return;
    setState(() => _isLoading = true);
    final results = await Future.wait([
      widget.repository.getPendingRequests(widget.userId!, isAdminOverride: widget.isStorageAdmin),
      widget.repository.getUserApproverProfessions(widget.userId!),
    ]);
    if (mounted) {
      setState(() {
        _pendingRequests = (results[0] as List<DonationRequest>)
            .where((r) => r.approvalStatus == DonationApprovalStatus.pending_local)
            .toList();
        _userProfessionIds = results[1] as List<String>;
        _isLoading = false;
      });
    }
  }

  Future<void> _doApprove(DonationRequest req) async {
    if (widget.userId == null) return;
    
    // แจ้งเตือนก่อนทำการลัดคิว
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin Override'),
        content: const Text('คุณกำลังจะใช้อำนาจแอดมินอนุมัติคำร้องนี้ลัดคิวทุกขั้นตอน ยืนยันหรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยืนยันอนุมัติ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await widget.repository.approveRequest(
        req.id, req.approvalStatus, widget.userId!,
        isAdminOverride: true,
      );
      _loadPending();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId == null) return const Center(child: Text('กรุณาเข้าสู่ระบบ'));
    if (!widget.isStorageAdmin) return const Center(child: Text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้ (เฉพาะ Admin)'));
    
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'ภาพรวมคำร้องรออนุมัติทั้งหมด (Admin Override)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        Expanded(
          child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _pendingRequests.isEmpty
                ? const Center(child: Text('ไม่มีรายการรออนุมัติ'))
                : ListView.builder(
                    itemCount: _pendingRequests.length,
                    itemBuilder: (context, index) {
                      final req = _pendingRequests[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          title: Text(req.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('สถานะปัจจุบัน: ${_getStatusLabel(req.approvalStatus)}'),
                              if (req.approvalStatus == DonationApprovalStatus.pending_local) ...[
                                const SizedBox(height: 4),
                                Text('📍 สถานที่ใช้: ${req.usageLocation ?? "-"}', style: const TextStyle(fontSize: 12)),
                                Text('🏠 ที่อยู่ผู้ร้อง: ${req.requesterAddress ?? "-"}', style: const TextStyle(fontSize: 12)),
                              ],
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                                // ✅ Bug #2 Fix: ใช้ _doApprove() ที่ส่ง professionId ที่ถูกต้อง
                                onPressed: () async {
                                  try {
                                    await _doApprove(req);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('✅ ยืนยันคำร้องสำเร็จ'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('เกิดข้อผิดพลาด: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.red),
                                onPressed: () async {
                                  await widget.repository.rejectRequest(req.id);
                                  _loadPending();
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  String _getStatusLabel(DonationApprovalStatus status) {
    switch (status) {
      case DonationApprovalStatus.pending_local: return 'รอผู้นำชุมชนยืนยัน';
      default: return 'อื่นๆ';
    }
    }
  }


/// แผงประวัติการบริจาค
class _ContributionHistoryPanel extends StatefulWidget {
  final DonationRepository repository;
  const _ContributionHistoryPanel({required this.repository});

  @override
  State<_ContributionHistoryPanel> createState() => _ContributionHistoryPanelState();
}

class _ContributionHistoryPanelState extends State<_ContributionHistoryPanel> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final history = await widget.repository.getContributions();
      setState(() {
        _history = history;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return ListView.builder(
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final item = _history[index];
        final user = item['user'] as Map?;
        final request = item['request'] as Map?;
        return ListTile(
          leading: const Icon(Icons.history, color: Colors.green),
          title: Text('${user?['username'] ?? 'ไม่ระบุชื่อ'} บริจาค ${item['amount']} บาท'),
          subtitle: Text('ให้กับ: ${request?['title'] ?? 'ไม่ทราบรายการ'}'),
          trailing: Text(item['created_at'].toString().split('T')[0]),
        );
      },
    );
  }
}

/// แผงช่วยเหลือฉุกเฉินสำหรับอาชีพ (Responder Help Panel)
class _ResponderHelpPanel extends StatefulWidget {
  final String? userId;
  const _ResponderHelpPanel({this.userId});

  @override
  State<_ResponderHelpPanel> createState() => _ResponderHelpPanelState();
}

class _ResponderHelpPanelState extends State<_ResponderHelpPanel> {
  late VideoRepository _videoRepository;
  List<Video> _emergencyVideos = [];
  bool _isLoading = true;
  Position? _currentPosition;
  StreamSubscription? _emergencySub;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _videoRepository = ServiceLocator.instance.videoRepository;
    _loadEmergencyVideos();

    // Listen for new emergency alerts via WebSocket and auto-refresh
    _emergencySub = WebSocketService().emergencyNotificationStream.listen((data) {
      debugPrint('ResponderHelpPanel: Received emergency notification, refreshing list...');
      _loadEmergencyVideos();
    });

    // Periodic refresh every 10 seconds to catch any missed events
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _loadEmergencyVideos();
    });
  }

  @override
  void dispose() {
    _emergencySub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadEmergencyVideos() async {
    if (!mounted) return;
    setState(() => _isLoading = _emergencyVideos.isEmpty); // Only show loading on first load
    try {
      // 1. Get Current Location for distance calculation
      try {
        _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('Error getting location: $e');
      }

      // 2. Load Categories for Filtering
      final repo = ServiceLocator.instance.donationRepository;
      final emergencyCategories = await repo.getEmergencyCategories();
      final user = AuthService.instance.currentUser;
      
      // 3. Load Videos
      debugPrint('ResponderHelpPanel: Loading videos from ${AppConfig.localApiUrl}');
      final allVideos = await _videoRepository.getEmergencyVideos();
      
      // 4. Filter Videos by Role
      List<Video> filteredVideos = [];
      if (user != null) {
        for (var video in allVideos) {
          bool isRelevant = false;
          final categoryId = video.categoryId;
          
          if (categoryId != null) {
            final category = emergencyCategories.any((c) => c.id == categoryId) 
                ? emergencyCategories.firstWhere((c) => c.id == categoryId)
                : null;
            
            if (category != null) {
              if (user.professionId != null && category.volunteerProfessionIds.contains(user.professionId)) {
                isRelevant = true;
              }
            } else {
               // Fallback
               isRelevant = true;
            }
          } else {
            // General emergency without category
            isRelevant = true;
          }
          
          if (isRelevant) {
            filteredVideos.add(video);
          }
        }
      }

      debugPrint('ResponderHelpPanel: Loaded ${filteredVideos.length} filtered videos (out of ${allVideos.length})');
      if (mounted) {
        setState(() {
          _emergencyVideos = filteredVideos;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading emergency videos: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatAddress(Video video) {
    List<String> parts = [];
    if (video.village != null && video.village!.isNotEmpty) parts.add('หมู่บ้าน ${video.village}');
    if (video.road != null && video.road!.isNotEmpty) parts.add('ถนน ${video.road}');
    if (video.soi != null && video.soi!.isNotEmpty) parts.add('ซอย ${video.soi}');
    if (video.alley != null && video.alley!.isNotEmpty) parts.add('ตรอก ${video.alley}');
    if (video.address != null && video.address!.isNotEmpty) parts.add(video.address!);
    
    if (parts.isEmpty) return 'ไม่ระบุที่อยู่ละเอียด';
    return parts.join(' ');
  }

  String _getDistanceLabel(Video video) {
    if (_currentPosition == null || video.latitude == 0 || video.longitude == 0) {
      return 'ไม่ทราบระยะทาง';
    }
    
    double distanceInMeters = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      video.latitude,
      video.longitude,
    );
    
    if (distanceInMeters < 1000) {
      return 'ห่างจากคุณ ${distanceInMeters.toStringAsFixed(0)} เมตร';
    } else {
      return 'ห่างจากคุณ ${(distanceInMeters / 1000).toStringAsFixed(1)} กม.';
    }
  }

  Future<void> _handleAcceptHelp(Video video) async {
    if (widget.userId == null) return;
    
    // Show loading state
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('กำลังบันทึกการตอบรับ...')),
    );

    try {
      // 1. สร้าง Record การตอบรับ (Real API call)
      final responseId = await _videoRepository.acceptIncident(
        videoId: video.id,
        responderId: widget.userId!,
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
      );
      
      if (responseId == null) {
        throw Exception('ไม่สามารถบันทึกการตอบรับได้ กรุณาลองใหม่');
      }

      // 2. ไปที่หน้า EmergencyLivePage ทันที
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EmergencyLivePage(
              videoId: video.id,
              responseId: responseId, // Pass the response tracking ID
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId == null) return const Center(child: Text('กรุณาเข้าสู่ระบบ'));

    return RefreshIndicator(
      onRefresh: _loadEmergencyVideos,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'เหตุฉุกเฉินที่กำลังเกิดขึ้น (Active Emergencies)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _emergencyVideos.isEmpty
                    ? const Center(child: Text('ไม่มีเหตุฉุกเฉินในขณะนี้'))
                    : ListView.builder(
                        itemCount: _emergencyVideos.length,
                        itemBuilder: (context, index) {
                          final video = _emergencyVideos[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Column(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.emergency, color: Colors.red),
                                  title: Text(video.title ?? 'ไม่ระบุชื่อเหตุการณ์'),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_formatAddress(video), 
                                        style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                      const SizedBox(height: 4),
                                      Text(_getDistanceLabel(video), 
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                                    ],
                                  ),
                                  trailing: const Icon(Icons.live_tv, color: Colors.green),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                  child: ElevatedButton(
                                    onPressed: () => _handleAcceptHelp(video),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(double.infinity, 45),
                                    ),
                                    child: const Text('ฉันพร้อมช่วยเหลือ (Accept Help)', 
                                      style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
