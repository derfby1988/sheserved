import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/erp/presentation/providers/organization_settings_provider.dart';
import '../features/admin/models/organization_settings.dart';
import '../features/erp/presentation/widgets/glass_card.dart';
import '../features/erp/presentation/providers/dashboard_theme_provider.dart';
import '../features/erp/data/models/dashboard_theme.dart';

class OrganizationSettingsPage extends ConsumerStatefulWidget {
  const OrganizationSettingsPage({Key? key}) : super(key: key);

  @override
  ConsumerState<OrganizationSettingsPage> createState() => _OrganizationSettingsPageState();
}

class _OrganizationSettingsPageState extends ConsumerState<OrganizationSettingsPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _nameEnController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _taxIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _selfHostApiUrlController = TextEditingController();

  String _currency = 'THB';
  String _language = 'th';
  String _timezone = 'Asia/Bangkok';
  String _storageMode = 'cloud';

  final Map<String, _BranchControllers> _branchControllers = {};
  String? _editingBranchId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(organizationSettingsProvider.notifier).loadFromCurrentUser();
      _syncFormFromState();
    });
  }

  void _syncFormFromState() {
    final settings = ref.read(organizationSettingsProvider).settings;
    if (settings == null) return;

    _nameController.text = settings.professionName;
    _nameEnController.text = settings.professionNameEn ?? '';
    _logoUrlController.text = settings.logoUrl ?? '';
    _taxIdController.text = settings.taxId ?? '';
    _phoneController.text = settings.phone ?? '';
    _emailController.text = settings.email ?? '';
    _addressController.text = settings.address ?? '';
    _selfHostApiUrlController.text = settings.selfHostApiUrl ?? '';
    _currency = settings.currency;
    _language = settings.language;
    _timezone = settings.timezone;
    _storageMode = settings.storageMode;

    _branchControllers.clear();
    for (final branch in settings.branches) {
      _branchControllers[branch.id] = _BranchControllers.fromBranch(branch);
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameEnController.dispose();
    _logoUrlController.dispose();
    _taxIdController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _selfHostApiUrlController.dispose();
    for (final bc in _branchControllers.values) {
      bc.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(organizationSettingsProvider.notifier).saveOrganization(
          name: _nameController.text.trim(),
          nameEn: _nameEnController.text.trim(),
          logoUrl: _logoUrlController.text.trim().isEmpty ? null : _logoUrlController.text.trim(),
          taxId: _taxIdController.text.trim().isEmpty ? null : _taxIdController.text.trim(),
          phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
          address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
          currency: _currency,
          language: _language,
          timezone: _timezone,
          storageMode: _storageMode,
          selfHostApiUrl: _selfHostApiUrlController.text.trim().isEmpty ? null : _selfHostApiUrlController.text.trim(),
        );

    if (success && mounted) {
      _showSnackBar('บันทึกข้อมูลองค์กรสำเร็จ', isError: false);
    } else if (mounted) {
      final err = ref.read(organizationSettingsProvider).errorMessage ?? 'บันทึกไม่สำเร็จ';
      _showSnackBar(err, isError: true);
    }
  }

  Future<void> _saveBranch(OrganizationBranch branch) async {
    final ctrls = _branchControllers[branch.id];
    if (ctrls == null) return;

    final updated = await ref.read(organizationSettingsProvider.notifier).saveBranch(
      branchId: branch.id,
      branchCode: ctrls.code.text.trim(),
      branchName: ctrls.name.text.trim(),
      taxId: ctrls.taxId.text.trim().isEmpty ? null : ctrls.taxId.text.trim(),
      branchTaxCode: ctrls.branchTaxCode.text.trim().isEmpty ? null : ctrls.branchTaxCode.text.trim(),
      address: ctrls.address.text.trim().isEmpty ? null : ctrls.address.text.trim(),
      phone: ctrls.phone.text.trim().isEmpty ? null : ctrls.phone.text.trim(),
      email: ctrls.email.text.trim().isEmpty ? null : ctrls.email.text.trim(),
      isMainBranch: branch.isMainBranch,
      isActive: branch.isActive,
    );

    if (updated != null && mounted) {
      setState(() => _editingBranchId = null);
      _showSnackBar('บันทึกสาขาสำเร็จ', isError: false);
      _syncFormFromState();
    } else if (mounted) {
      final err = ref.read(organizationSettingsProvider).errorMessage ?? 'บันทึกสาขาไม่สำเร็จ';
      _showSnackBar(err, isError: true);
    }
  }

  Future<void> _deleteBranch(String branchId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: const Text('ต้องการลบสาขานี้หรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final success = await ref.read(organizationSettingsProvider.notifier).deleteBranch(branchId);
    if (success && mounted) {
      _showSnackBar('ลบสาขาสำเร็จ', isError: false);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orgState = ref.watch(organizationSettingsProvider);
    final themeState = ref.watch(dashboardThemeProvider);
    final isDark = themeState.theme?.isDarkMode ?? false;

    final bgColors = isDark
        ? [const Color(0xFF0F0F0F), const Color(0xFF1A1A1A)]
        : [const Color(0xFFDFF8FF), const Color(0xFFDFF7E8), const Color(0xFFF4E4FB)];
    final textPrimary = isDark ? Colors.white : const Color(0xFF1D2733);
    final textSecondary = isDark ? Colors.white70 : const Color(0xFF617181);

    if (orgState.isLoading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFE8F6FF),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFE8F6FF),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'ตั้งค่าองค์กร',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: textPrimary),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: bgColors,
                stops: isDark ? null : const [0.0, 0.5, 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          if (!isDark) ...[
            Positioned(top: -60, left: -30, child: _Blob(color: const Color(0xFFBFE7FF), size: 180)),
            Positioned(top: 80, right: -50, child: _Blob(color: const Color(0xFFCFEFBA), size: 200)),
            Positioned(bottom: -70, left: 40, child: _Blob(color: const Color(0xFFF0D6FF), size: 190)),
          ],
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _SectionTitle(title: 'ข้อมูลองค์กร', icon: Icons.business, isDark: isDark),
                    const SizedBox(height: 10),
                    GlassCard(
                      section: GlassSection.card,
                      tintColor: const Color(0xFFBFE7FF),
                      borderRadius: 24,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _GlassField(label: 'ชื่อองค์กร (ภาษาไทย)', controller: _nameController, isDark: isDark, validator: (v) => v == null || v.isEmpty ? 'กรุณากรอกชื่อองค์กร' : null),
                          const SizedBox(height: 14),
                          _GlassField(label: 'ชื่อองค์กร (ภาษาอังกฤษ)', controller: _nameEnController, isDark: isDark),
                          const SizedBox(height: 14),
                          _GlassField(label: 'โลโก้ URL', controller: _logoUrlController, isDark: isDark, hint: 'https://...'),
                          const SizedBox(height: 14),
                          _GlassField(label: 'เลขที่ผู้เสียภาษี', controller: _taxIdController, isDark: isDark),
                          const SizedBox(height: 14),
                          _GlassField(label: 'โทรศัพท์', controller: _phoneController, isDark: isDark, keyboardType: TextInputType.phone),
                          const SizedBox(height: 14),
                          _GlassField(label: 'อีเมล', controller: _emailController, isDark: isDark, keyboardType: TextInputType.emailAddress),
                          const SizedBox(height: 14),
                          _GlassField(label: 'ที่อยู่', controller: _addressController, isDark: isDark, maxLines: 2),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SectionTitle(title: 'การตั้งค่าทั่วไป', icon: Icons.settings, isDark: isDark),
                    const SizedBox(height: 10),
                    GlassCard(
                      section: GlassSection.card,
                      tintColor: const Color(0xFFF0E7B4),
                      borderRadius: 24,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _GlassDropdown(
                            label: 'ภาษา', value: _language,
                            items: const [MapEntry('th', 'ภาษาไทย'), MapEntry('en', 'English')],
                            isDark: isDark, onChanged: (v) => setState(() => _language = v),
                          ),
                          const SizedBox(height: 14),
                          _GlassDropdown(
                            label: 'สกุลเงิน', value: _currency,
                            items: const [MapEntry('THB', 'บาท (THB)'), MapEntry('USD', 'ดอลลาร์ (USD)')],
                            isDark: isDark, onChanged: (v) => setState(() => _currency = v),
                          ),
                          const SizedBox(height: 14),
                          _GlassDropdown(
                            label: 'เขตเวลา', value: _timezone,
                            items: const [MapEntry('Asia/Bangkok', 'Asia/Bangkok'), MapEntry('UTC', 'UTC')],
                            isDark: isDark, onChanged: (v) => setState(() => _timezone = v),
                          ),
                          const SizedBox(height: 14),
                          _GlassDropdown(
                            label: 'โหมดจัดเก็บข้อมูล', value: _storageMode,
                            items: const [
                              MapEntry('cloud', 'Cloud (Supabase)'),
                              MapEntry('self_host', 'Self-Host'),
                              MapEntry('hybrid', 'Hybrid'),
                            ],
                            isDark: isDark, onChanged: (v) => setState(() => _storageMode = v),
                          ),
                          if (_storageMode != 'cloud') ...[
                            const SizedBox(height: 14),
                            _GlassField(label: 'Self-Host API URL', controller: _selfHostApiUrlController, isDark: isDark, hint: 'https://192.168.1.111:8080'),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SectionTitle(title: 'สาขา', icon: Icons.account_tree, isDark: isDark),
                    const SizedBox(height: 10),
                    _buildBranches(orgState, isDark, textPrimary, textSecondary),
                    const SizedBox(height: 32),
                    _GlassActionButton(
                      label: 'บันทึกข้อมูลองค์กร',
                      icon: Icons.save_rounded,
                      tintColor: const Color(0xFF4F7DF3),
                      isDark: isDark,
                      isLoading: orgState.isSaving,
                      onTap: _save,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranches(
    OrganizationSettingsState orgState,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
  ) {
    final branches = orgState.settings?.branches ?? [];
    if (branches.isEmpty) {
      return GlassCard(
        section: GlassSection.card,
        tintColor: const Color(0xFFE8E0F0),
        borderRadius: 20,
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            'ยังไม่มีสาขา',
            style: GoogleFonts.inter(fontSize: 14, color: textSecondary),
          ),
        ),
      );
    }

    return Column(
      children: branches.map((branch) {
        final isEditing = _editingBranchId == branch.id;
        final ctrls = _branchControllers[branch.id];

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            section: GlassSection.card,
            tintColor: branch.isMainBranch ? const Color(0xFFBDEBDB) : const Color(0xFFE8E0F0),
            borderRadius: 20,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            (branch.isMainBranch ? const Color(0xFF4CAF50) : const Color(0xFF9E9E9E))
                                .withOpacity(isDark ? 0.4 : 0.2),
                            (branch.isMainBranch ? const Color(0xFF4CAF50) : const Color(0xFF9E9E9E))
                                .withOpacity(isDark ? 0.2 : 0.1),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          branch.isMainBranch ? Icons.star_rounded : Icons.store_rounded,
                          size: 20,
                          color: branch.isMainBranch ? const Color(0xFF4CAF50) : textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            branch.branchName,
                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${branch.branchCode}${branch.branchTaxCode != null && branch.branchTaxCode!.isNotEmpty ? ' · รหัสสาขาภาษี: ${branch.branchTaxCode}' : ''}',
                            style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (branch.isMainBranch)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: const Color(0xFF4CAF50).withOpacity(isDark ? 0.25 : 0.12),
                          border: Border.all(
                            color: const Color(0xFF4CAF50).withOpacity(isDark ? 0.4 : 0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'สาขาหลัก',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF2E7D32)),
                        ),
                      ),
                    const SizedBox(width: 8),
                    if (!isEditing) ...[
                      _IconBtn(icon: Icons.edit_rounded, tintColor: const Color(0xFF4F7DF3), isDark: isDark, onTap: () => setState(() => _editingBranchId = branch.id)),
                      const SizedBox(width: 4),
                      if (!branch.isMainBranch)
                        _IconBtn(icon: Icons.delete_rounded, tintColor: const Color(0xFFE53935), isDark: isDark, onTap: () => _deleteBranch(branch.id)),
                    ] else
                      _IconBtn(icon: Icons.close_rounded, tintColor: textSecondary, isDark: isDark, onTap: () => setState(() => _editingBranchId = null)),
                  ],
                ),
                if (isEditing && ctrls != null) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0x1A000000)),
                  const SizedBox(height: 16),
                  _GlassField(label: 'รหัสสาขา', controller: ctrls.code, isDark: isDark),
                  const SizedBox(height: 12),
                  _GlassField(label: 'ชื่อสาขา', controller: ctrls.name, isDark: isDark),
                  const SizedBox(height: 12),
                  _GlassField(label: 'รหัสสาขาภาษี', controller: ctrls.branchTaxCode, isDark: isDark, hint: 'เช่น 00000, 00001'),
                  const SizedBox(height: 12),
                  _GlassField(label: 'เลขที่ผู้เสียภาษี', controller: ctrls.taxId, isDark: isDark),
                  const SizedBox(height: 12),
                  _GlassField(label: 'โทรศัพท์', controller: ctrls.phone, isDark: isDark, keyboardType: TextInputType.phone),
                  const SizedBox(height: 12),
                  _GlassField(label: 'อีเมล', controller: ctrls.email, isDark: isDark, keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  _GlassField(label: 'ที่อยู่', controller: ctrls.address, isDark: isDark, maxLines: 2),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _GlassActionButton(
                          label: 'บันทึกสาขา',
                          icon: Icons.save_rounded,
                          tintColor: const Color(0xFF4CAF50),
                          isDark: isDark,
                          isLoading: orgState.isSaving,
                          onTap: () => _saveBranch(branch),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _BranchControllers {
  final TextEditingController code;
  final TextEditingController name;
  final TextEditingController taxId;
  final TextEditingController branchTaxCode;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController address;

  _BranchControllers({
    required this.code,
    required this.name,
    required this.taxId,
    required this.branchTaxCode,
    required this.phone,
    required this.email,
    required this.address,
  });

  factory _BranchControllers.fromBranch(OrganizationBranch branch) {
    return _BranchControllers(
      code: TextEditingController(text: branch.branchCode),
      name: TextEditingController(text: branch.branchName),
      taxId: TextEditingController(text: branch.taxId ?? ''),
      branchTaxCode: TextEditingController(text: branch.branchTaxCode ?? ''),
      phone: TextEditingController(text: branch.phone ?? ''),
      email: TextEditingController(text: branch.email ?? ''),
      address: TextEditingController(text: branch.address ?? ''),
    );
  }

  void dispose() {
    code.dispose();
    name.dispose();
    taxId.dispose();
    branchTaxCode.dispose();
    phone.dispose();
    email.dispose();
    address.dispose();
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.45),
          boxShadow: [BoxShadow(color: color.withOpacity(0.20), blurRadius: 70, spreadRadius: 25)],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isDark;
  const _SectionTitle({required this.title, required this.icon, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1D2733);
    return Row(
      children: [
        Icon(icon, size: 18, color: textPrimary.withOpacity(0.7)),
        const SizedBox(width: 8),
        Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
      ],
    );
  }
}

class _GlassField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool isDark;
  final String? hint;
  final TextInputType? keyboardType;
  final int? maxLines;
  final String? Function(String?)? validator;

  const _GlassField({
    required this.label,
    required this.controller,
    required this.isDark,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1D2733);
    final textSecondary = isDark ? Colors.white60 : const Color(0xFF8A9AAC);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: textPrimary.withOpacity(0.85))),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          style: GoogleFonts.inter(fontSize: 14, color: textPrimary, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 13.5, color: textSecondary.withOpacity(0.6)),
            filled: true,
            fillColor: (isDark ? Colors.white : const Color(0xFFFFFFFF)).withOpacity(isDark ? 0.06 : 0.55),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(isDark ? 0.12 : 0.5), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(isDark ? 0.12 : 0.5), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: const Color(0xFF4F7DF3).withOpacity(0.6), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<MapEntry<String, String>> items;
  final bool isDark;
  final ValueChanged<String> onChanged;

  const _GlassDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1D2733);
    final textSecondary = isDark ? Colors.white60 : const Color(0xFF8A9AAC);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: textPrimary.withOpacity(0.85))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : const Color(0xFFFFFFFF)).withOpacity(isDark ? 0.06 : 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(isDark ? 0.12 : 0.5), width: 1.5),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: textSecondary, size: 20),
              dropdownColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8FBFF),
              style: GoogleFonts.inter(fontSize: 14, color: textPrimary, fontWeight: FontWeight.w500),
              items: items.map((e) {
                return DropdownMenuItem<String>(
                  value: e.key,
                  child: Text(e.value, style: GoogleFonts.inter(fontSize: 14, color: textPrimary)),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tintColor;
  final bool isDark;
  final bool isLoading;
  final VoidCallback? onTap;

  const _GlassActionButton({
    required this.label,
    required this.icon,
    required this.tintColor,
    required this.isDark,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF1D2733);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tintColor.withOpacity(isDark ? 0.35 : 0.22),
                tintColor.withOpacity(isDark ? 0.22 : 0.12),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(isDark ? 0.25 : 0.55), width: 1.5),
            boxShadow: [
              BoxShadow(color: tintColor.withOpacity(isDark ? 0.25 : 0.15), blurRadius: 18, offset: const Offset(0, 5)),
            ],
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: textColor),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: textColor),
                      const SizedBox(width: 8),
                      Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color tintColor;
  final bool isDark;
  final VoidCallback? onTap;

  const _IconBtn({required this.icon, required this.tintColor, required this.isDark, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: tintColor.withOpacity(isDark ? 0.2 : 0.1),
            border: Border.all(color: Colors.white.withOpacity(isDark ? 0.2 : 0.5), width: 1),
          ),
          child: Center(child: Icon(icon, size: 18, color: tintColor)),
        ),
      ),
    );
  }
}
