import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../models/registration_field_config.dart';

/// Admin Page สำหรับจัดการ Field ลงทะเบียน
class RegistrationFieldAdminPage extends StatefulWidget {
  const RegistrationFieldAdminPage({super.key});

  @override
  State<RegistrationFieldAdminPage> createState() =>
      _RegistrationFieldAdminPageState();
}

class _RegistrationFieldAdminPageState extends State<RegistrationFieldAdminPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _configService = RegistrationFieldConfigService();
  UserType _selectedUserType = UserType.consumer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: UserType.values.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedUserType = UserType.values[_tabController.index];
        });
      }
    });
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
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        title: const Text('จัดการฟิลด์ลงทะเบียน'),
        actions: [
          IconButton(
            icon: const Icon(Icons.preview),
            onPressed: _showPreview,
            tooltip: 'ดูตัวอย่าง',
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            onPressed: _resetToDefaults,
            tooltip: 'รีเซ็ตเป็นค่าเริ่มต้น',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.textOnPrimary,
          labelColor: AppColors.textOnPrimary,
          unselectedLabelColor: AppColors.textOnPrimary.withOpacity(0.6),
          tabs: UserType.values.map((type) {
            return Tab(text: type.shortTitle);
          }).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: UserType.values.map((type) {
          return _buildFieldList(type);
        }).toList(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddFieldDialog(_selectedUserType),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'เพิ่มฟิลด์',
          style: AppTextStyles.button.copyWith(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildFieldList(UserType userType) {
    final fields = _configService.getConfigsForUserType(userType);

    if (fields.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 16),
            Text(
              'ยังไม่มีฟิลด์',
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'กดปุ่ม "เพิ่มฟิลด์" เพื่อเริ่มต้น',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textHint,
              ),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: fields.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          _configService.reorderFields(userType, oldIndex, newIndex);
        });
      },
      itemBuilder: (context, index) {
        final field = fields[index];
        return _buildFieldCard(field, userType, index);
      },
    );
  }

  Widget _buildFieldCard(
      RegistrationFieldConfig field, UserType userType, int index) {
    return Card(
      key: ValueKey(field.id),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: field.isRequired ? AppColors.primary : AppColors.border,
          width: field.isRequired ? 2 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _getFieldTypeColor(field.fieldType).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getFieldTypeIcon(field.fieldType),
            color: _getFieldTypeColor(field.fieldType),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                field.label,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (field.isRequired)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'จำเป็น',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              field.fieldType.displayName,
              style: AppTextStyles.caption.copyWith(
                color: _getFieldTypeColor(field.fieldType),
              ),
            ),
            if (field.hint != null && field.hint!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                field.hint!,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textHint,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              color: AppColors.primary,
              onPressed: () => _showEditFieldDialog(userType, field),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: AppColors.error,
              onPressed: () => _confirmDeleteField(userType, field),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Icon(
                Icons.drag_handle,
                color: AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFieldTypeIcon(FieldType type) {
    switch (type) {
      case FieldType.text:
        return Icons.text_fields;
      case FieldType.email:
        return Icons.email_outlined;
      case FieldType.phone:
        return Icons.phone_outlined;
      case FieldType.number:
        return Icons.numbers;
      case FieldType.date:
        return Icons.calendar_today_outlined;
      case FieldType.image:
        return Icons.image_outlined;
      case FieldType.multilineText:
        return Icons.notes;
      case FieldType.dropdown:
        return Icons.arrow_drop_down_circle_outlined;
    }
  }

  Color _getFieldTypeColor(FieldType type) {
    switch (type) {
      case FieldType.text:
        return Colors.blue;
      case FieldType.email:
        return Colors.orange;
      case FieldType.phone:
        return Colors.green;
      case FieldType.number:
        return Colors.purple;
      case FieldType.date:
        return Colors.teal;
      case FieldType.image:
        return Colors.pink;
      case FieldType.multilineText:
        return Colors.indigo;
      case FieldType.dropdown:
        return Colors.amber;
    }
  }

  void _showAddFieldDialog(UserType userType) {
    showDialog(
      context: context,
      builder: (context) => FieldEditorDialog(
        userType: userType,
        onSave: (field) {
          setState(() {
            _configService.addField(userType, field);
          });
        },
      ),
    );
  }

  void _showEditFieldDialog(UserType userType, RegistrationFieldConfig field) {
    showDialog(
      context: context,
      builder: (context) => FieldEditorDialog(
        userType: userType,
        existingField: field,
        onSave: (updatedField) {
          setState(() {
            _configService.updateField(userType, updatedField);
          });
        },
      ),
    );
  }

  void _confirmDeleteField(UserType userType, RegistrationFieldConfig field) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบฟิลด์ "${field.label}" หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _configService.removeField(userType, field.id);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('ลบฟิลด์ "${field.label}" แล้ว')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
  }

  void _resetToDefaults() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('รีเซ็ตเป็นค่าเริ่มต้น'),
        content: const Text(
            'การดำเนินการนี้จะลบการตั้งค่าทั้งหมดและกลับไปใช้ค่าเริ่มต้น\n\nต้องการดำเนินการต่อหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _configService.resetToDefaults();
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('รีเซ็ตเป็นค่าเริ่มต้นแล้ว')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('รีเซ็ต'),
          ),
        ],
      ),
    );
  }

  void _showPreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FieldPreviewPage(
          userType: _selectedUserType,
          fields: _configService.getConfigsForUserType(_selectedUserType),
        ),
      ),
    );
  }
}

