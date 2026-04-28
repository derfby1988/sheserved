import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../models/profession.dart';
import '../../data/repositories/profession_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'group_members_admin_page.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../shared/widgets/online_providers_badge.dart';

/// Admin Page สำหรับจัดการอาชีพ
class ProfessionAdminPage extends StatefulWidget {
  const ProfessionAdminPage({super.key});

  @override
  State<ProfessionAdminPage> createState() => _ProfessionAdminPageState();
}

class _ProfessionAdminPageState extends State<ProfessionAdminPage> {
  List<Profession> _professions = [];
  bool _isLoading = true;
  final Map<String, int> _pendingCounts = {};

  @override
  void initState() {
    super.initState();
    _loadProfessions();
  }

  Future<void> _loadProfessions() async {
    setState(() => _isLoading = true);
    try {
      final repository = ProfessionRepository(Supabase.instance.client);
      final professions = await repository.getAllProfessions();
      if (mounted) {
        setState(() {
          // Sort explicitly by displayOrder to ensure correct order
          professions.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
          _professions = professions;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading professions: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    setState(() {
      final Profession movedItem = _professions.removeAt(oldIndex);
      _professions.insert(newIndex, movedItem);

      // Re-assign display orders dynamically based on current index
      for (int i = 0; i < _professions.length; i++) {
        _professions[i] = _professions[i].copyWith(displayOrder: i);
      }
    });

    try {
      final repository = ProfessionRepository(Supabase.instance.client);
      await repository.reorderProfessions(_professions);
    } catch (e) {
      debugPrint('Error reordering professions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึกการเรียงลำดับ: $e'), backgroundColor: AppColors.error),
        );
        _loadProfessions(); // Revert back to server order if failed
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const TlzDrawer(),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 16),
        child: Container(
          color: AppColors.primary,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TlzAppTopBar.onPrimary(
                searchHintText: 'ค้นหาอาชีพ...',
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildProfessionList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProfessionDialog,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'เพิ่มอาชีพใหม่',
          style: AppTextStyles.button.copyWith(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildProfessionList() {
    if (_professions.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.work_off_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'ไม่พบรายการอาชีพในขณะนี้',
              style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'กรุณากดปุ่ม "เพิ่มอาชีพใหม่" หรือตรวจสอบการเชื่อมต่อ',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadProfessions,
              icon: const Icon(Icons.refresh),
              label: const Text('โหลดใหม่'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    // Show all professions to allow full reordering and editing
    final displayProfessions = List<Profession>.from(_professions);
    displayProfessions.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    return RefreshIndicator(
      onRefresh: _loadProfessions,
      child: Column(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              header: Column(
                children: [
                   AllGroupsOnlinePanel(professions: displayProfessions, isAdminView: true),
                   const SizedBox(height: 20),
                   if (displayProfessions.isNotEmpty)
                     Padding(
                       padding: const EdgeInsets.only(bottom: 8.0),
                       child: Text(
                         'กดค้างแล้วลาก (Drag & Drop) เพื่อจัดเรียงลำดับรายการทั้งหมด',
                         style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
                       ),
                     ),
                ],
              ),
              itemCount: displayProfessions.length,
              itemBuilder: (context, index) {
                final profession = displayProfessions[index];
                return Padding(
                  key: ValueKey(profession.id),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                     children: [
                        Expanded(child: _buildProfessionCard(profession, margin: EdgeInsets.zero)),
                        const SizedBox(width: 8),
                        ReorderableDragStartListener(
                           index: index,
                           child: const Icon(Icons.drag_handle, color: Colors.grey),
                        ),
                     ],
                  ),
                );
              },
              onReorder: _handleReorder,
              proxyDecorator: (child, index, animation) {
                return Material(
                  color: Colors.transparent,
                  elevation: 6,
                  shadowColor: AppColors.primary.withOpacity(0.2),
                  child: child,
                );
              },
            ),
          ),
          const SizedBox(height: 80),
        ],
      )
    );
  }

  Widget _buildProfessionCard(Profession profession, {EdgeInsets? margin}) {
    final pendingCount = _pendingCounts[profession.id] ?? 0;

    return Card(
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: profession.isBuiltIn
              ? AppColors.primary.withOpacity(0.3)
              : AppColors.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Main Info Area - Tap to Config
          InkWell(
            onTap: () => _navigateToFieldConfig(profession),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (profession.colorHex != null 
                        ? Color(int.parse(profession.colorHex!.replaceFirst('#', '0xFF')))
                        : _getCategoryColor(profession.category)).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getIconData(profession.iconName),
                      color: profession.colorHex != null 
                        ? Color(int.parse(profession.colorHex!.replaceFirst('#', '0xFF')))
                        : _getCategoryColor(profession.category),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      profession.name,
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '#${profession.displayOrder}',
                                      style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (profession.isBuiltIn)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Built-in',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.primary,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            _buildCompactStat(Icons.list_alt, '${profession.fieldCount} ฟิลด์'),
                            _buildCompactStat(Icons.people_outline, '${profession.memberCount} คน'),
                            _buildCompactStat(
                              profession.category.id == UserCategory.consumerId ? Icons.person : Icons.business,
                              profession.category.displayName,
                            ),
                            if (profession.requiresVerification)
                              _buildCompactStat(Icons.verified_user, 'ต้องตรวจสอบ', color: AppColors.warning),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Actions Area - Independent of Card Tap
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (pendingCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.notification_important, size: 12, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          '$pendingCount รายการรอตรวจ',
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox.shrink(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildActionIcon(
                      Icons.group_add_outlined, 
                      Colors.blue, 
                      'จัดการสมาชิก',
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupMembersAdminPage(profession: profession))),
                    ),
                    _buildActionIcon(
                      Icons.edit_outlined, 
                      AppColors.primary, 
                      'แก้ไขอาชีพ',
                      () => _showEditProfessionDialog(profession),
                    ),
                    if (!profession.isBuiltIn) 
                      _buildActionIcon(
                        Icons.delete_outline, 
                        AppColors.error, 
                        'ลบอาชีพ',
                        () => _confirmDeleteProfession(profession),
                      ),
                    _buildActionIcon(
                      Icons.settings_outlined, 
                      AppColors.textHint, 
                      'ตั้งค่าฟิลด์',
                      () => _navigateToFieldConfig(profession),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStat(IconData icon, String label, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? AppColors.textHint),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: color ?? AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildActionIcon(IconData icon, Color color, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: color, size: 20),
      onPressed: onTap,
      tooltip: tooltip,
      splashRadius: 20,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(),
    );
  }

  Color _getCategoryColor(UserCategory category) {
    if (category.id == UserCategory.consumerId) {
      return Colors.blue;
    } else if (category.id == UserCategory.providerId) {
      return AppColors.primary;
    }
    return Colors.purple;
  }

  IconData _getIconData(String? iconName) {
    switch (iconName) {
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'store':
        return Icons.store;
      case 'local_hospital':
        return Icons.local_hospital;
      case 'person':
        return Icons.person;
      case 'medical_services':
        return Icons.medical_services;
      case 'delivery_dining':
        return Icons.delivery_dining;
      case 'engineering':
        return Icons.engineering;
      case 'gavel':
        return Icons.gavel;
      case 'school':
        return Icons.school;
      case 'restaurant':
        return Icons.restaurant;
      case 'spa':
        return Icons.spa;
      case 'fitness_center':
        return Icons.fitness_center;
      default:
        return Icons.work;
    }
  }

  void _navigateToFieldConfig(Profession profession) {
    Navigator.pushNamed(
      context,
      '/admin/registration-fields',
      arguments: profession,
    );
  }

  void _showAddProfessionDialog() async {
    debugPrint('Showing Add Profession Dialog');
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => ProfessionEditorDialog(
          onSave: (profession) {
            _loadProfessions();
            scaffoldMessenger.showSnackBar(
              SnackBar(
                content: Text('เพิ่มอาชีพ "${profession.name}" สำเร็จ'),
                backgroundColor: AppColors.success,
              ),
            );
          },
        ),
      );
    } catch (e) {
      debugPrint('Error showing dialog: $e');
    }
  }

  void _showEditProfessionDialog(Profession profession) async {
    debugPrint('Showing Edit Profession Dialog for: ${profession.name}');
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => ProfessionEditorDialog(
          existingProfession: profession,
          onSave: (updatedProfession) {
            _loadProfessions();
            scaffoldMessenger.showSnackBar(
              SnackBar(
                content: Text('แก้ไขอาชีพ "${updatedProfession.name}" เรียบร้อย'),
                backgroundColor: AppColors.success,
              ),
            );
          },
        ),
      );
    } catch (e) {
      debugPrint('Error showing dialog: $e');
    }
  }

  void _confirmDeleteProfession(Profession profession) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text(
            'ต้องการลบอาชีพ "${profession.name}" หรือไม่?\n\nการลบอาชีพจะลบ field configs ที่เกี่ยวข้องทั้งหมดด้วย'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
          onPressed: () async {
            final scaffoldMessenger = ScaffoldMessenger.of(context);
            final navigator = Navigator.of(context);
            try {
              final ProfessionRepository repo = ProfessionRepository(Supabase.instance.client);
              await repo.deleteProfession(profession.id);
              setState(() {
                _professions.removeWhere((p) => p.id == profession.id);
              });
              navigator.pop();
              scaffoldMessenger.showSnackBar(
                SnackBar(content: Text('ลบอาชีพ "${profession.name}" แล้ว')),
              );
            } catch (e) {
              scaffoldMessenger.showSnackBar(
                SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
              );
            }
          },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
  }
}

class ProfessionEditorDialog extends StatefulWidget {
  final Profession? existingProfession;
  final Function(Profession) onSave;

  const ProfessionEditorDialog({
    super.key,
    this.existingProfession,
    required this.onSave,
  });

  @override
  State<ProfessionEditorDialog> createState() => _ProfessionEditorDialogState();
}

class _ProfessionEditorDialogState extends State<ProfessionEditorDialog> {
  late TextEditingController _nameController;
  late TextEditingController _nameEnController;
  late TextEditingController _descriptionController;
  final List<UserCategory> _categories = [];
  bool _isCategoriesLoading = true;
  late UserCategory _selectedCategory;
  bool _requiresVerification = true;
  bool _isVolunteer = false;
  String _selectedIcon = 'work';
  String _selectedColor = '#71BE0A'; // Default to AppColors.primary
  String? _copyFromProfessionId;
  bool _isSaving = false;
  bool get isEditing => widget.existingProfession != null;

  final List<Map<String, dynamic>> _availableIcons = [
    {'name': 'work', 'icon': Icons.work, 'label': 'งานทั่วไป'},
    {'name': 'person', 'icon': Icons.person, 'label': 'บุคคล'},
    {'name': 'store', 'icon': Icons.store, 'label': 'ร้านค้า'},
    {'name': 'local_hospital', 'icon': Icons.local_hospital, 'label': 'โรงพยาบาล'},
    {'name': 'medical_services', 'icon': Icons.medical_services, 'label': 'บริการทางการแพทย์'},
    {'name': 'shopping_cart', 'icon': Icons.shopping_cart, 'label': 'การซื้อขาย'},
    {'name': 'delivery_dining', 'icon': Icons.delivery_dining, 'label': 'จัดส่ง'},
    {'name': 'engineering', 'icon': Icons.engineering, 'label': 'วิศวกรรม'},
    {'name': 'gavel', 'icon': Icons.gavel, 'label': 'กฎหมาย'},
    {'name': 'school', 'icon': Icons.school, 'label': 'การศึกษา'},
    {'name': 'restaurant', 'icon': Icons.restaurant, 'label': 'ร้านอาหาร'},
    {'name': 'spa', 'icon': Icons.spa, 'label': 'สปา/ความงาม'},
    {'name': 'fitness_center', 'icon': Icons.fitness_center, 'label': 'ฟิตเนส'},
  ];

  final List<String> _availableColors = [
    '#71BE0A', '#2196F3', '#FFC107', '#E91E63', '#9C27B0', '#00BCD4', '#FF9800', '#4CAF50', '#607D8B', '#795548',
  ];

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.existingProfession?.name ?? '');
    _nameEnController =
        TextEditingController(text: widget.existingProfession?.nameEn ?? '');
    _descriptionController =
        TextEditingController(text: widget.existingProfession?.description ?? '');
    
    _selectedCategory = widget.existingProfession?.category ?? 
        const UserCategory(id: 'provider', name: 'ผู้ให้บริการ');
        
    _requiresVerification =
        widget.existingProfession?.requiresVerification ?? true;
    _isVolunteer = widget.existingProfession?.isVolunteer ?? false;
    _selectedIcon = widget.existingProfession?.iconName ?? 'work';
    _selectedColor = widget.existingProfession?.colorHex ?? '#71BE0A';

    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isCategoriesLoading = true);
    try {
      final repository = ProfessionRepository(Supabase.instance.client);
      final categories = await repository.getAllUserCategories();
      
      if (mounted) {
        setState(() {
          _categories.clear();
          categories.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
          _categories.addAll(categories);
          
          if (widget.existingProfession != null) {
            _selectedCategory = _categories.firstWhere(
              (c) => c.id == widget.existingProfession!.category.id,
              orElse: () => _categories.isNotEmpty ? _categories.first : _selectedCategory,
            );
          } else if (_categories.isNotEmpty) {
            _selectedCategory = _categories.firstWhere(
              (c) => c.id == 'provider',
              orElse: () => _categories.first,
            );
          }
          
          _isCategoriesLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
      if (mounted) {
        setState(() => _isCategoriesLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameEnController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEditing ? 'แก้ไขอาชีพ' : 'เพิ่มอาชีพใหม่'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'ชื่ออาชีพ (ภาษาไทย) *',
                hintText: 'เช่น แพทย์, ทนายความ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameEnController,
              decoration: const InputDecoration(
                labelText: 'ชื่ออาชีพ (ภาษาอังกฤษ)',
                hintText: 'เช่น Doctor, Lawyer',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'คำอธิบาย',
                hintText: 'อธิบายลักษณะอาชีพ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'เลือกไอคอน',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _availableIcons.map((iconData) {
                    final isSelected = _selectedIcon == iconData['name'];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedIcon = iconData['name'];
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 50,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withOpacity(0.1)
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                iconData['icon'] as IconData,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textHint,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'เลือกสี',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _availableColors.map((colorHex) {
                    final isSelected = _selectedColor == colorHex;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedColor = colorHex;
                          });
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(int.parse(colorHex.replaceFirst('#', '0xFF'))),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? AppColors.textPrimary : Colors.transparent,
                              width: isSelected ? 2 : 0,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 20)
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isCategoriesLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else
              DropdownButtonFormField<UserCategory>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'หมวดหมู่ผู้ใช้',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: _categories.isNotEmpty 
                  ? _categories.map((category) {
                      return DropdownMenuItem(
                        value: category,
                        child: Text(category.displayName),
                      );
                    }).toList()
                  : [
                      DropdownMenuItem(
                        value: _selectedCategory,
                        child: Text(_selectedCategory.displayName),
                      )
                    ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedCategory = value;
                    });
                  }
                },
              ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('ต้องตรวจสอบก่อนใช้งาน'),
              subtitle: const Text('ผู้สมัครต้องรอ Admin อนุมัติ'),
              value: _requiresVerification,
              onChanged: (value) {
                setState(() {
                  _requiresVerification = value;
                });
              },
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('สิทธิอาสาสมัคร (Volunteer Role)'),
              subtitle: const Text('สามารถรับแจ้งเตือนและเข้าช่วยเหลือเมื่อเกิดเหตุฉุกเฉินได้'),
              value: _isVolunteer,
              onChanged: (value) {
                setState(() {
                  _isVolunteer = value;
                });
              },
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
            if (!isEditing) ...[
              const Divider(height: 32),
              Text(
                'คัดลอก Fields จากอาชีพอื่น (ไม่บังคับ)',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _copyFromProfessionId,
                decoration: const InputDecoration(
                  labelText: 'เลือกอาชีพต้นแบบ',
                  border: OutlineInputBorder(),
                ),
                menuMaxHeight: 250,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('ไม่คัดลอก'),
                  ),
                  ...Profession.defaultProfessions.map((p) {
                    return DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() {
                    _copyFromProfessionId = value;
                  });
                },
              ),
            ],
          ],
        ),
      ),
    ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveProfession,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(isEditing ? 'บันทึก' : 'เพิ่ม'),
        ),
      ],
    );
  }

  void _saveProfession() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกชื่ออาชีพ')),
      );
      return;
    }

    final name = _nameController.text.trim();
    final nameEn = _nameEnController.text.trim().isNotEmpty ? _nameEnController.text.trim() : null;
    final description = _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null;

    setState(() => _isSaving = true);

    try {
      final ProfessionRepository repo = ProfessionRepository(Supabase.instance.client);
      
      if (isEditing) {
        final updated = await repo.updateProfession(widget.existingProfession!.id, {
          'name': name,
          'name_en': nameEn,
          'description': description,
          'icon_name': _selectedIcon,
          'color_hex': _selectedColor,
          'category': _selectedCategory.value,
          'requires_verification': _requiresVerification,
          'is_volunteer': _isVolunteer,
        });
        widget.onSave(updated);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('บันทึกอาชีพ "$name" สำเร็จ ✓'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        final newProfession = await repo.createProfession(
          name: name,
          nameEn: nameEn,
          description: description,
          iconName: _selectedIcon,
          colorHex: _selectedColor,
          category: _selectedCategory,
          requiresVerification: _requiresVerification,
          isVolunteer: _isVolunteer,
        );

        if (_copyFromProfessionId != null) {
          try {
            await repo.copyFieldsFromProfession(_copyFromProfessionId!, newProfession.id);
          } catch (e) {
            debugPrint('Error copying fields: $e');
          }
        }

        widget.onSave(newProfession);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('เพิ่มอาชีพ "$name" สำเร็จ ✓'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving profession: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('บันทึกไม่สำเร็จ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
