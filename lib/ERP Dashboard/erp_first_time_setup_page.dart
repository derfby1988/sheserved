import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../features/erp/presentation/providers/organization_settings_provider.dart';

/// First-time Setup Wizard for ERP Dashboard
/// Shown when user has profession_id but no organization data exists yet.
class ErpFirstTimeSetupPage extends ConsumerStatefulWidget {
  const ErpFirstTimeSetupPage({super.key});

  @override
  ConsumerState<ErpFirstTimeSetupPage> createState() => _ErpFirstTimeSetupPageState();
}

class _ErpFirstTimeSetupPageState extends ConsumerState<ErpFirstTimeSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nameEnController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _taxIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _branchNameController = TextEditingController();
  String _currency = 'THB';
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _nameEnController.dispose();
    _logoUrlController.dispose();
    _taxIdController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _branchNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final notifier = ref.read(organizationSettingsProvider.notifier);
    final orgState = ref.read(organizationSettingsProvider);
    final professionId = orgState.settings?.professionId;

    try {
      // Save organization settings
      final saved = await notifier.saveOrganization(
        name: _nameController.text.trim(),
        nameEn: _nameEnController.text.trim().isNotEmpty ? _nameEnController.text.trim() : null,
        logoUrl: _logoUrlController.text.trim().isNotEmpty ? _logoUrlController.text.trim() : null,
        taxId: _taxIdController.text.trim().isNotEmpty ? _taxIdController.text.trim() : null,
        phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
        email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
        address: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
        currency: _currency,
      );

      if (saved && professionId != null && _branchNameController.text.trim().isNotEmpty) {
        // Create first branch as main branch
        await notifier.saveBranch(
          branchCode: 'HQ01',
          branchName: _branchNameController.text.trim(),
          isMainBranch: true,
        );
      }

      if (saved && mounted) {
        // Reload organization data
        await notifier.loadOrganization(professionId ?? '');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ตั้งค่าองค์กรสำเร็จ'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกล้มเหลว: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Center(
              child: Column(
                children: [
                  Icon(Icons.business, size: 64, color: Color(0xFF0066FF)),
                  const SizedBox(height: 16),
                  Text(
                    'ยินดีต้อนรับสู่ ERP Dashboard',
                    style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'กรุณาตั้งค่าข้อมูลองค์กรของคุณเพื่อเริ่มต้นใช้งาน',
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Section: Organization Info
            _SectionTitle(title: 'ข้อมูลองค์กร', icon: Icons.business),
            const SizedBox(height: 12),
            _TextField(
              controller: _nameController,
              label: 'ชื่อองค์กร *',
              validator: (v) => v == null || v.trim().isEmpty ? 'กรุณากรอกชื่อองค์กร' : null,
            ),
            _TextField(controller: _nameEnController, label: 'ชื่อภาษาอังกฤษ'),
            _TextField(controller: _logoUrlController, label: 'URL โลโก้ (ถ้ามี)'),
            _TextField(controller: _taxIdController, label: 'เลขประจำตัวผู้เสียภาษี', keyboardType: TextInputType.number),
            _TextField(controller: _phoneController, label: 'เบอร์โทรศัพท์'),
            _TextField(controller: _emailController, label: 'อีเมล', keyboardType: TextInputType.emailAddress),
            _TextField(controller: _addressController, label: 'ที่อยู่', maxLines: 3),
            const SizedBox(height: 16),

            // Section: First Branch
            _SectionTitle(title: 'สาขาหลัก (HQ)', icon: Icons.location_on),
            const SizedBox(height: 12),
            _TextField(
              controller: _branchNameController,
              label: 'ชื่อสาขาหลัก *',
              validator: (v) => v == null || v.trim().isEmpty ? 'กรุณากรอกชื่อสาขา' : null,
            ),
            const SizedBox(height: 8),
            Text(
              'สาขานี้จะถูกตั้งเป็นสาขาหลัก (HQ) และสาขาเริ่มต้นสำหรับรายงาน',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),

            // Currency
            _SectionTitle(title: 'สกุลเงิน', icon: Icons.attach_money),
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
            const SizedBox(height: 32),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'กำลังบันทึก...' : 'บันทึกและเริ่มใช้งาน', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
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
        Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
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
  const _TextField({required this.controller, required this.label, this.validator, this.keyboardType, this.maxLines});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType ?? TextInputType.text,
        maxLines: maxLines ?? 1,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(fontSize: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final String label;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final void Function(String?) onChanged;
  const _DropdownRow({required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label, style: GoogleFonts.inter(fontSize: 14))),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              value: value,
              items: items,
              onChanged: onChanged,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
