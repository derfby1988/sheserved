                const SizedBox(height: 50),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildTabItem({
    required IconData icon,
    required String text,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? activeColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? activeColor : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: isActive ? activeColor : Colors.grey,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 16),
          Stack(
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                backgroundImage: _tempProfileImage != null
                    ? FileImage(_tempProfileImage!)
                    : (_user?.profileImageUrl != null
                        ? NetworkImage(_user!.profileImageUrl!)
                        : null) as ImageProvider?,
                child: _user?.profileImageUrl == null && _tempProfileImage == null
                    ? const Icon(Icons.person, size: 60, color: AppColors.primary)
                    : null,
              ),
              if (_isEditing)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _user?.fullName ?? '',
                style: AppTextStyles.heading2,
              ),
              const SizedBox(width: 8),
              if (!_isEditing)
                GestureDetector(
                  onTap: () => setState(() => _isEditing = true),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5A623).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, color: Color(0xFFF5A623), size: 18),
                  ),
                )
              else
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isEditing = false;
                      _tempProfileImage = null;
                    });
                    _loadProfile();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.red, size: 18),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _profession?.category.name ?? _user?.userType.displayName ?? '',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              if (_user?.verificationStatus == VerificationStatus.verified) ...[
                const SizedBox(width: 8),
                const Icon(Icons.verified, color: AppColors.primary, size: 16),
              ],
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCoreInfo() {
    return Column(
      children: [
        _buildFieldRow('ชื่อผู้ใช้', _user?.username ?? '', isEditable: false),
        const SizedBox(height: 12),
        if (_isEditing) ...[
          TlzTextField(
            label: 'ชื่อ',
            controller: _controllers['first_name'],
          ),
          const SizedBox(height: 12),
          TlzTextField(
            label: 'นามสกุล',
            controller: _controllers['last_name'],
          ),
        ] else ...[
          _buildFieldRow('ชื่อ', _user?.firstName ?? ''),
          const SizedBox(height: 12),
          _buildFieldRow('นามสกุล', _user?.lastName ?? ''),
        ],
      ],
    );
  }

  List<Widget> _buildDynamicFields() {
    return _fields.map((field) {
      if (_isEditing) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildEditableDynamicField(field),
        );
      } else {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildReadonlyDynamicField(field),
        );
      }
    }).toList();
  }

  Widget _buildReadonlyDynamicField(RegistrationFieldConfig field) {
    String value = _dynamicData[field.fieldId] ?? '';
    
    if (field.fieldType == FieldType.date && value.isNotEmpty) {
      final date = DateTime.tryParse(value);
      if (date != null) {
        value = '${date.day} ${_getThaiShortMonth(date.month)} ${date.year + 543}';
      }
    } else if (field.fieldType == FieldType.image) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.label, style: AppTextStyles.bodySmall.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          if (value.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                value,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 150,
                  color: Colors.grey[200],
                  child: const Icon(Icons.broken_image),
                ),
              ),
            )
          else
            const Text('ไม่มีข้อมูล'),
        ],
      );
    }

    return _buildFieldRow(field.label, value.isEmpty ? 'ไม่มีข้อมูล' : value);
  }

  Widget _buildEditableDynamicField(RegistrationFieldConfig field) {
    if (field.fieldType == FieldType.date) {
      final date = _dynamicValues[field.fieldId] as DateTime?;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.label, style: AppTextStyles.bodyMedium),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _selectDate(field.fieldId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    date != null 
                      ? '${date.day} ${_getThaiShortMonth(date.month)} ${date.year + 543}'
                      : field.hint ?? 'เลือกวันที่',
                    style: TextStyle(color: date != null ? Colors.black : Colors.grey),
                  ),
                  const Icon(Icons.calendar_today, size: 20),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (field.fieldType == FieldType.image) {
       final currentUrl = _dynamicValues[field.fieldId] as String?;
       return Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Text(field.label, style: AppTextStyles.bodyMedium),
           const SizedBox(height: 8),
           if (currentUrl != null && currentUrl.isNotEmpty)
             Stack(
               children: [
                 ClipRRect(
                   borderRadius: BorderRadius.circular(8),
                   child: Image.network(currentUrl, height: 100, width: 100, fit: BoxFit.cover),
                 ),
                 Positioned(
                   top: 0, right: 0,
                   child: IconButton(
                     icon: const Icon(Icons.cancel, color: Colors.red),
                     onPressed: () => setState(() => _dynamicValues[field.fieldId] = null),
                   ),
                 )
               ],
             )
           else
             const Text('อัพโหลดรูปภาพ (เร็วๆ นี้)'),
         ],
       );
    }

    return TlzTextField(
      label: field.label,
      controller: _controllers[field.fieldId],
      hint: field.hint,
      keyboardType: field.fieldType == FieldType.phone ? TextInputType.phone : TextInputType.text,
      maxLines: field.fieldType == FieldType.multilineText ? 3 : 1,
    );
  }

  Widget _buildFieldRow(String label, String value, {bool isEditable = true}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'การตั้งค่าการแจ้งเตือน',
          style: AppTextStyles.heading3.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'แจ้งเหตุฉุกเฉินใกล้ตัว (ไทยมุง)',
                      style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'รับแจ้งเตือนเมื่อมีเหตุการณ์เกิดขึ้นในรัศมี 500 เมตร',
                      style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _thaiMhungEnabled,
                onChanged: (value) => _updateVolunteerSettings(enabled: value),
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),
        ),
        if (_thaiMhungEnabled || (_profession?.isVolunteer ?? false)) ...[
          const SizedBox(height: 24),
          _buildRadiusSection(),
          const SizedBox(height: 24),
          _buildUnblurredProfessionSection(),
        ],
      ],
    );
  }

  Widget _buildRadiusSection() {
    final isProfessional = _profession?.isVolunteer ?? false;
    final title = isProfessional ? 'รัศมีพื้นที่รับผิดชอบ' : 'พื้นที่ให้ทางแก่เจ้าหน้าที่';
    final description = isProfessional 
        ? 'ระบุระยะทางที่คุณสามารถเดินทางไปช่วยเหลือเหตุฉุกเฉินได้' 
        : 'รัศมีสำหรับการแจ้งเตือนเหตุ เพื่ออำนวยความสะดวก "เส้นทาง"แก่เจ้าหน้าที่';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _alertRadius >= 1000 
                    ? '${(_alertRadius / 1000).toStringAsFixed(1)} กม.' 
                    : '$_alertRadius ม.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Slider(
            value: _alertRadius.toDouble().clamp(500, 100000),
            min: 500,
            max: 100000,
            divisions: 199,
            onChanged: (value) => setState(() => _alertRadius = value.round()),
            onChangeEnd: (value) => _updateVolunteerSettings(radius: value.round()),
            activeColor: AppColors.primary,
            inactiveColor: Colors.grey[200],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('500 ม.', style: AppTextStyles.bodySmall.copyWith(color: Colors.grey)),
              Text('100 กม.', style: AppTextStyles.bodySmall.copyWith(color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _updateApproverSettings({bool? enabled, int? radius}) async {
    if (_user == null) return;
    bool newEnabled = enabled ?? _isApproverEnabled;
    final newRadius = radius ?? _approvalRadius;
    
    try {
      if (enabled != null) {
        await Supabase.instance.client.from('user_registration_data').upsert({
          'user_id': _user!.id,
          'field_id': 'is_approver_enabled',
          'field_value': newEnabled.toString(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,field_id');
      }
      if (radius != null) {
        await Supabase.instance.client.from('user_registration_data').upsert({
          'user_id': _user!.id,
          'field_id': 'approval_radius',
          'field_value': newRadius.toString(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,field_id');
      }
      
      // Save locally to dynamicData so we don't have to refetch
      _dynamicData['is_approver_enabled'] = newEnabled.toString();
      _dynamicData['approval_radius'] = newRadius.toString();
      
      if (mounted) {
        setState(() {
          _isApproverEnabled = newEnabled;
          _approvalRadius = newRadius;
        });
      }
    } catch(e) {
      debugPrint('Error updating approver settings: $e');
    }
  }

  Widget _buildApproverSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'การตั้งค่าการอนุมัติ',
          style: AppTextStyles.heading3.copyWith(color: Colors.teal),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'เข้าร่วมอนุมัติรายการบริจาค',
                      style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'แสดงตามสิทธิ์ที่กำหนดไว้ใน dialog flow การอนุมัติ แถบหมวดหมู่ หน้าจัดการระบบบริจาค',
                      style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isApproverEnabled,
                onChanged: (value) => _updateApproverSettings(enabled: value),
                activeThumbColor: Colors.teal,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // พื้นที่อนุมัติการบริจาค
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'พื้นที่อนุมัติการบริจาค',
                    style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _approvalRadius >= 1000 
                        ? '${(_approvalRadius / 1000).toStringAsFixed(1)} กม.' 
                        : '$_approvalRadius ม.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.teal,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'โดยคำนวนระยะทางจากที่อยู่ปัจจุบันของผู้อนุมัติ ไปยังตำแหน่งหรือสถานที่ที่ผู้ร้องขอการบริจาคต้องการนำไปใช้',
                style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Slider(
                value: _approvalRadius.toDouble().clamp(500, 100000),
                min: 500,
                max: 100000,
                divisions: 199,
                activeColor: Colors.teal,
                onChanged: (val) {
                  setState(() {
                    _approvalRadius = val.toInt();
                  });
                },
                onChangeEnd: (val) => _updateApproverSettings(radius: val.toInt()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  /// โหลดรายการอาชีพจิตอาสาทั้งหมดจาก Supabase Professions Table
  Future<void> _loadVolunteerProfessions() async {
    if (_isLoadingProfessions) return;
    setState(() => _isLoadingProfessions = true);
    try {
      final response = await Supabase.instance.client
          .from('professions')
          .select('''
            id, name, color_hex, is_volunteer, is_active, category, display_order,
            category_data:user_categories!professions_category_fkey(*)
          ''')
          .eq('is_active', true)
          .order('display_order'); // Order within categories
      if (mounted) {
        setState(() {
          _allVolunteerProfessions = (response as List).map((json) {
            // Handle category safely
            prof.UserCategory category;
            if (json['category_data'] != null) {
              category = prof.UserCategory.fromJson(json['category_data']);
            } else {
              category = prof.UserCategory.fromString(json['category'] ?? 'consumer');
            }

            return prof.Profession(
              id: json['id'] ?? '',
              name: json['name'] ?? '',
              colorHex: json['color_hex'],
              isVolunteer: json['is_volunteer'] ?? false,
              category: category,
              isActive: json['is_active'] ?? true,
              displayOrder: json['display_order'] ?? 0,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
          }).toList();

          // เรียงลำดับเพิ่มเติม: หมวดหมู่ (displayOrder) -> อาชีพ (displayOrder)
          _allVolunteerProfessions.sort((a, b) {
            final catCompare = a.category.displayOrder.compareTo(b.category.displayOrder);
            if (catCompare != 0) return catCompare;
            return a.displayOrder.compareTo(b.displayOrder);
          });

          // ตั้งค่าเริ่มต้นเป็นกลุ่มแรกหากยังไม่ได้เลือก
          if (_allVolunteerProfessions.isNotEmpty && _selectedCategory == null) {
            _selectedCategory = _allVolunteerProfessions.first.category.id;
          }
          _isLoadingProfessions = false;
        });
      }
    } catch (e) {
      debugPrint('ProfilePage: Error loading professions: $e');
      if (mounted) setState(() => _isLoadingProfessions = false);
    }
  }

  /// UI เลือกอาชีพที่อนุญาตให้เห็นวิดีโอไม่เบลอ
  Widget _buildUnblurredProfessionSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _isSavingUnblurred
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                        ),
                      )
                    : const Icon(Icons.visibility, color: Colors.red, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'สิทธิ์ดูวิดีโอต้นฉบับ',
                      style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'เลือกอาชีพจิตอาสาที่อนุญาตให้เห็นภาพ/วิดีโอไม่ผ่านการเบลอ',
                      style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingProfessions)
            const Center(child: CircularProgressIndicator())
          else if (_allVolunteerProfessions.isEmpty)
            Text(
              'ไม่พบรายการอาชีพ',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
            )
          else ...[
            // 1. ส่วนเลือกกลุ่มอาชีพ (Category Selector)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _getUniqueCategories().map((cat) {
                  final isSelected = _selectedCategory == cat.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat.displayName),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _selectedCategory = cat.id);
                      },
                      selectedColor: AppColors.primary.withValues(alpha: 0.1),
                      labelStyle: AppTextStyles.bodySmall.copyWith(
                        color: isSelected ? AppColors.primary : Colors.grey,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            // 2. ส่วนเลือกอาชีพในกลุ่มที่เลือก (Professions in Selected Category)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allVolunteerProfessions
                  .where((p) => p.category.id == _selectedCategory)
                  .map((p) {
                final isSelected = _selectedUnblurredIds.contains(p.id);
                Color chipColor = AppColors.primary;
                if (p.colorHex != null && p.colorHex!.isNotEmpty) {
                  try {
                    chipColor = Color(int.parse(p.colorHex!.replaceFirst('#', '0xFF')));
                  } catch (_) {}
                }
                return FilterChip(
                  label: Text(p.name),
                  selected: isSelected,
                  selectedColor: chipColor.withValues(alpha: 0.2),
                  checkmarkColor: chipColor,
                  labelStyle: AppTextStyles.bodySmall.copyWith(
                    color: isSelected ? chipColor : Colors.grey[700],
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected ? chipColor : Colors.grey[300]!,
                    width: isSelected ? 1.5 : 1,
                  ),
                  onSelected: _isSavingUnblurred
                      ? null
                      : (val) {
                          setState(() {
                            if (val) {
                              _selectedUnblurredIds.add(p.id);
                            } else {
                              _selectedUnblurredIds.remove(p.id);
                            }
                          });
                          _saveUnblurredProfessions();
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text(
              'หมายเหตุ: อาชีพที่ไม่ได้เลือกจะเห็นเพียงภาพเบลอ (Privacy Mode)',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  /// ดึงหมวดหมู่ที่ไม่ซ้ำกันจากรายการอาชีพทั้งหมด
  List<prof.UserCategory> _getUniqueCategories() {
    final categories = <prof.UserCategory>[];
    final seen = <String>{};
    for (var p in _allVolunteerProfessions) {
      if (!seen.contains(p.category.id)) {
        seen.add(p.category.id);
        categories.add(p.category);
      }
    }
    // เรียงตาม displayOrder เพื่อให้ตรงกับหน้าจัดการ (Admin)
    categories.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return categories;
  }

  Future<void> _saveUnblurredProfessions() async {
    if (_user == null) return;
    setState(() => _isSavingUnblurred = true);
    try {
      // บันทึกลงตาราง user_registration_data ซึ่งเป็นตารางแบบ Dynamic Key-Value
      // วิธีนี้จะทำให้ข้อมูลถูกบันทึกสำเร็จแน่นอนทั้งใน Local และ Supabase Cloud โดยไม่ต้องกังวลเรื่องคอลัมน์ขาดหาย
      await Supabase.instance.client.from('user_registration_data').upsert({
        'user_id': _user!.id,
        'field_id': 'unblurred_profession_ids',
        'field_value': json.encode(_selectedUnblurredIds.toList()),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,field_id');

      // อัพเดต local session
      AuthService.instance.login(_user!.copyWith(
        unblurredProfessionIds: _selectedUnblurredIds.toList(),
      ));
      debugPrint('ProfilePage: ✅ Saved unblurred professions: $_selectedUnblurredIds');
    } catch (e) {
      debugPrint('ProfilePage: ❌ Error saving unblurred professions: $e');
    } finally {
      if (mounted) {
        setState(() => _isSavingUnblurred = false);
      }
    }
  }

  Future<void> _updateVolunteerSettings({bool? enabled, int? radius}) async {
    if (_user == null) return;
    
    bool newEnabled = enabled ?? _thaiMhungEnabled;
    final newRadius = radius ?? _alertRadius;

    // Guided UX: If enabling, check for background location permission on Android
    if (enabled == true) {
      final locService = LocationTrackingService();
      final isAlwaysGranted = await locService.isBackgroundPermissionGranted();
      
      if (!isAlwaysGranted) {
        // Show our custom guidance dialog first
        final shouldGoToSettings = await BackgroundPermissionDialog.show(context);
        if (!mounted) return;
        if (shouldGoToSettings) {
          await openAppSettings();
          // After returning from settings, we don't force 'true' yet, 
          // let the user toggle again once they grant permission.
          return;
        } else {
          // User cancelled the guidance, don't enable
          setState(() => _thaiMhungEnabled = false);
          return;
        }
      }
    }
    
    setState(() {
      _thaiMhungEnabled = newEnabled;
      _alertRadius = newRadius;
    });

    try {
      await _repository.updateProfile(
        userId: _user!.id,
        coreData: {
          'is_thai_mhung_enabled': newEnabled,
          'alert_radius': newRadius,
        },
        dynamicData: {},
        userType: _user!.userType,
      );
      
      AuthService.instance.login(_user!.copyWith(
        isThaiMhungEnabled: newEnabled,
        alertRadius: newRadius,
      ));

      // Option 3: Start/Stop persistent tracking based on toggle
      final locService = LocationTrackingService();
      if (newEnabled) {
        // Start persistent tracking
        await locService.startTracking(userId: _user!.id);
      } else {
        // Stop tracking
        locService.stopTracking();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกการตั้งค่าจิตอาสาสำเร็จ'),
            duration: Duration(seconds: 1),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating volunteer settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _tempProfileImage = File(image.path);
      });
    }
  }

  Future<void> _selectDate(String fieldId) async {
    final current = _dynamicValues[fieldId] as DateTime? ?? DateTime.now();
    final picked = await showThaiDatePicker(
      context,
      initialDate: current,
      firstDate: DateTime(DateTime.now().year - 100),
      lastDate: DateTime.now(),
      era: Era.be,
      locale: 'th_TH',
    );
    if (picked != null) {
      setState(() {
        _dynamicValues[fieldId] = picked;
      });
    }
  }

  String _getThaiShortMonth(int month) {
    const months = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
    return months[month - 1];
  }

  void _handleSave() async {
    if (_user == null) return;
    setState(() => _isSaving = true);

    try {
      final userId = _user!.id;
      final Map<String, dynamic> coreData = {
        'first_name': _controllers['first_name']?.text,
        'last_name': _controllers['last_name']?.text,
        'is_thai_mhung_enabled': _thaiMhungEnabled,
        'alert_radius': _alertRadius,
      };

      final Map<String, String> dynamicData = {};
      for (final field in _fields) {
        if (field.fieldType == FieldType.date) {
          final date = _dynamicValues[field.fieldId] as DateTime?;
          if (date != null) dynamicData[field.fieldId] = date.toIso8601String();
        } else if (field.fieldType != FieldType.image) {
          final text = _controllers[field.fieldId]?.text ?? '';
          dynamicData[field.fieldId] = text;
        }
      }

      // Handle Profile Image Upload
      if (_tempProfileImage != null) {
         try {
           final fileName = 'profiles/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
           final supabase = Supabase.instance.client;
           await supabase.storage.from('public').upload(fileName, _tempProfileImage!);
           final imageUrl = supabase.storage.from('public').getPublicUrl(fileName);
           coreData['profile_image_url'] = imageUrl;
         } catch (e) {
           debugPrint('Image upload failed: $e');
         }
      }

      await _repository.updateProfile(
        userId: userId,
        coreData: coreData,
        dynamicData: dynamicData,
        userType: _user!.userType,
      );
      
      // Update local session
      AuthService.instance.login(_user!.copyWith(
        firstName: coreData['first_name'],
        lastName: coreData['last_name'],
        isThaiMhungEnabled: _thaiMhungEnabled,
        alertRadius: _alertRadius,
        profileImageUrl: coreData['profile_image_url'],
      ));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกข้อมูลสำเร็จ')),
        );
        setState(() {
          _isEditing = false;
          _isSaving = false;
          _tempProfileImage = null;
        });
        _loadProfile();
      }
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
        );
      }
    }
  }
}
