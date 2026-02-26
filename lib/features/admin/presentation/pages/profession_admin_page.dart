import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../models/profession.dart';
import '../../data/repositories/profession_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'group_members_admin_page.dart';
import '../../../../shared/widgets/tlz_drawer.dart';
import '../../../../shared/widgets/tlz_hamburger_menu.dart';

/// Admin Page สำหรับจัดการอาชีพ
class ProfessionAdminPage extends StatefulWidget {
  const ProfessionAdminPage({super.key});

  @override
  State<ProfessionAdminPage> createState() => _ProfessionAdminPageState();
}

class _ProfessionAdminPageState extends State<ProfessionAdminPage> {
  List<Profession> _professions = [];
  bool _isLoading = true;
  Map<String, int> _pendingCounts = {};

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const TlzDrawer(),
      appBar: AppBar(
        leading: const TlzHamburgerMenu(),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        title: const Text('จัดการอาชีพและฟิลด์ลงทะเบียน'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.pushNamed(context, '/admin/applications'),
            tooltip: 'ดูผู้สมัครรอตรวจสอบ',
          ),
        ],
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

    // Separate built-in and custom professions
    final builtInProfessions =
        _professions.where((p) => p.isBuiltIn).toList();
    final customProfessions =
        _professions.where((p) => !p.isBuiltIn).toList();

    return RefreshIndicator(
      onRefresh: _loadProfessions,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Built-in professions section
          if (builtInProfessions.isNotEmpty) ...[
            _buildSectionHeader('อาชีพหลัก (Built-in)', Icons.lock_outline),
            const SizedBox(height: 8),
            ...builtInProfessions.map((p) => _buildProfessionCard(p)),
          ],
    
          // Custom professions section
          if (customProfessions.isNotEmpty) ...[
            if (builtInProfessions.isNotEmpty) const SizedBox(height: 24),
            _buildSectionHeader('อาชีพที่เพิ่มเอง', Icons.add_circle_outline),
            const SizedBox(height: 8),
            ...customProfessions.map((p) => _buildProfessionCard(p)),
          ],
    
          const SizedBox(height: 80), // Space for FAB
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildProfessionCard(Profession profession) {
    final pendingCount = _pendingCounts[profession.id] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: profession.isBuiltIn
              ? AppColors.primary.withOpacity(0.3)
              : AppColors.border,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _navigateToFieldConfig(profession),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getCategoryColor(profession.category).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getIconData(profession.iconName),
                  color: _getCategoryColor(profession.category),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            profession.name,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (profession.isBuiltIn)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock,
                                  size: 12,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Built-in',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Field count
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.list_alt,
                              size: 14,
                              color: AppColors.textHint,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${profession.fieldCount} ฟิลด์',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),

                        // Category
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              profession.category == UserCategory.consumer
                                  ? Icons.person
                                  : Icons.business,
                              size: 14,
                              color: AppColors.textHint,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              profession.category.displayName,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),

                        // Requires verification badge
                        if (profession.requiresVerification)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_user,
                                size: 14,
                                color: AppColors.warning,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'ต้องตรวจสอบ',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.warning,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (profession.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        profession.description!,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textHint,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 4),

              // Actions
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Pending count badge
                  if (pendingCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$pendingCount รอตรวจ',
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Actions row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!profession.isBuiltIn) ...[
                        _buildCompactIconButton(
                          icon: Icons.people_outline,
                          color: Colors.blue,
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GroupMembersAdminPage(profession: profession),
                              ),
                            );
                          },
                          tooltip: 'จัดการสมาชิกและสิทธิกลุ่ม',
                        ),
                        _buildCompactIconButton(
                          icon: Icons.edit_outlined,
                          color: AppColors.primary,
                          onPressed: () => _showEditProfessionDialog(profession),
                          tooltip: 'แก้ไข',
                        ),
                        _buildCompactIconButton(
                          icon: Icons.delete_outline,
                          color: AppColors.error,
                          onPressed: () => _confirmDeleteProfession(profession),
                          tooltip: 'ลบ',
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          Icons.settings_outlined,
                          color: AppColors.textHint,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return IconButton(
      icon: Icon(icon),
      color: color,
      iconSize: 20,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }

  Color _getCategoryColor(UserCategory category) {
    switch (category) {
      case UserCategory.consumer:
        return Colors.blue;
      case UserCategory.provider:
        return AppColors.primary;
    }
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

  void _showAddProfessionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProfessionEditorDialog(
        onSave: (profession) {
          _loadProfessions(); // Reload from server to get correct state
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('เพิ่มอาชีพ "${profession.name}" สำเร็จ'),
                backgroundColor: AppColors.success,
              ),
            );
          }
        },
      ),
    );
  }

  void _showEditProfessionDialog(Profession profession) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProfessionEditorDialog(
        existingProfession: profession,
        onSave: (updatedProfession) {
          _loadProfessions(); // Reload from server
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('แก้ไขอาชีพ "${updatedProfession.name}" เรียบร้อย'),
                backgroundColor: AppColors.success,
              ),
            );
          }
        },
      ),
    );
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
              try {
                final ProfessionRepository repo = ProfessionRepository(Supabase.instance.client);
                await repo.deleteProfession(profession.id);
                setState(() {
                  _professions.removeWhere((p) => p.id == profession.id);
                });
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('ลบอาชีพ "${profession.name}" แล้ว')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
                  );
                }
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