/// Dialog สำหรับเพิ่ม/แก้ไข Field
class FieldEditorDialog extends StatefulWidget {
  final UserType userType;
  final RegistrationFieldConfig? existingField;
  final Function(RegistrationFieldConfig) onSave;

  const FieldEditorDialog({
    super.key,
    required this.userType,
    this.existingField,
    required this.onSave,
  });

  @override
  State<FieldEditorDialog> createState() => _FieldEditorDialogState();
}

class _FieldEditorDialogState extends State<FieldEditorDialog> {
  late TextEditingController _labelController;
  late TextEditingController _hintController;
  late FieldType _selectedFieldType;
  late bool _isRequired;

  @override
  void initState() {
    super.initState();
    _labelController =
        TextEditingController(text: widget.existingField?.label ?? '');
    _hintController =
        TextEditingController(text: widget.existingField?.hint ?? '');
    _selectedFieldType = widget.existingField?.fieldType ?? FieldType.text;
    _isRequired = widget.existingField?.isRequired ?? false;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingField != null;

    return AlertDialog(
      title: Text(isEditing ? 'แก้ไขฟิลด์' : 'เพิ่มฟิลด์ใหม่'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Label
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'ชื่อฟิลด์ *',
                hintText: 'เช่น อีเมล, เบอร์โทร',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Hint
            TextField(
              controller: _hintController,
              decoration: const InputDecoration(
                labelText: 'คำแนะนำ (Placeholder)',
                hintText: 'เช่น กรอกอีเมลของคุณ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Field Type
            DropdownButtonFormField<FieldType>(
              value: _selectedFieldType,
              decoration: const InputDecoration(
                labelText: 'ประเภทฟิลด์',
                border: OutlineInputBorder(),
              ),
              items: FieldType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.displayName),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedFieldType = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // Is Required
            SwitchListTile(
              title: const Text('จำเป็นต้องกรอก'),
              subtitle: const Text('ผู้ใช้ต้องกรอกข้อมูลนี้'),
              value: _isRequired,
              onChanged: (value) {
                setState(() {
                  _isRequired = value;
                });
              },
              activeColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: _saveField,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: Text(isEditing ? 'บันทึก' : 'เพิ่ม'),
        ),
      ],
    );
  }

  void _saveField() {
    if (_labelController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกชื่อฟิลด์')),
      );
      return;
    }

    final field = RegistrationFieldConfig(
      id: widget.existingField?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      label: _labelController.text,
      hint: _hintController.text.isNotEmpty ? _hintController.text : null,
      fieldType: _selectedFieldType,
      isRequired: _isRequired,
      order: widget.existingField?.order ?? 999,
    );

    widget.onSave(field);
    Navigator.pop(context);
  }
}

/// หน้า Preview แสดงตัวอย่างฟอร์ม
class FieldPreviewPage extends StatelessWidget {
  final UserType userType;
  final List<RegistrationFieldConfig> fields;

  const FieldPreviewPage({
    super.key,
    required this.userType,
    required this.fields,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        title: Text('ตัวอย่าง: ${userType.title}'),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'ข้อมูลจำเพาะ',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.heading4.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'สำหรับ ${userType.title}',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Fields
                    ...fields.map((field) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildFieldPreview(field),
                        )),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Button
          Container(
            padding: const EdgeInsets.all(24),
            color: Colors.white,
            child: SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'ต่อไป',
                  style: AppTextStyles.button.copyWith(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldPreview(RegistrationFieldConfig field) {
    if (field.fieldType == FieldType.image) {
      return _buildImageFieldPreview(field);
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.primary,
          width: 1.5,
        ),
      ),
      child: TextField(
        enabled: false,
        maxLines: field.fieldType == FieldType.multilineText ? 3 : 1,
        decoration: InputDecoration(
          hintText: field.hint ?? field.label,
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textHint,
          ),
          prefixIcon: Icon(
            _getIconForField(field),
            color: AppColors.primary,
            size: 24,
          ),
          suffixIcon: field.isRequired
              ? const Icon(Icons.star, color: AppColors.error, size: 12)
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildImageFieldPreview(RegistrationFieldConfig field) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getIconForField(field),
              color: AppColors.textHint,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      field.label,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (field.isRequired)
                      Text(
                        ' *',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'แตะเพื่ออัพโหลด',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.cloud_upload_outlined,
            color: AppColors.primary,
            size: 24,
          ),
        ],
      ),
    );
  }

  IconData _getIconForField(RegistrationFieldConfig field) {
    switch (field.fieldType) {
      case FieldType.email:
        return Icons.email_outlined;
      case FieldType.phone:
        return Icons.phone_outlined;
      case FieldType.date:
        return Icons.calendar_today_outlined;
      case FieldType.image:
        return Icons.image_outlined;
      case FieldType.number:
        return Icons.numbers;
      case FieldType.multilineText:
        return Icons.notes;
      case FieldType.dropdown:
        return Icons.arrow_drop_down_circle_outlined;
      default:
        return Icons.text_fields;
    }
  }
}
