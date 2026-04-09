import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/core/constants/app_text_styles.dart';
import 'package:sheserved/services/service_locator.dart';
import 'package:sheserved/features/donation/data/repositories/beneficiary_repository.dart';
import 'package:sheserved/features/donation/data/repositories/fee_repository.dart';
import 'package:sheserved/features/donation/data/repositories/donation_repository.dart';
import 'package:sheserved/features/donation/models/donation_models.dart';
import 'package:sheserved/features/donation/models/fee_models.dart';
import 'package:sheserved/features/donation/services/fee_calculator_service.dart';
import 'package:sheserved/features/admin/models/profession.dart';

class CategoryEscrowConfigDialog extends StatefulWidget {
  final DonationCategory category;
  final VoidCallback onSaved;

  const CategoryEscrowConfigDialog({
    super.key,
    required this.category,
    required this.onSaved,
  });

  @override
  State<CategoryEscrowConfigDialog> createState() => _CategoryEscrowConfigDialogState();
}

class _CategoryEscrowConfigDialogState extends State<CategoryEscrowConfigDialog> {
  late BeneficiaryRepository _beneficiaryRepo;
  late FeeRepository _feeRepo;
  late FeeCalculatorService _feeCalc;
  late DonationRepository _donationRepo;

  bool _isLoading = true;
  bool _isSaving = false;

  List<BeneficiaryOrganization> _beneficiaries = [];
  String? _selectedBeneficiaryId;

  late TextEditingController _pauseGraceCtrl;
  late TextEditingController _transferGraceCtrl;
  late TextEditingController _cancelGraceCtrl;
  late TextEditingController _creditExpiryCtrl;

  late TextEditingController _previewNetCtrl;
  double _previewGross = 0;
  FeeBreakdown? _previewBreakdown;

  late TextEditingController _sheservedAccountCtrl;

