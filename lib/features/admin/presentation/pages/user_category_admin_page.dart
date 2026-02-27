import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../models/profession.dart';
import '../../data/repositories/profession_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/widgets/tlz_drawer.dart';
import '../../../../shared/widgets/tlz_hamburger_menu.dart';

/// หน้าจัดการหมวดหมู่ผู้ใช้ (Consumer, Provider, etc.)
class UserCategoryAdminPage extends StatefulWidget {
  const UserCategoryAdminPage({super.key});

  @override
  State<UserCategoryAdminPage> createState() => _UserCategoryAdminPageState();
}

class _UserCategoryAdminPageState extends State<UserCategoryAdminPage> {
  List<UserCategory> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    try {
      final repository = ProfessionRepository(Supabase.instance.client);
      final categories = await repository.getAllUserCategories();
      if (mounted) {
        setState(() {
          _categories = categories;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
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
        title: const Text('จัดการหมวดหมู่ผู้ใช้'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCategories,
              child: ReorderableListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _categories.length,
                onReorder: _onReorder,
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  return Container(
                    key: ValueKey(category.id),
                    child: _buildCategoryCard(category),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditorDialog(),
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มหมวดหมู่'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildCategoryCard(UserCategory category) {
    final bool isSystem = category.id == UserCategory.consumerId || 
                         category.id == UserCategory.providerId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSystem ? AppColors.primary.withOpacity(0.3) : AppColors.border,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getIconData(category.iconName),
            color: AppColors.primary,
          ),
        ),
        title: Text(
          category.name,
          style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${category.id}', style: AppTextStyles.caption),
            if (category.description != null)
              Text(category.description!, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showEditorDialog(category),
              tooltip: 'แก้ไข',
            ),
            if (!isSystem)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                onPressed: () => _confirmDelete(category),
                tooltip: 'ลบ',
              ),
          ],
        ),
      ),
    );
  }

  IconData _getIconData(String? iconName) {
    switch (iconName) {
      case 'shopping_cart': return Icons.shopping_cart;
      case 'medical_services': return Icons.medical_services;
      case 'person': return Icons.person;
      case 'business': return Icons.business;
      case 'volunteer_activism': return Icons.volunteer_activism;
      case 'group': return Icons.group;
      case 'home': return Icons.home;
      case 'school': return Icons.school;
      case 'favorite': return Icons.favorite;
      case 'star': return Icons.star;
      case 'pets': return Icons.pets;
      default: return Icons.category;
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    setState(() {
      final category = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, category);
    });

    try {
      final repository = ProfessionRepository(Supabase.instance.client);
      await repository.reorderUserCategories(_categories);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกลำดับใหม่แล้ว'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการจัดลำดับ: $e'), backgroundColor: AppColors.error),
        );
      }
      _loadCategories(); // Revert on error
    }
  }

  void _showEditorDialog([UserCategory? category]) {
    showDialog(
      context: context,
      builder: (context) => UserCategoryEditorDialog(
        category: category,
        onSave: () {
          _loadCategories();
        },
      ),
    );
  }

  void _confirmDelete(UserCategory category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('คุณต้องการลบหมวดหมู่ "${category.name}" ใช่หรือไม่?\n(การลบอาจส่งผลต่อการคัดกรองอาชีพที่ใช้หมวดหมู่นี้)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final repository = ProfessionRepository(Supabase.instance.client);
                await repository.deleteUserCategory(category.id);
                _loadCategories();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ลบหมวดหมู่เรียบร้อยแล้ว')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: AppColors.error));
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

/// Dialog แก้ไขหมวดหมู่
class UserCategoryEditorDialog extends StatefulWidget {
  final UserCategory? category;
  final VoidCallback onSave;

  const UserCategoryEditorDialog({super.key, this.category, required this.onSave});

  @override
  State<UserCategoryEditorDialog> createState() => _UserCategoryEditorDialogState();
}

class _UserCategoryEditorDialogState extends State<UserCategoryEditorDialog> {
  late TextEditingController _idController;
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  String _selectedIcon = 'category';
  bool _isSaving = false;
  bool get isEditing => widget.category != null;

  final List<Map<String, dynamic>> _availableIcons = [
    {'name': 'category', 'icon': Icons.category},
    {'name': 'shopping_cart', 'icon': Icons.shopping_cart},
    {'name': 'medical_services', 'icon': Icons.medical_services},
    {'name': 'person', 'icon': Icons.person},
    {'name': 'business', 'icon': Icons.business},
    {'name': 'volunteer_activism', 'icon': Icons.volunteer_activism},
    {'name': 'group', 'icon': Icons.group},
    {'name': 'home', 'icon': Icons.home},
    {'name': 'school', 'icon': Icons.school},
    {'name': 'favorite', 'icon': Icons.favorite},
    {'name': 'star', 'icon': Icons.star},
    {'name': 'pets', 'icon': Icons.pets},
  ];

  @override
  void initState() {
    super.initState();
    _idController = TextEditingController(text: widget.category?.id ?? '');
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _descriptionController = TextEditingController(text: widget.category?.description ?? '');
    _selectedIcon = widget.category?.iconName ?? 'category';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEditing ? 'แก้ไขหมวดหมู่' : 'เพิ่มหมวดหมู่ใหม่'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _idController,
              enabled: !isEditing,
              decoration: const InputDecoration(
                labelText: 'ID (ภาษาอังกฤษ)',
                hintText: 'เช่น volunteer, organization',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'ชื่อหมวดหมู่ (ภาษาไทย)',
                hintText: 'เช่น อาสาสมัคร',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'คำอธิบาย (ไม่บังคับ)',
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.palette_outlined, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  'เลือกไอคอนหมวดหมู่',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              width: double.maxFinite,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _availableIcons.length,
                itemBuilder: (context, index) {
                  final iconData = _availableIcons[index];
                  final bool isSelected = _selectedIcon == iconData['name'];
                  
                  return InkWell(
                    onTap: () => setState(() => _selectedIcon = iconData['name']),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? AppColors.primary.withOpacity(0.1) 
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.border,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        iconData['icon'] as IconData,
                        color: isSelected ? AppColors.primary : AppColors.textHint,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('บันทึก'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_idController.text.isEmpty || _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบถ้วน')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = ProfessionRepository(Supabase.instance.client);
      final data = {
        'id': _idController.text.trim().toLowerCase(),
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'icon_name': _selectedIcon,
        'is_active': true,
      };

      if (isEditing) {
        // preserve current display order if editing
        data['display_order'] = widget.category!.displayOrder;
        await repository.updateUserCategory(widget.category!.id, data);
      } else {
        // default order for new item
        data['display_order'] = 999;
        await repository.createUserCategory(data);
      }

      widget.onSave();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
