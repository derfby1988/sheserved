import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../services/service_locator.dart';
import '../../data/repositories/donation_repository.dart';
import '../../models/donation_models.dart';
import '../../../../shared/widgets/thai_address_picker/thai_address_picker.dart';
import '../../../../shared/widgets/thai_buddhist_date_picker.dart';
import '../../../../shared/widgets/image_upload_field.dart';
import 'package:intl/intl.dart';


class DonationCreatePage extends StatefulWidget {
  final String? videoId;
  final String? defaultCategoryId;
  const DonationCreatePage({super.key, this.videoId, this.defaultCategoryId});

  @override
  State<DonationCreatePage> createState() => _DonationCreatePageState();
}

class _DonationCreatePageState extends State<DonationCreatePage> {
  final _formKey = GlobalKey<FormState>();
  late DonationRepository _repository;

  // ฟิลด์พื้นฐานที่ดึงจาก database (admin-configurable)
  List<DonationCategoryField> _globalFields = [];

  // ค่าที่กรอกในแต่ละ global field (key = field.id)
  Map<String, dynamic> _globalData = {};

  // ค่าพิเศษสำหรับฟิลด์ที่มี dedicated column ใน DB
  String? _selectedCategoryId;
  ThaiAddress? _selectedAddress;
  bool _addressError = false;

  // ค่าจาก custom fields ของหมวดหมู่
  Map<String, dynamic> _customData = {};

  List<DonationCategory> _categories = [];
  List<Map<String, dynamic>> _communities = [];

  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _repository = DonationRepository(Supabase.instance.client);
    _selectedCategoryId = widget.defaultCategoryId;
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final results = await Future.wait([
        _repository.getGlobalFields(),
        _repository.getCategories(),
        _repository.getCommunities(),
      ]);
      final allCategories = results[1] as List<DonationCategory>;
      // กรอง emergency categories ออก — dropdown นี้แสดงเฉพาะหมวดหมู่บริจาคปกติ
      final normalCategories = allCategories.where((c) => !c.isEmergency).toList();
      setState(() {
        _globalFields = results[0] as List<DonationCategoryField>;
        _categories = normalCategories;
        _communities = results[2] as List<Map<String, dynamic>>;

        // ถ้าเปิดมาจาก Live page และยังไม่มี defaultCategoryId ที่ตรงกับ normal categories
        // ให้ auto-select หมวดหมู่แรก (default: รายการลำดับแรกของตารางจริงที่ไม่ใช่ emergency)
        if (widget.videoId != null && (_selectedCategoryId == null ||
            !normalCategories.any((c) => c.id == _selectedCategoryId))) {
          _selectedCategoryId = normalCategories.isNotEmpty ? normalCategories.first.id : null;
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading initial data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถโหลดข้อมูลเบื้องต้นได้')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  DonationCategory? get _selectedCategory {
    if (_selectedCategoryId == null) return null;
    final match = _categories.where((c) => c.id == _selectedCategoryId).toList();
    return match.isEmpty ? null : match.first;
  }

  // ==========================================
  // VALIDATION & SUBMIT
  // ==========================================

  Future<void> _reviewAndSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    // ตรวจสอบ address_picker ที่อยู่ใน global fields หรือ hardcode section
    final hasAddressPickerField = _globalFields.any((f) => f.type == 'address_picker');
    if (hasAddressPickerField && _selectedAddress == null) {
      setState(() => _addressError = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาระบุที่อยู่ผู้ร้องขอ')));
      return;
    }

    _formKey.currentState!.save();

    final currentUser = ServiceLocator.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนดำเนินการ')),
      );
      return;
    }

    final selectedCat = _categories.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => _categories.first,
    );

    final confirmed = await _showSummaryDialog(selectedCat);
    if (!confirmed) return;