  @override
  void initState() {
    super.initState();
    _beneficiaryRepo = ServiceLocator.instance.beneficiaryRepository;
    _feeRepo = ServiceLocator.instance.feeRepository;
    _feeCalc = FeeCalculatorService(_feeRepo);
    _donationRepo = ServiceLocator.instance.donationRepository;

    _selectedBeneficiaryId = widget.category.beneficiaryOrgId;
    _pauseGraceCtrl = TextEditingController(text: widget.category.pauseGracePeriodHours.toString());
    _transferGraceCtrl = TextEditingController(text: widget.category.transferFailureGraceHours.toString());
    _cancelGraceCtrl = TextEditingController(text: widget.category.cancellationGraceHours.toString());
    
    // Default 90 days if not set
    // Note: Assuming Category model has it, but for safety will fallback to '90' if not present in the model struct yet.
    _creditExpiryCtrl = TextEditingController(text: '90');

    _sheservedAccountCtrl = TextEditingController(text: widget.category.sheservedAccountId ?? '');

    _previewNetCtrl = TextEditingController(text: '10000'); // default 10,000

    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final allBeneficiaries = await _beneficiaryRepo.getAll(activeOnly: true);
      final allProfessions = await ServiceLocator.instance.professionRepository.getAllProfessions();
      
      // กรองเฉพาะองค์กรที่อยู่ใน flow การอนุมัติของหมวดหมู่นี้ 
      // โดย approverProfessionIds เก็บเป็นรหัสของ user_category (เช่น "provider", "local_leader")
      // จึงต้องหาว่า profession_id ขององค์กรนั้นอยู่ใน category ใด
      final filteredBeneficiaries = allBeneficiaries.where((b) {
        if (b.professionId == null) return false;
        
        final profList = allProfessions.where((p) => p.id == b.professionId);
        if (profList.isEmpty) return false;
        
        final targetProf = profList.first;
        return widget.category.approverProfessionIds.contains(targetProf.category.value);
      }).toList();

      await _feeCalc.loadForCategory(widget.category.id);
      
      if (mounted) {
        setState(() {
          _beneficiaries = filteredBeneficiaries;
          _isLoading = false;
        });
        _updatePreview();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  void _updatePreview() {
    final net = double.tryParse(_previewNetCtrl.text) ?? 0;
    if (net <= 0) {
      setState(() {
        _previewGross = 0;
        _previewBreakdown = null;
      });
      return;
    }

    final gross = _feeCalc.grossFromNet(net);
    setState(() {
      _previewGross = gross;
      if (gross.isInfinite || gross.isNaN) {
         _previewBreakdown = null;
      } else {
         _previewBreakdown = _feeCalc.breakdown(grossAmount: gross);
      }
    });
  }

  Future<void> _saveGracePeriods() async {
    setState(() => _isSaving = true);
    try {
      final pauseGrace = int.tryParse(_pauseGraceCtrl.text) ?? 72;
      final transferGrace = int.tryParse(_transferGraceCtrl.text) ?? 48;
      final cancelGrace = int.tryParse(_cancelGraceCtrl.text) ?? 24;
      final creditExpiry = int.tryParse(_creditExpiryCtrl.text) ?? 90;
      final sheservedAccount = _sheservedAccountCtrl.text.trim();

      await _donationRepo.updateCategory(widget.category.id, {
        'beneficiary_org_id': _selectedBeneficiaryId,
        'sheserved_account_id': sheservedAccount.isEmpty ? null : sheservedAccount,
        'pause_grace_period_hours': pauseGrace,
        'transfer_failure_grace_hours': transferGrace,
        'cancellation_grace_hours': cancelGrace,
        'refund_credit_expiry_days': creditExpiry,
      });

      if (mounted) {
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('บันทึกข้อมูลเรียบร้อยแล้ว'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('บันทึกไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AlertDialog(
        content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600, // กว้างหน่อย
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('ตั้งค่า Escrow & ค่าธรรมเนียม', style: AppTextStyles.heading3),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text('หมวดหมู่: ${widget.category.name}', style: AppTextStyles.bodyMedium.copyWith(color: Colors.grey)),
            const Divider(height: 32),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ส่วนที่ 1: Beneficiary
                    _buildSectionTitle('1. Beneficiary Organization', Icons.business),
                    const Text('เลือกองค์กรที่จะเป็น Escrow Account รองรับเงินบริจาคของหมวดหมู่นี้', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      value: _selectedBeneficiaryId,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('ไม่ระบุ (ใช้ตาม Global Default ถ้ามี)')),
                        ..._beneficiaries.map((b) => DropdownMenuItem(
                          value: b.id,
                          child: Text('${b.name} ${b.isGlobalDefault ? "(Global Default)" : ""}'),
                        )),
                      ],
                      onChanged: (val) => setState(() => _selectedBeneficiaryId = val),
                    ),
                    if (_beneficiaries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          '⚠️ ไม่มีองค์กรที่ตรงกับ Flow การอนุมัติ (คุณต้องไปที่เมนู "ผู้รับมรดก/Escrow" เพื่อกำหนด Profession ให้ตรงกับ Flow อนุมัติของหมวดหมู่นี้)',
                          style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                        ),
                      ),
                    const SizedBox(height: 24),

                    // ส่วนที่ 2: Grace Period
                    _buildSectionTitle('2. Grace Periods (ชั่วโมง)', Icons.timer),
                    const Text('ระยะเวลาผ่อนผันก่อนที่ระบบจะข้ามขั้นตอนอัตโนมัติ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _pauseGraceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'ถูก Pause (ชม.)', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _transferGraceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'โอนไม่ผ่าน (ชม.)', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _cancelGraceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'ยกเลิกคำร้อง (ชม.)', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _creditExpiryCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'วันหมดอายุเครดิตเงินคืน (วัน)', border: OutlineInputBorder()),
                            style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text('หากเครดิตหมดอายุ หรือผู้บริจาคเลือกไม่รับเงินคืน ยอดจะตกเป็นของ Beneficiary อัตโนมัติ', style: TextStyle(fontSize: 11, color: Colors.blue)),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveGracePeriods,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                        child: _isSaving 
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('บันทึก Escrow & Grace Period'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),

                    // ส่วนที่ 3: Platform Fees
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionTitle('3. Platform Fees (ค่าธรรมเนียม)', Icons.payments),
                        ElevatedButton.icon(
                          onPressed: () => _showFeeItemEditor(null),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('เพิ่มค่าบริการ'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                        ),
                      ],
                    ),
                    const Text('เพิ่มรายการที่แพลตฟอร์มจะหักเป็นค่าบริการ รวมถึงภาษีต่างๆ ณ วันที่เงินเข้า Escrow', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _sheservedAccountCtrl,
                      decoration: const InputDecoration(
                        labelText: 'บัญชีรับเงินของแอป (Sheserved Revenue Account ID / PromptPay)',
                        border: OutlineInputBorder(),
                        hintText: 'หากมีความต้องการให้แยกโอน Platform Fee',
                      ),
                    ),
                    const SizedBox(height: 16),

                    _buildFeeItemsList(),

                    const SizedBox(height: 24),
                    
                    // Live Preview แบบ Glassmorphism
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.visibility, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Text('Live Preview: การคำนวณ Gross Target', style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _previewNetCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'ยอดสุทธิที่ Reporter ต้องการ (Net Goal)',
                                    border: OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                    suffixText: '฿',
                                  ),
                                  onChanged: (_) => _updatePreview(),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 3,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('ยอดรวมที่ต้องระดมทุน (Gross Target):', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                      if (_previewGross.isNaN || _previewGross.isInfinite)
                                        const Text('ไม่สามารถคำนวณได้ (ค่า Rate >= 100%)', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
                                      else 
                                        Text('฿${_previewGross.toStringAsFixed(2)}', style: AppTextStyles.heading2.copyWith(color: AppColors.primary)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_previewBreakdown != null && _previewBreakdown!.items.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text('รายละเอียดการจำแนกค่าธรรมเนียม (Fee Breakdown):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            ..._previewBreakdown!.items.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('- ${e.name} ${e.feeType == FeeType.percentOfGross ? "(${e.rate}%)" : e.feeType == FeeType.fixedBaht ? "(${e.fixedAmount} ฿)" : "(Per Tx)"}', style: const TextStyle(fontSize: 13)),
                                  Text('฿${e.deducted.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, color: Colors.red)),
                                ],
                              ),
                            )),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('คงเหลือสุทธิ (Net Amount):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                Text('฿${_previewBreakdown!.netAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.teal),
        const SizedBox(width: 8),
        Text(title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildFeeItemsList() {
    if (_feeCalc.cachedItems.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
        child: const Text('ยังไม่มีค่าธรรมเนียม', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _feeCalc.cachedItems.length,
      itemBuilder: (context, index) {
        final item = _feeCalc.cachedItems[index];
        final typeStr = item.feeType == FeeType.percentOfGross 
            ? '${item.rate}% ของยอดรวม' 
            : item.feeType == FeeType.fixedBaht 
                ? '${item.amount} ฿ ต่อครั้ง' 
                : '${item.rate}% ต่อ Transaction';
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
          child: ListTile(
            dense: true,
            title: Text(item.name, style: TextStyle(fontWeight: FontWeight.bold, color: item.isActive ? Colors.black : Colors.grey)),
            subtitle: Text(typeStr),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: item.isActive,
                  onChanged: (val) async {
                    await _feeRepo.updateFeeItem(item.id, {'is_active': val});
                    _feeCalc.clearCache();
                    await _loadData();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _showFeeItemEditor(item),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFeeItemEditor(CategoryFeeItem? item) {
    final nameCtrl = TextEditingController(text: item?.name);
    FeeType selectedType = item?.feeType ?? FeeType.percentOfGross;
    final rateCtrl = TextEditingController(text: item?.rate?.toString() ?? '');
    final amountCtrl = TextEditingController(text: item?.amount?.toString() ?? '');
    bool isActive = item?.isActive ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(item == null ? 'เพิ่มค่าบริการ' : 'แก้ไขค่าบริการ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'ชื่อค่าบริการ (เช่น Platform Fee, VAT)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<FeeType>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: 'ประเภทการหักเงิน'),
                  items: FeeType.values.map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t.name),
                  )).toList(),
                  onChanged: (val) => setDialogState(() => selectedType = val!),
                ),
                const SizedBox(height: 12),
                if (selectedType == FeeType.percentOfGross || selectedType == FeeType.percentPerTransaction)
                  TextField(controller: rateCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'อัตราเปอร์เซ็นต์ (%)')),
                if (selectedType == FeeType.fixedBaht)
                  TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'จำนวนเงินคงที่ (บาท)')),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('เปิดใช้งาน'),
                  value: isActive,
                  onChanged: (val) => setDialogState(() => isActive = val),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty) return;
                
                final rate = double.tryParse(rateCtrl.text);
                final amount = double.tryParse(amountCtrl.text);

                final data = {
                  'category_id': widget.category.id,
                  'name': nameCtrl.text,
                  'fee_type': selectedType.name,
                  'rate': rate,
                  'amount': amount,
                  'is_active': isActive,
                };

                try {
                  if (item == null) {
                    await _feeRepo.addFeeItem(data);
                  } else {
                    await _feeRepo.updateFeeItem(item.id, data);
                  }
                  
                  _feeCalc.clearCache(); // ล้าง cache เก่า
                  if (mounted) Navigator.pop(ctx);
                  await _loadData(); // โหลดข้อมูลใหม่
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }
}
