import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/core/constants/app_text_styles.dart';
import 'package:sheserved/services/service_locator.dart';
import '../../../data/repositories/beneficiary_repository.dart';
import '../../../../admin/data/repositories/profession_repository.dart';
import '../../../../admin/models/profession.dart';

class BeneficiaryAdminPanel extends StatefulWidget {
  final int initialTabIndex; // เพิ่มเพื่อรองรับการกระโดดมาที่แท็บ "รอตรวจสอบ"
  const BeneficiaryAdminPanel({super.key, this.initialTabIndex = 0});

  @override
  State<BeneficiaryAdminPanel> createState() => _BeneficiaryAdminPanelState();
}

class _BeneficiaryAdminPanelState extends State<BeneficiaryAdminPanel> {
  late BeneficiaryRepository _repository;
  bool _isLoading = true;
  List<BeneficiaryOrganization> _organizations = [];
  List<Profession> _professions = [];

  @override
  void initState() {
    super.initState();
    _repository = ServiceLocator.instance.beneficiaryRepository;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final orgs = await _repository.getAll(activeOnly: false);
      final profs = await ServiceLocator.instance.professionRepository.getAllProfessions();
      if (mounted) {
        setState(() {
          _organizations = orgs;
          _professions = profs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('โหลดข้อมูลล้มเหลว: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddEditDialog([BeneficiaryOrganization? org]) {
    final nameCtrl = TextEditingController(text: org?.name ?? '');
    final regNoCtrl = TextEditingController(text: org?.registrationNo ?? '');
    final bankNameCtrl = TextEditingController(text: org?.bankName ?? '');
    final bankAccCtrl = TextEditingController(text: org?.bankAccount ?? '');
    final bankAccNameCtrl = TextEditingController(text: org?.bankAccountName ?? '');
    final contactEmailCtrl = TextEditingController(text: org?.contactEmail ?? '');

    bool isVerified = org?.isVerified ?? false;
    bool isActive = org?.isActive ?? false;
    bool isGlobalDefault = org?.isGlobalDefault ?? false;
    bool isSaving = false;
    String? selectedProfessionId = org?.professionId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(org == null ? Icons.add_business : Icons.edit_document, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(org == null ? 'เพิ่มหน่วยงานรับมรดก' : 'แก้ไขหน่วยงาน', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'ชื่อหน่วยงาน / มูลนิธิ (บังคับ)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: regNoCtrl,
                    decoration: const InputDecoration(labelText: 'เลขทะเบียนนิติบุคคล', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: selectedProfessionId,
                    decoration: const InputDecoration(labelText: 'เชื่อมโยงกลุ่มผู้อนุมัติ (Profession)', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('ไม่ระบุ')),
                      ..._professions.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))),
                    ],
                    onChanged: (val) => setDialogState(() => selectedProfessionId = val),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const Align(alignment: Alignment.centerLeft, child: Text('ข้อมูลบัญชีธนาคาร', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: bankNameCtrl,
                    decoration: const InputDecoration(labelText: 'ธนาคาร', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: bankAccCtrl,
                    decoration: const InputDecoration(labelText: 'เลขที่บัญชี', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: bankAccNameCtrl,
                    decoration: const InputDecoration(labelText: 'ชื่อบัญชี', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: contactEmailCtrl,
                    decoration: const InputDecoration(labelText: 'อีเมลผู้ประสานงาน', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('ผ่านการดตรวจสอบแล้ว (Verified)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: const Text('ตรวจสอบเอกสารแล้ว', style: TextStyle(fontSize: 12)),
                          value: isVerified,
                          activeColor: Colors.green,
                          onChanged: (val) {
                            setDialogState(() {
                              isVerified = val;
                              if (!isVerified) isActive = false; // Constraint: Active requires Verified
                            });
                          },
                        ),
                        SwitchListTile(
                          title: const Text('เปิดใช้งาน (Active)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: const Text('ใช้เป็นตัวเลือกสำหรับ Escrow ได้', style: TextStyle(fontSize: 12)),
                          value: isActive,
                          activeColor: Colors.blue,
                          onChanged: isVerified ? (val) => setDialogState(() => isActive = val) : null,
                        ),
                        SwitchListTile(
                          title: const Text('ใช้เป็น Global Default', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: const Text('เป็นตัวสำรองเมื่อเคสไม่มี Beneficiary', style: TextStyle(fontSize: 12)),
                          value: isGlobalDefault,
                          activeColor: Colors.orange,
                          onChanged: isActive ? (val) => setDialogState(() => isGlobalDefault = val) : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณากรอกชื่อหน่วยงาน')));
                        return;
                      }

                      setDialogState(() => isSaving = true);
                      try {
                        // ดึง user id สำหรับ audit log
                        final userId = ServiceLocator.instance.currentUser?.id ?? '';
                        if (userId.isEmpty) throw Exception('ไม่พบ User Session (Auth Guidelines)');

                        final data = {
                          'name': nameCtrl.text.trim(),
                          'registration_no': regNoCtrl.text.trim().isEmpty ? null : regNoCtrl.text.trim(),
                          'bank_name': bankNameCtrl.text.trim().isEmpty ? null : bankNameCtrl.text.trim(),
                          'bank_account': bankAccCtrl.text.trim().isEmpty ? null : bankAccCtrl.text.trim(),
                          'bank_account_name': bankAccNameCtrl.text.trim().isEmpty ? null : bankAccNameCtrl.text.trim(),
                          'contact_email': contactEmailCtrl.text.trim().isEmpty ? null : contactEmailCtrl.text.trim(),
                          'is_verified': isVerified,
                          'is_active': isActive,
                          'is_global_default': isGlobalDefault,
                          'profession_id': selectedProfessionId,
                        };

                        if (org == null) {
                          await _repository.create(data);
                        } else {
                          await _repository.update(org.id, data);
                        }

                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกข้อมูลเรียบร้อยแล้ว'), backgroundColor: Colors.green));
                        }
                        _loadData();
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกล้มเหลว: $e'), backgroundColor: Colors.red));
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // นับจำนวนเพื่อแสดง badge warning
    final missingBankInfo = _organizations.where((o) => o.bankAccount == null || o.bankAccount!.isEmpty).length;
    final globalDefaultCount = _organizations.where((o) => o.isGlobalDefault && o.isActive).length;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('จัดการหน่วยงานผู้รับมรดก (Beneficiaries Escrow)', style: AppTextStyles.heading2.copyWith(color: AppColors.primary)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showAddEditDialog(),
                icon: const Icon(Icons.add),
                label: const Text('เพิ่มหน่วยงาน'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('หน่วยงานบุคคลที่ 3 ที่ทำหน้าที่เป็น Escrow Account เพื่อความโปร่งใสของระบบ', style: TextStyle(color: Colors.grey, fontSize: 13)),
          
          if (missingBankInfo > 0 || globalDefaultCount == 0)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade300)),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (missingBankInfo > 0) const Text('⚠️ มีบางหน่วยงานที่ยังขาดข้อมูลบัญชีธนาคาร จะไม่สามารถโอนเงินได้', style: TextStyle(color: Colors.deepOrange, fontSize: 12, fontWeight: FontWeight.bold)),
                        if (globalDefaultCount == 0) const Text('⚠️ ยังไม่มีหน่วยงานใดถูกตั้งเป็น Global Default (จำเป็นสำหรับการคืนเงินฉุกเฉิน)', style: TextStyle(color: Colors.deepOrange, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 16),
          Expanded(
            child: DefaultTabController(
              length: 2,
              initialIndex: widget.initialTabIndex,
              child: Column(
                children: [
                  const TabBar(
                    labelColor: AppColors.primary,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: AppColors.primary,
                    tabs: [
                      Tab(text: 'อนุมัติแล้ว (Verified)'),
                      Tab(text: 'รอตรวจสอบ (Pending)'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildOrganizationList(_organizations.where((o) => o.isVerified).toList()),
                        _buildOrganizationList(_organizations.where((o) => !o.isVerified).toList()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrganizationList(List<BeneficiaryOrganization> orgs) {
    if (orgs.isEmpty) {
      return const Center(child: Text('ไม่มีข้อมูลหน่วยงาน', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: orgs.length,
      itemBuilder: (context, index) {
        final org = orgs[index];
                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: org.isActive ? Colors.green.shade100 : Colors.grey.shade200,
                          child: Icon(Icons.account_balance, color: org.isActive ? Colors.green : Colors.grey),
                        ),
                        title: Row(
                          children: [
                            Text(org.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            if (org.isGlobalDefault) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                                child: const Text('Global Default', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              )
                            ]
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('อาชีพ/กลุ่มผู้อนุมัติ: ${_professions.any((p) => p.id == org.professionId) ? _professions.firstWhere((p) => p.id == org.professionId).name : "-"}'),
                            Text('ธนาคาร: ${org.bankName ?? '-'} | บัญชี: ${org.bankAccount ?? '-'}'),
                            Text('สถานะ: ${org.isVerified ? "Verified ✓" : "รอตรวจสอบ"} | ${org.isActive ? "Active" : "Inactive"}', 
                              style: TextStyle(color: org.isActive ? Colors.green : Colors.grey, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showAddEditDialog(org),
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                );
  }
}