    _submitRequest(currentUser.id);
  }

  Future<bool> _showSummaryDialog(DonationCategory cat) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.3), // Make barrier a bit lighter for glass effect
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            tween: Tween(begin: 0.85, end: 1.0),
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              child: child,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFE2B0FF).withOpacity(0.15),
                    const Color(0xFF9F44D3).withOpacity(0.15),
                    const Color(0xFF00C6FF).withOpacity(0.15),
                    const Color(0xFF0072FF).withOpacity(0.15),
                  ],
                  stops: [0.0, 0.3, 0.7, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9F44D3).withOpacity(0.25),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20.0), // Border thickness
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(29), // Inner radius
                  color: Colors.white.withOpacity(0.92), // Glass body
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400, maxHeight: 650),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header Banner ──
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.04),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(bottom: BorderSide(color: Colors.grey.shade100, width: 2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ตรวจสอบข้อมูล',
                              style: AppTextStyles.heading5.copyWith(
                                color: AppColors.primary, 
                                fontWeight: FontWeight.bold, 
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'กรุณาตรวจสอบความถูกต้องก่อนส่ง',
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // ── Content ──
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card 1: ข้อมูลหลัก
                        _buildSectionHeader(Icons.info_outline_rounded, 'ข้อมูลพื้นฐาน'),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                            ],
                          ),
                          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 4),
                          child: Column(
                            children: [
                              _summaryRow(Icons.category_rounded, 'หมวดหมู่', cat.name),
                              ..._globalFields.where((f) => f.id != 'category_id').map((field) {
                                final rawVal = _globalData[field.id];
                                if (rawVal == null || rawVal.toString().isEmpty) return const SizedBox.shrink();
                                String displayVal = rawVal.toString();
                                if (field.type == 'date') {
                                  final dt = rawVal is DateTime ? rawVal : DateTime.tryParse(rawVal.toString());
                                  displayVal = dt != null ? ThaiDateUtils.formatShortDateBE(dt) : rawVal.toString();
                                } else if (field.id == 'community_id') {
                                  final comm = _communities.where((c) => c['id'].toString() == rawVal.toString()).firstOrNull;
                                  displayVal = comm?['name']?.toString() ?? rawVal.toString();
                                } else if (field.type == 'boolean') {
                                  displayVal = rawVal == true ? 'ใช่' : 'ไม่ใช่';
                                } else if (field.type == 'address_picker' && _selectedAddress != null) {
                                  displayVal = _selectedAddress!.fullAddress;
                                } else if (field.type == 'number' && rawVal != null) {
                                  final num = double.tryParse(rawVal.toString());
                                  displayVal = num != null ? '฿${NumberFormat('#,##0').format(num)}' : rawVal.toString();
                                }
                                return _summaryRow(_fieldIcon(field), field.label, displayVal);
                              }),
                            ],
                          ),
                        ),

                        // Card 2: ข้อมูลเพิ่มเติมตามหมวดหมู่
                        if (_customData.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _buildSectionHeader(Icons.dashboard_customize_rounded, 'ข้อมูลเฉพาะหมวดหมู่'),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                              ],
                            ),
                            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 4),
                            child: Column(
                              children: _customData.entries.map((e) {
                                final rawVal = e.value;
                                if (rawVal == null || rawVal.toString().isEmpty) return const SizedBox.shrink();
                                
                                final customFieldList = cat.customFields ?? [];
                                final matchField = customFieldList.where((f) => f.id == e.key).firstOrNull;
                                final label = matchField?.label ?? e.key;
                                final type = matchField?.type ?? 'text';
                                
                                String displayVal = rawVal.toString();
                                if (type == 'image') {
                                  displayVal = 'แนบรูปรับรองแล้ว';
                                } else if (type == 'date') {
                                  final dt = rawVal is DateTime ? rawVal : DateTime.tryParse(rawVal.toString());
                                  displayVal = dt != null ? ThaiDateUtils.formatShortDateBE(dt) : rawVal.toString();
                                } else if (type == 'number') {
                                  final num = double.tryParse(rawVal.toString());
                                  displayVal = num != null ? NumberFormat('#,##0.##').format(num) : rawVal.toString();
                                } else if (type == 'boolean') {
                                  displayVal = rawVal == true ? 'ใช่' : 'ไม่ใช่';
                                }
                                return _summaryRow(
                                  matchField != null ? _fieldIcon(matchField) : Icons.data_object_rounded,
                                  label, 
                                  displayVal,
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // ── Footer Actions ──
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.03), offset: const Offset(0, -5), blurRadius: 10),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                          ),
                          child: Text('กลับไปแก้ไข', style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: AppColors.primary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('ยืนยันส่งคำร้อง', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
)) ?? false;
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[700]),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey[800], letterSpacing: 0.2),
        ),
      ],
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: AppColors.primary.withOpacity(0.8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w600, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRequest(String userId) async {
    setState(() => _isSubmitting = true);

    try {
      // สร้าง request data จาก global fields + custom fields
      // ฟิลด์ที่มี dedicated column จะถูก map ตรง ๆ
      final requestData = <String, dynamic>{
        'user_id': userId,
        'category_id': _selectedCategoryId,
        if (widget.videoId != null) 'video_id': widget.videoId,
        'approval_status': DonationApprovalStatus.pending_local.name,
      };

      // Map ค่าจาก global fields ไปยัง DB columns ที่ถูกต้อง
      for (final field in _globalFields) {
        final val = _globalData[field.id];
        if (val == null) continue;

        switch (field.id) {
          case 'title':
            requestData['title'] = val.toString();
            break;
          case 'description':
            requestData['description'] = val.toString();
            break;
          case 'target_amount':
            requestData['target_amount'] = double.tryParse(val.toString()) ?? 0.0;
            break;
          case 'community_id':
            requestData['community_id'] = val.toString();
            break;
          case 'usage_location':
            requestData['usage_location'] = val.toString();
            break;
          case 'needed_date':
            final dt = val is DateTime ? val : DateTime.tryParse(val.toString());
            if (dt != null) requestData['needed_date'] = dt.toIso8601String();
            break;
          case 'is_trending':
            requestData['is_trending'] = val == true;
            break;
          case 'requester_address':
            if (_selectedAddress != null) {
              requestData['requester_address'] = _selectedAddress!.fullAddress;
            }
            break;
          case 'address_picker':
            if (_selectedAddress != null) {
              requestData['requester_address'] = _selectedAddress!.fullAddress;
            }
            break;
          default:
            // ฟิลด์อื่น ๆ ที่ไม่มี dedicated column → เก็บใน custom_data
            break;
        }
      }

      // รวม custom data เพิ่มเติม
      final enrichedCustomData = {
        ..._customData,
        if (_selectedAddress?.localGovType != null)
          'local_gov_type': _selectedAddress!.localGovType,
        if (_selectedAddress?.leaderRole?.leaderTitleTh != null)
          'leader_title': _selectedAddress!.leaderRole!.leaderTitleTh,
      };

      if (enrichedCustomData.isNotEmpty) {
        requestData['custom_data'] = enrichedCustomData;
      }

      // ลบ Logic ส่วนเกินที่บังคับ/สร้าง title ออกอย่างถาวรตามที่ผู้ร้องขอ
      // ตอนนี้ระบบจะส่งข้อมูลแบบ Dynamic จาก Global Fields เท่านั้น

      final newRequestId = await _repository.createRequestWithAutoApproval(
        requestData,
        userId, // ✅ ใช้จาก parameter
        categoryId: _selectedCategoryId,
        skipVolunteerCheck: widget.videoId != null, // ยกเว้นให้ถ้ามาจากการรับงานบน Live
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ส่งคำร้องขอเรียบร้อยแล้ว!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        
        if (widget.videoId != null) {
          // ถ้าเปิดมาจากหน้า Live ให้ปิดหน้านี้เพื่อกลับไปดู Live ต่อ
          Navigator.pop(context, newRequestId);
        } else {
          // ถ้าเปิดแบบปกติ ให้เปลี่ยนหน้าไปหน้าProfile เพื่อดูสถานะคำร้อง
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/profile',
            (route) => route.isFirst,
            arguments: {
              'tabIndex': 0,
              'highlightRequestId': newRequestId,
            },
          );
        }
      }
    } catch (e) {
      debugPrint('Error creating request: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    }
  }

  // ==========================================
  // BUILD WIDGETS
  // ==========================================

  Widget _buildProgressIndicator() {
    final bool section1Done = _selectedCategoryId != null;
    final bool section2Done = _globalFields.any((f) => f.id == 'title' || f.id == 'address_picker' || f.id == 'requester_address')
        ? (_globalData['title']?.toString().isNotEmpty == true)
        : true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          _progressStep(1, 'หมวดหมู่', isActive: true, isDone: section1Done),
          Expanded(
            child: Container(
              height: 2,
              color: section1Done ? AppColors.primary : Colors.grey[300],
            ),
          ),
          _progressStep(2, 'ข้อมูลพื้นฐาน', isActive: section1Done, isDone: section2Done),
        ],
      ),
    );
  }

  Widget _progressStep(int step, String label, {bool isActive = false, bool isDone = false}) {
    final color = isDone ? AppColors.primary : (isActive ? AppColors.primary : Colors.grey[400]!);
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone ? AppColors.primary : Colors.white,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text('$step', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: color, fontSize: 11)),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.heading5.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration({required String hintText, required IconData prefixIcon}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTextStyles.bodyMedium.copyWith(color: Colors.grey[400]),
      prefixIcon: Icon(prefixIcon, color: AppColors.primary.withOpacity(0.5), size: 22),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey[200]!, width: 1)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)),
    );
  }

  IconData _fieldIcon(DonationCategoryField field) {
    switch (field.type) {
      case 'date': return Icons.calendar_today_rounded;
      case 'number': return Icons.numbers_rounded;
      case 'long_text': return Icons.description_rounded;
      case 'community_dropdown': return Icons.location_city_rounded;
      case 'address_picker': return Icons.home_rounded;
      case 'boolean': return Icons.toggle_on_rounded;
      case 'image': return Icons.image_rounded;
      default: return Icons.text_fields_rounded;
    }
  }

  /// Render ฟิลด์พื้นฐาน 1 ฟิลด์ จาก global fields ที่ admin กำหนด
  Widget _buildGlobalField(DonationCategoryField field) {
    switch (field.type) {
      case 'text':
        return TextFormField(
          initialValue: _globalData[field.id]?.toString(),
          decoration: _buildInputDecoration(
            hintText: field.label,
            prefixIcon: field.id == 'title'
                ? Icons.title_rounded
                : field.id == 'usage_location'
                    ? Icons.place_rounded
                    : Icons.text_fields_rounded,
          ).copyWith(labelText: field.label + (field.isRequired ? ' *' : '')),
          style: AppTextStyles.bodyMedium,
          validator: (val) => (field.isRequired && (val == null || val.trim().isEmpty)) ? 'กรุณากรอก${field.label}' : null,
          onChanged: (val) => _globalData[field.id] = val,
          onSaved: (val) => _globalData[field.id] = val ?? '',
        );

      case 'long_text':
        return TextFormField(
          initialValue: _globalData[field.id]?.toString(),
          decoration: _buildInputDecoration(
            hintText: field.label,
            prefixIcon: Icons.description_rounded,
          ).copyWith(
            labelText: field.label + (field.isRequired ? ' *' : ''),
            alignLabelWithHint: true,
          ),
          style: AppTextStyles.bodyMedium,
          maxLines: 4,
          validator: (val) => (field.isRequired && (val == null || val.trim().isEmpty)) ? 'กรุณากรอก${field.label}' : null,
          onChanged: (val) => _globalData[field.id] = val,
          onSaved: (val) => _globalData[field.id] = val ?? '',
        );

      case 'number':
        return TextFormField(
          initialValue: _globalData[field.id]?.toString(),
          decoration: _buildInputDecoration(
            hintText: field.label,
            prefixIcon: Icons.monetization_on_rounded,
          ).copyWith(labelText: field.label + (field.isRequired ? ' *' : '')),
          style: AppTextStyles.bodyMedium,
          keyboardType: TextInputType.number,
          validator: (val) => (field.isRequired && (val == null || val.trim().isEmpty)) ? 'กรุณากรอก${field.label}' : null,
          onChanged: (val) => _globalData[field.id] = val,
          onSaved: (val) => _globalData[field.id] = val ?? '',
        );

      case 'date':
        return ThaiBuddhistDatePickerField(
          value: _globalData[field.id] != null
              ? (_globalData[field.id] is DateTime
                  ? _globalData[field.id] as DateTime
                  : DateTime.tryParse(_globalData[field.id].toString()))
              : null,
          label: field.label,
          isRequired: field.isRequired,
          onDateSelected: (date) {
            setState(() {
              _globalData[field.id] = date.toIso8601String();
            });
          },
        );

      case 'community_dropdown':
        return DropdownButtonFormField<String>(
          value: _globalData[field.id]?.toString(),
          decoration: _buildInputDecoration(
            hintText: field.label,
            prefixIcon: Icons.location_city_rounded,
          ).copyWith(labelText: field.label + (field.isRequired ? ' *' : '')),
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[500]),
          items: _communities.map((c) => DropdownMenuItem(
            value: c['id'].toString(),
            child: Text(c['name']?.toString() ?? 'ไม่ทราบชื่อ', style: AppTextStyles.bodyMedium, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (val) => setState(() => _globalData[field.id] = val),
          validator: (val) => (field.isRequired && val == null) ? 'กรุณาเลือก${field.label}' : null,
          onSaved: (val) => _globalData[field.id] = val,
        );

      case 'address_picker':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (field.label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  field.label + (field.isRequired ? ' *' : ''),
                  style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[700], fontWeight: FontWeight.w500),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _addressError ? Colors.redAccent : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: ThaiAddressPicker(
                initialAddress: _selectedAddress,
                onAddressSelected: (address) {
                  setState(() {
                    _selectedAddress = address;
                    _addressError = false;
                    _globalData[field.id] = address.fullAddress;
                  });
                },
              ),
            ),
            if (_addressError)
              const Padding(
                padding: EdgeInsets.only(left: 16, top: 4),
                child: Text('กรุณาระบุที่อยู่ผู้ร้องขอ', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
          ],
        );

      case 'boolean':
        return StatefulBuilder(
          builder: (context, localSetState) {
            final val = _globalData[field.id] == true;
            return SwitchListTile(
              title: Text(field.label, style: const TextStyle(fontWeight: FontWeight.bold)),
              value: val,
              activeColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              tileColor: Colors.grey[50],
              onChanged: (newVal) {
                setState(() => _globalData[field.id] = newVal);
              },
            );
          },
        );

      case 'image':
        return ImageUploadField(
          label: field.label,
          isRequired: field.isRequired,
          bucket: 'donations',
          pathPrefix: 'requests/',
          initialUrl: _globalData[field.id]?.toString(),
          onUploaded: (url) => setState(() => _globalData[field.id] = url),
          onRemoved: () => setState(() => _globalData[field.id] = null),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  /// Render custom fields ของหมวดหมู่ที่เลือก
  List<Widget> _buildCategoryCustomFields() {
    final category = _selectedCategory;
    if (category == null || category.customFields.isEmpty) return [];

    return category.customFields.map((field) {
      // ── date ──
      if (field.type == 'date') {
        return Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: ThaiBuddhistDatePickerField(
            value: _customData[field.id] != null
                ? DateTime.tryParse(_customData[field.id].toString())
                : null,
            label: field.label,
            isRequired: field.isRequired,
            onDateSelected: (date) {
              setState(() {
                _customData[field.id] = date.toIso8601String();
              });
            },
          ),
        );
      }

      // ── address_picker ──
      if (field.type == 'address_picker') {
        final currentAddress = _customData[field.id] is ThaiAddress
            ? _customData[field.id] as ThaiAddress
            : null;
        return Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (field.label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    field.label + (field.isRequired ? ' *' : ''),
                    style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[700], fontWeight: FontWeight.w500),
                  ),
                ),
              ThaiAddressPicker(
                initialAddress: currentAddress,
                onAddressSelected: (address) {
                  setState(() {
                    _customData[field.id] = address.fullAddress;
                    // เก็บ address object แยกเพื่อ enrich custom_data
                    _customData['${field.id}_obj'] = address;
                  });
                },
              ),
            ],
          ),
        );
      }

      // ── community_dropdown ──
      if (field.type == 'community_dropdown') {
        return Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: DropdownButtonFormField<String>(
            value: _customData[field.id]?.toString(),
            decoration: _buildInputDecoration(
              hintText: field.label,
              prefixIcon: Icons.location_city_rounded,
            ).copyWith(labelText: field.label + (field.isRequired ? ' *' : '')),
            isExpanded: true,
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[500]),
            items: _communities.map((c) => DropdownMenuItem(
              value: c['id'].toString(),
              child: Text(c['name']?.toString() ?? 'ไม่ทราบชื่อ', style: AppTextStyles.bodyMedium, overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (val) => setState(() => _customData[field.id] = val),
            validator: (val) => (field.isRequired && val == null) ? 'กรุณาเลือก${field.label}' : null,
            onSaved: (val) => _customData[field.id] = val,
          ),
        );
      }

      // ── boolean ──
      if (field.type == 'boolean') {
        return Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: SwitchListTile(
            title: Text(field.label, style: const TextStyle(fontWeight: FontWeight.w500)),
            value: _customData[field.id] == true,
            activeThumbColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: Colors.grey[50],
            onChanged: (val) => setState(() => _customData[field.id] = val),
          ),
        );
      }

      // ── image upload ──
      if (field.type == 'image') {
        return Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: ImageUploadField(
            label: field.label,
            isRequired: field.isRequired,
            bucket: 'donations',
            pathPrefix: 'requests/custom/',
            initialUrl: _customData[field.id]?.toString(),
            onUploaded: (url) => setState(() => _customData[field.id] = url),
            onRemoved: () => setState(() => _customData[field.id] = null),
          ),
        );
      }

      // ── text / long_text / number (fallback) ──
      return Padding(
        padding: const EdgeInsets.only(top: 16.0),
        child: TextFormField(
          decoration: _buildInputDecoration(
            hintText: field.label,
            prefixIcon: field.type == 'number' ? Icons.numbers : Icons.text_fields,
          ).copyWith(
            labelText: field.label + (field.isRequired ? ' *' : ''),
            alignLabelWithHint: field.type == 'long_text',
          ),
          style: AppTextStyles.bodyMedium,
          keyboardType: field.type == 'number' ? TextInputType.number : TextInputType.text,
          maxLines: field.type == 'long_text' ? 3 : 1,
          validator: (val) => (field.isRequired && (val == null || val.isEmpty)) ? 'กรุณาระบุข้อมูล' : null,
          onSaved: (val) => _customData[field.id] = val,
        ),
      );
    }).toList();
  }

  // =========================================================
  // หน้า Build หลัก — Render global fields ทั้งหมด dynamically
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text('สร้างคำร้องขอ', style: AppTextStyles.heading4),
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primary,
            elevation: 0,
            centerTitle: true,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    children: [
                      _buildProgressIndicator(),

                      // ── Card หมวดหมู่ (เลือกก่อนเสมอ) ──
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('เลือกหมวดหมู่', Icons.category_rounded, 'เลือกประเภทความช่วยเหลือที่ต้องการ'),
                            // ทั้ง Reporter และ Responder เปลี่ยนหมวดหมู่ได้
                            // แต่แสดงเฉพาะหมวดหมู่บริจาคปกติ (ไม่ใช่ emergency) เท่านั้น
                            DropdownButtonFormField<String>(
                              decoration: _buildInputDecoration(hintText: 'หมวดหมู่การบริจาค', prefixIcon: Icons.category_rounded),
                              value: _selectedCategoryId,
                              isExpanded: true,
                              icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[500]),
                              items: _categories.map((cat) => DropdownMenuItem(
                                value: cat.id,
                                child: Text(cat.name, style: AppTextStyles.bodyMedium, overflow: TextOverflow.ellipsis),
                              )).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedCategoryId = val;
                                  _customData.clear();
                                });
                              },
                              validator: (val) => val == null ? 'กรุณาเลือกหมวดหมู่' : null,
                            ),
                            const SizedBox(height: 8),
                            if (widget.videoId != null)
                              Text(
                                'เลือกประเภทสิ่งที่ต้องการรับบริจาค (ไม่รวมหมวดฉุกเฉิน)',
                                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                              ),
                          ],
                        ),
                      ),

                      // ── Card ฟิลด์พื้นฐาน (global fields จาก admin) ──
                      if (_selectedCategoryId != null && _globalFields.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
                          ),
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionTitle(
                                'ข้อมูลพื้นฐาน',
                                Icons.volunteer_activism,
                                'ข้อมูลที่ผู้ร้องขอทุกคนต้องกรอก',
                              ),
                              // Render global fields แยกตาม type ข้ามฟิลด์ category_id (hardcode แล้วด้านบน)
                              ..._globalFields
                                  .where((f) => f.id != 'category_id')
                                  .expand((field) => [
                                        const SizedBox(height: 16),
                                        _buildGlobalField(field),
                                      ]),
                            ],
                          ),
                        ),
                      ],

                      // ── Card Custom fields ของหมวดหมู่ (ถ้ามี) ──
                      if (_selectedCategoryId != null && (_selectedCategory?.customFields.isNotEmpty ?? false)) ...[
                        const SizedBox(height: 24),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
                          ),
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionTitle(
                                'ข้อมูลเฉพาะหมวดหมู่',
                                Icons.tune_rounded,
                                'ข้อมูลเพิ่มเติมสำหรับ ${_selectedCategory?.name ?? 'หมวดหมู่นี้'}',
                              ),
                              ..._buildCategoryCustomFields(),
                            ],
                          ),
                        ),
                      ],

                      if (_selectedCategoryId != null) ...[
                        const SizedBox(height: 36),
                        // ── Submit Button ──
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF76A5A5), Color(0xFF4A6A8A)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                            ),
                            onPressed: _isSubmitting ? null : _reviewAndSubmit,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.fact_check_rounded, color: Colors.white, size: 22),
                                SizedBox(width: 10),
                                Text('ตรวจสอบและส่งคำร้อง', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
        ),
        // Full-screen loading overlay
        if (_isSubmitting)
          Container(
            color: Colors.black.withOpacity(0.3),
            child: const Center(
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('กำลังส่งคำร้องขอ...'),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
