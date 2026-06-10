import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../features/erp/presentation/providers/organization_settings_provider.dart';
import '../features/admin/models/organization_settings.dart';

/// Organization Settings Page
/// ฟอร์มตั้งค่าองค์กร: ชื่อ, โลโก้, ที่อยู่, ภาษา, สกุลเงิน, สาขา
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

  final List<TextEditingController> _branchNameControllers = [];
  final List<TextEditingController> _branchCodeControllers = [];
  final List<TextEditingController> _branchPhoneControllers = [];
  final List<TextEditingController> _branchAddressControllers = [];

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

    _branchNameControllers.clear();
    _branchCodeControllers.clear();
    _branchPhoneControllers.clear();
    _branchAddressControllers.clear();
    for (final branch in settings.branches) {
      _branchNameControllers.add(TextEditingController(text: branch.branchName));
      _branchCodeControllers.add(TextEditingController(text: branch.branchCode));
      _branchPhoneControllers.add(TextEditingController(text: branch.phone ?? ''));
      _branchAddressControllers.add(TextEditingController(text: branch.address ?? ''));
    }
    setState(() {});
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
    for (final c in _branchNameControllers) c.dispose();
    for (final c in _branchCodeControllers) c.dispose();
    for (final c in _branchPhoneControllers) c.dispose();
    for (final c in _branchAddressControllers) c.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกข้อมูลองค์กรสำเร็จ'), backgroundColor: Colors.green),
      );
    } else if (mounted) {
      final err = ref.read(organizationSettingsProvider).errorMessage ?? 'บันทึกไม่สำเร็จ';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orgState = ref.watch(organizationSettingsProvider);

    if (orgState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section: Organization Info
                    _SectionTitle(title: 'ข้อมูลองค์กร', icon: Icons.business),
                    const SizedBox(height: 12),
                    _TextField(controller: _nameController, label: 'ชื่อองค์กร *', validator: (v) => v == null || v.trim().isEmpty ? 'กรุณากรอกชื่อองค์กร' : null),
                    _TextField(controller: _nameEnController, label: 'ชื่อภาษาอังกฤษ'),
                    _TextField(controller: _logoUrlController, label: 'URL โลโก้'),
                    _TextField(controller: _taxIdController, label: 'เลขประจำตัวผู้เสียภาษี', keyboardType: TextInputType.number),
                    _TextField(controller: _phoneController, label: 'เบอร์โทรศัพท์'),
                    _TextField(controller: _emailController, label: 'อีเมล', keyboardType: TextInputType.emailAddress),
                    _TextField(controller: _addressController, label: 'ที่อยู่', maxLines: 3),
                    const SizedBox(height: 16),

                    // Section: Preferences
                    _SectionTitle(title: 'การตั้งค่าทั่วไป', icon: Icons.settings),
                    const SizedBox(height: 12),
                    _DropdownRow(
                      label: 'สกุลเงิน',
                      value: _currency,
                      items: const [
                        DropdownMenuItem(value: 'THB', child: Text('THB — บาท')),
                        DropdownMenuItem(value: 'USD', child: Text('USD — ดอลลาร์')),
                      ],
                      onChanged: (v) => setState(() => _currency = v!),
                    ),
                    _DropdownRow(
                      label: 'ภาษา',
                      value: _language,
                      items: const [
                        DropdownMenuItem(value: 'th', child: Text('ไทย')),
                        DropdownMenuItem(value: 'en', child: Text('English')),
                      ],
                      onChanged: (v) => setState(() => _language = v!),
                    ),
                    _DropdownRow(
                      label: 'เขตเวลา',
                      value: _timezone,
                      items: const [
                        DropdownMenuItem(value: 'Asia/Bangkok', child: Text('Asia/Bangkok')),
                        DropdownMenuItem(value: 'UTC', child: Text('UTC')),
                      ],
                      onChanged: (v) => setState(() => _timezone = v!),
                    ),
                    _DropdownRow(
                      label: 'โหมดจัดเก็บข้อมูล',
                      value: _storageMode,
                      items: const [
                        DropdownMenuItem(value: 'cloud', child: Text('Cloud (Supabase)')),
                        DropdownMenuItem(value: 'self_host', child: Text('Self-host')),
                      ],
                      onChanged: (v) => setState(() => _storageMode = v!),
                    ),
                    if (_storageMode == 'self_host')
                      _TextField(controller: _selfHostApiUrlController, label: 'URL API Self-host'),
                    const SizedBox(height: 24),

                    // Section: Branches
                    _SectionTitle(title: 'สาขา', icon: Icons.location_on),
                    const SizedBox(height: 12),
                    _BranchesList(
                      branches: orgState.settings?.branches ?? [],
                      onAddBranch: () async {
                        final notifier = ref.read(organizationSettingsProvider.notifier);
                        final settings = orgState.settings;
                        if (settings == null) return;
                        final newBranch = await notifier.saveBranch(
                          branchCode: 'BR${(settings.branches.length + 1).toString().padLeft(2, '0')}',
                          branchName: 'สาขาใหม่',
                          isMainBranch: settings.branches.isEmpty,
                        );
                        if (newBranch != null && mounted) {
                          _syncFormFromState();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('เพิ่มสาขาสำเร็จ'), backgroundColor: Colors.green),
                          );
                        }
                      },
                      onDeleteBranch: (branchId) async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('ยืนยันการลบ'),
                            content: const Text('ต้องการลบสาขานี้หรือไม่?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await ref.read(organizationSettingsProvider.notifier).deleteBranch(branchId);
                          if (mounted) _syncFormFromState();
                        }
                      },
                    ),
                    const SizedBox(height: 32),
                    // Save button (moved from AppBar to avoid duplicate Scaffold)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: orgState.isSaving ? null : _save,
                        icon: orgState.isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save),
                        label: Text(orgState.isSaving ? 'กำลังบันทึก...' : 'บันทึก', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0066FF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
  }
}

// ========================
// UI Components
// ========================

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF0066FF)),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E)),
        ),
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int? maxLines;

  const _TextField({
    required this.controller,
    required this.label,
    this.validator,
    this.keyboardType,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines ?? 1,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final String label;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: value,
                  items: items,
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchesList extends StatelessWidget {
  final List<OrganizationBranch> branches;
  final VoidCallback onAddBranch;
  final ValueChanged<String> onDeleteBranch;

  const _BranchesList({
    required this.branches,
    required this.onAddBranch,
    required this.onDeleteBranch,
  });

  @override
  Widget build(BuildContext context) {
    if (branches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Text('ยังไม่มีสาขา', style: GoogleFonts.inter(color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onAddBranch,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('เพิ่มสาขาหลัก'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        ...branches.map((branch) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        branch.branchName,
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${branch.branchCode}${branch.isMainBranch ? ' (สาขาหลัก)' : ''}',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      if (branch.phone != null && branch.phone!.isNotEmpty)
                        Text(branch.phone!, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                if (!branch.isMainBranch)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    onPressed: () => onDeleteBranch(branch.id),
                  ),
              ],
            ),
          );
        }).toList(),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAddBranch,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('เพิ่มสาขา'),
          ),
        ),
      ],
    );
  }
}
