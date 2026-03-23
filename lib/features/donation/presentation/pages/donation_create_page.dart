import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../services/service_locator.dart';
import '../../data/repositories/donation_repository.dart';
import '../../models/donation_models.dart';
import '../../../../shared/widgets/thai_address_picker/thai_address_picker.dart';
import 'package:intl/intl.dart';

class DonationCreatePage extends StatefulWidget {
  final String? videoId;
  const DonationCreatePage({super.key, this.videoId});

  @override
  State<DonationCreatePage> createState() => _DonationCreatePageState();
}

class _DonationCreatePageState extends State<DonationCreatePage> {
  final _formKey = GlobalKey<FormState>();
  late DonationRepository _repository;

  // Form Fields
  String _title = '';
  String _description = '';
  double _targetAmount = 0;
  String? _selectedCategoryId;
  String? _selectedCommunityId;
  DateTime? _neededDate;
  bool _neededDateError = false; // [FIX 3] validation state for date
  Map<String, dynamic> _customData = {};
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  ThaiAddress? _selectedAddress;

  List<DonationCategory> _categories = [];
  List<Map<String, dynamic>> _communities = [];
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _repository = DonationRepository(Supabase.instance.client);
    _loadInitialData();
  }

  @override
  void dispose() {
    _locationController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final categories = await _repository.getCategories();
      final communities = await _repository.getCommunities();
      setState(() {
        _categories = categories;
        _communities = communities;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading initial data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถโหลดข้อมูลเบื้องต้นได้')),
        );
      }
    }
  }

  // [FIX] ดึงหมวดหมู่ที่เลือกอยู่
  DonationCategory? get _selectedCategory {
    if (_selectedCategoryId == null) return null;
    final match = _categories.where((c) => c.id == _selectedCategoryId).toList();
    return match.isEmpty ? null : match.first;
  }

  // [FIX] ตรวจสอบว่าหมวดหมู่ที่เลือกมี Custom Fields หรือไม่
  bool get _hasCategoryCustomFields {
    final cat = _selectedCategory;
    return cat != null && cat.customFields.isNotEmpty;
  }

  // [FIX 1] ตรวจสอบว่าหมวดหมู่ที่เลือกต้องการช่องยอดเงินหรือไม่
  bool get _showAmountField {
    if (_hasCategoryCustomFields) return false; // Custom fields จะจัดการเองถ้ามี
    final cat = _selectedCategory;
    if (cat == null) return true;
    const nonMonetaryKeywords = ['organ', 'caregiving', 'transport', 'shelter'];
    final nameEn = (cat.nameEn ?? '').toLowerCase();
    return !nonMonetaryKeywords.any((k) => nameEn.contains(k));
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _neededDate) {
      setState(() {
        _neededDate = picked;
        _neededDateError = false; // clear error when selected
      });
    }
  }

  Future<void> _reviewAndSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    // UI fields removed, no need to validate _neededDate or _selectedCommunityId

    _formKey.currentState!.save();

    final currentUser = ServiceLocator.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนดำเนินการ')),
      );
      return;
    }

    final selectedCat = _categories.firstWhere((c) => c.id == _selectedCategoryId, orElse: () => _categories.first);

    // [FIX 4] แสดง Summary Dialog ก่อน Submit
    final confirmed = await _showSummaryDialog(selectedCat);
    if (!confirmed) return;

    _submitRequest(currentUser.id);
  }

  // [FIX 4]: Summary review dialog
  Future<bool> _showSummaryDialog(DonationCategory cat) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.fact_check_rounded, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            const Text('ตรวจสอบข้อมูลก่อนส่ง'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _summaryRow(Icons.category_rounded, 'หมวดหมู่', cat.name),
              _summaryRow(Icons.title_rounded, 'หัวข้อ', _title),
              if (_showAmountField) _summaryRow(Icons.monetization_on_rounded, 'ยอดเป้าหมาย', '฿${NumberFormat('#,##0').format(_targetAmount)}'),
              if (_description.isNotEmpty) _summaryRow(Icons.description_rounded, 'รายละเอียด', _description),
              const Divider(height: 24),
              if (_selectedAddress != null) _summaryRow(Icons.home_rounded, 'ที่อยู่', _selectedAddress!.fullAddress),
              if (_customData.isNotEmpty) ...[
                const Divider(height: 24),
                Text('ข้อมูลเพิ่มเติม', style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[500], fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._customData.entries.map((e) => _summaryRow(Icons.data_object_rounded, e.key, e.value?.toString() ?? '-')),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('แก้ไข', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            label: const Text('ยืนยันส่งคำร้อง', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primary.withOpacity(0.6)),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: '$label: ', style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[600])),
                  TextSpan(text: value, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRequest(String userId) async {
    setState(() => _isSubmitting = true);

    try {
      final requestData = {
        'user_id': userId,
        'category_id': _selectedCategoryId,
        'video_id': widget.videoId,
        'community_id': _selectedCommunityId ?? 'unknown', // Set default since UI removed
        'title': _title,
        'description': _description,
        'target_amount': _showAmountField ? _targetAmount : null,
        'current_amount': 0,
        'needed_date': (_neededDate ?? DateTime.now().add(const Duration(days: 30))).toIso8601String(), // Set default
        'usage_location': _locationController.text.isEmpty ? 'ไม่ระบุ' : _locationController.text, // Set default
        'requester_address': _selectedAddress?.fullAddress ?? '',
        'approval_status': DonationApprovalStatus.pending_local.name,
        'status': 'active',
        'is_trending': false,
        'custom_data': _customData,
      };

      await _repository.createRequest(requestData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ส่งคำร้องขอเรียบร้อยแล้ว! กำลังรอการยืนยันจากผู้นำชุมชน'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
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

  // [FIX 2] Progress step indicator widget
  Widget _buildProgressIndicator() {
    final bool section1Done = _selectedCategoryId != null && _title.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          _progressStep(1, 'ข้อมูลความต้องการ', isActive: true, isDone: section1Done),
          Expanded(
            child: Container(
              height: 2,
              color: section1Done ? AppColors.primary : Colors.grey[300],
            ),
          ),
          _progressStep(2, 'การยืนยันพื้นที่', isActive: section1Done, isDone: _selectedAddress != null),
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

  List<Widget> _buildCustomFields() {
    final category = _selectedCategory;
    if (category == null || category.customFields.isEmpty) return [];

    return category.customFields.map((field) {
      if (field.type == 'date') {
        return Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: TextFormField(
            decoration: _buildInputDecoration(hintText: field.label, prefixIcon: Icons.calendar_month).copyWith(
              labelText: field.label + (field.isRequired ? ' *' : ''),
            ),
            readOnly: true,
            style: AppTextStyles.bodyMedium,
            controller: TextEditingController(text: _customData[field.id]?.toString() ?? ''),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setState(() {
                  _customData[field.id] = DateFormat('dd/MM/yyyy').format(picked);
                });
              }
            },
            validator: (val) => (field.isRequired && (val == null || val.isEmpty)) ? 'กรุณาระบุข้อมูล' : null,
          ),
        );
      }

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

  InputDecoration _buildInputDecoration({required String hintText, required IconData prefixIcon}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTextStyles.bodyMedium.copyWith(color: Colors.grey[400]),
      prefixIcon: Icon(prefixIcon, color: AppColors.primary.withOpacity(0.5), size: 22),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
  }

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
          body: _isLoading && _categories.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    children: [
                      // [FIX 2] Progress Indicator
                      _buildProgressIndicator(),

                      // Section 1: Request Details
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('ข้อมูลความต้องการ', Icons.volunteer_activism, 'ระบุสิ่งที่คุณต้องการความช่วยเหลือ'),

                            // Category Dropdown
                            DropdownButtonFormField<String>(
                              decoration: _buildInputDecoration(hintText: 'หมวดหมู่การบริจาค', prefixIcon: Icons.category_rounded),
                              value: _selectedCategoryId,
                              icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[500]),
                              items: _categories.map((cat) {
                                return DropdownMenuItem(
                                  value: cat.id,
                                  child: Text(cat.name, style: AppTextStyles.bodyMedium),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedCategoryId = val;
                                  _customData.clear();
                                  _amountController.clear();
                                });
                              },
                              validator: (val) => val == null ? 'กรุณาเลือกหมวดหมู่' : null,
                            ),

                            // Progressive Disclosure: แสดงฟิลด์เพิ่มเติมหลังเลือกหมวดหมู่
                            AnimatedCrossFade(
                              duration: const Duration(milliseconds: 400),
                              crossFadeState: _selectedCategoryId == null
                                  ? CrossFadeState.showFirst
                                  : CrossFadeState.showSecond,
                              firstChild: Padding(
                                padding: const EdgeInsets.only(top: 20, bottom: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                                    const SizedBox(width: 8),
                                    Text(
                                      'เลือกหมวดหมู่ก่อนเพื่อดูฟิลด์ที่ต้องกรอก',
                                      style: AppTextStyles.bodySmall.copyWith(color: Colors.grey, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              secondChild: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 16),
                                  // Title
                                  TextFormField(
                                    decoration: _buildInputDecoration(hintText: 'หัวข้อคำร้องขอ (เช่น ขอรับผ้าห่ม)', prefixIcon: Icons.title_rounded),
                                    style: AppTextStyles.bodyMedium,
                                    validator: (val) => (val == null || val.isEmpty) ? 'กรุณาระบุหัวข้อ' : null,
                                    onChanged: (val) => setState(() => _title = val),
                                    onSaved: (val) => _title = val ?? '',
                                  ),
                                  const SizedBox(height: 16),
                                  // [SMART] Amount + Description or Custom Fields
                                  if (!_hasCategoryCustomFields) ...[
                                    if (_showAmountField) ...[
                                      TextFormField(
                                        controller: _amountController,
                                        decoration: _buildInputDecoration(hintText: 'จำนวนเงินหรือยอดเป้าหมาย (บาท)', prefixIcon: Icons.monetization_on_rounded),
                                        keyboardType: TextInputType.number,
                                        style: AppTextStyles.bodyMedium,
                                        validator: (val) => (val == null || val.isEmpty) ? 'กรุณาระบุยอดเป้าหมาย' : null,
                                        onSaved: (val) => _targetAmount = double.tryParse(val ?? '0') ?? 0,
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                    TextFormField(
                                      decoration: _buildInputDecoration(hintText: 'รายละเอียดเหตุผลความจำเป็น...', prefixIcon: Icons.description_rounded).copyWith(
                                        alignLabelWithHint: true,
                                      ),
                                      style: AppTextStyles.bodyMedium,
                                      maxLines: 4,
                                      validator: (val) => (val == null || val.isEmpty) ? 'กรุณาเพิ่มรายละเอียด' : null,
                                      onSaved: (val) => _description = val ?? '',
                                    ),
                                  ] else ...[
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                                      child: Row(
                                        children: [
                                          Icon(Icons.tune, size: 14, color: Colors.grey[500]),
                                          const SizedBox(width: 6),
                                          Text(
                                            'ฟิลด์นี้ถูกกำหนดโดยผู้ดูแลระบบ',
                                            style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[500], fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  // Dynamic Custom Fields
                                  ..._buildCustomFields(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Section 2 + Submit: แสดงเฉพาะเมื่อเลือกหมวดหมู่แล้ว
                      if (_selectedCategoryId != null) ...[
                      const SizedBox(height: 24),

                      // Section 2: Verification and Location
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('การยืนยันพื้นที่', Icons.security_rounded, 'เริ่มจากกรอกรหัสไปรษณีย์เพื่อระบุที่อยู่อัตโนมัติ'),

                            // Thai Address Picker (Cascading)
                            ThaiAddressPicker(
                              onAddressSelected: (address) {
                                setState(() => _selectedAddress = address);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Submit Button — [FIX 4] calls review first
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
                      ], // end if (_selectedCategoryId != null)
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
        ),
        // [FIX] Full-screen loading overlay while submitting
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