/// Dialog สำหรับเพิ่ม/แก้ไขอาชีพ
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
  late UserCategory _selectedCategory;
  bool _requiresVerification = true;
  String _selectedIcon = 'work';
  String? _copyFromProfessionId;
  bool _isSaving = false;
  bool get isEditing => widget.existingProfession != null;

  final List<Map<String, dynamic>> _availableIcons = [
    {'name': 'work', 'icon': Icons.work, 'label': 'งานทั่วไป'},
    {'name': 'person', 'icon': Icons.person, 'label': 'บุคคล'},
    {'name': 'store', 'icon': Icons.store, 'label': 'ร้านค้า'},
    {'name': 'local_hospital', 'icon': Icons.local_hospital, 'label': 'โรงพยาบาล'},
    {'name': 'medical_services', 'icon': Icons.medical_services, 'label': 'บริการทางการแพทย์'},
    {'name': 'delivery_dining', 'icon': Icons.delivery_dining, 'label': 'จัดส่ง'},
    {'name': 'engineering', 'icon': Icons.engineering, 'label': 'วิศวกรรม'},
    {'name': 'gavel', 'icon': Icons.gavel, 'label': 'กฎหมาย'},
    {'name': 'school', 'icon': Icons.school, 'label': 'การศึกษา'},
    {'name': 'restaurant', 'icon': Icons.restaurant, 'label': 'ร้านอาหาร'},
    {'name': 'spa', 'icon': Icons.spa, 'label': 'สปา/ความงาม'},
    {'name': 'fitness_center', 'icon': Icons.fitness_center, 'label': 'ฟิตเนส'},
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
    _selectedCategory =
        widget.existingProfession?.category ?? UserCategory.provider;
    _requiresVerification =
        widget.existingProfession?.requiresVerification ?? true;
    _selectedIcon = widget.existingProfession?.iconName ?? 'work';
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
      content: SingleChildScrollView(
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Name (Thai)
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'ชื่ออาชีพ (ภาษาไทย) *',
                  hintText: 'เช่น แพทย์, ทนายความ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Name (English)
              TextField(
                controller: _nameEnController,
                decoration: const InputDecoration(
                  labelText: 'ชื่ออาชีพ (ภาษาอังกฤษ)',
                  hintText: 'เช่น Doctor, Lawyer',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Description
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

              // Icon selector
              Text(
                'เลือกไอคอน',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _availableIcons.length,
                  itemBuilder: (context, index) {
                    final iconData = _availableIcons[index];
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
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Category
              DropdownButtonFormField<UserCategory>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'หมวดหมู่',
                  border: OutlineInputBorder(),
                ),
                items: UserCategory.values.map((category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text(category.displayName),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedCategory = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Requires verification
              SwitchListTile(
                title: const Text('ต้องตรวจสอบก่อนใช้งาน'),
                subtitle: const Text('ผู้สมัครต้องรอ Admin อนุมัติ'),
                value: _requiresVerification,
                onChanged: (value) {
                  setState(() {
                    _requiresVerification = value;
                  });
                },
                activeColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
              ),

              // Copy fields from another profession
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
                  value: _copyFromProfessionId,
                  decoration: const InputDecoration(
                    labelText: 'เลือกอาชีพต้นแบบ',
                    border: OutlineInputBorder(),
                  ),
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
          'category': _selectedCategory.value,
          'requires_verification': _requiresVerification,
        });
        widget.onSave(updated);
        if (mounted) Navigator.pop(context);
      } else {
        // Create new profession
        final newProfession = await repo.createProfession(
          name: name,
          nameEn: nameEn,
          description: description,
          iconName: _selectedIcon,
          category: _selectedCategory,
          requiresVerification: _requiresVerification,
        );

        // If copy fields from another profession is selected
        if (_copyFromProfessionId != null) {
          try {
            await repo.copyFieldsFromProfession(_copyFromProfessionId!, newProfession.id);
          } catch (e) {
            debugPrint('Error copying fields: $e');
            // We ignore field copy error but show the profession
          }
        }

        widget.onSave(newProfession);
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving profession: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถบันทึกข้อมูลได้: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
