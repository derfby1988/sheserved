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

    // Only show custom professions in management list
    final customProfessions =
        _professions.where((p) => !p.isBuiltIn).toList();

    return RefreshIndicator(
      onRefresh: _loadProfessions,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // === Online Providers Panel (Real-time) ===
          AllGroupsOnlinePanel(professions: customProfessions, isAdminView: true),
          const SizedBox(height: 20),
    
          // Professionals list (Custom only)
          if (customProfessions.isNotEmpty) ...[
            ...customProfessions.map((p) => _buildProfessionCard(p)),
          ] else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text(
                  'ยังไม่มีอาชีพที่เพิ่มเองในขณะนี้',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
                ),
              ),
            ),
    
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _getCategoryColor(profession.category).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getIconData(profession.iconName),
                      color: _getCategoryColor(profession.category),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Main Content
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
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                          ],
                        ),
                        const SizedBox(height: 6),
                        
                        // Stats & Category in Wrap
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
              
              const Divider(height: 20),
              
              // Bottom Action Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Pending Info
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

                  // Action Buttons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!profession.isBuiltIn) ...[
                        _buildActionIcon(
                          Icons.group_add_outlined, 
                          Colors.blue, 
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupMembersAdminPage(profession: profession))),
                        ),
                        _buildActionIcon(
                          Icons.edit_outlined, 
                          AppColors.primary, 
                          () => _showEditProfessionDialog(profession),
                        ),
                        _buildActionIcon(
                          Icons.delete_outline, 
                          AppColors.error, 
                          () => _confirmDeleteProfession(profession),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Icon(Icons.settings_outlined, color: AppColors.textHint, size: 18),
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

  Widget _buildActionIcon(IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  Color _getCategoryColor(UserCategory category) {
    if (category.id == UserCategory.consumerId) {
      return Colors.blue;
    } else if (category.id == UserCategory.providerId) {
      return AppColors.primary;
    }
    return Colors.purple; // Default for new custom categories
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
  final List<UserCategory> _categories = [];
  bool _isCategoriesLoading = true;
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
    
    // Set initial category (temp, will be refined once loaded)
    _selectedCategory = widget.existingProfession?.category ?? 
        const UserCategory(id: 'provider', name: 'ผู้ให้บริการ');
        
    _requiresVerification =
        widget.existingProfession?.requiresVerification ?? true;
    _selectedIcon = widget.existingProfession?.iconName ?? 'work';

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
          // Sort by display_order explicitly
          categories.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
          _categories.addAll(categories);
          
          // Re-match selected category with loaded list to ensure object identity
          if (widget.existingProfession != null) {
            _selectedCategory = _categories.firstWhere(
              (c) => c.id == widget.existingProfession!.category.id,
              orElse: () => _categories.isNotEmpty ? _categories.first : _selectedCategory,
            );
          } else if (_categories.isNotEmpty) {
            // Default to provider or first available
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

              // User Category
              if (_isCategoriesLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else
                DropdownButtonFormField<UserCategory>(
                  value: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'หมวดหมู่ผู้ใช้',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                  ),
                  items: _categories.map((category) {
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
