import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

/// Owner onboarding sheet: registers a venue owner application.
///
/// Returns `({String legalName, String? businessName, String contact})`
/// when submitted — the caller invokes `submit_venue_owner_application`.
class CourtOwnerRegisterSheet {
  static Future<({String legalName, String? businessName, String contact})?>
      show(BuildContext context) {
    return showModalBottomSheet<
        ({String legalName, String? businessName, String contact})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => const _CourtOwnerRegisterSheetBody(),
    );
  }
}

class _CourtOwnerRegisterSheetBody extends StatefulWidget {
  const _CourtOwnerRegisterSheetBody();

  @override
  State<_CourtOwnerRegisterSheetBody> createState() =>
      _CourtOwnerRegisterSheetBodyState();
}

class _CourtOwnerRegisterSheetBodyState
    extends State<_CourtOwnerRegisterSheetBody> {
  final _legalName = TextEditingController();
  final _businessName = TextEditingController();
  final _contact = TextEditingController();

  @override
  void dispose() {
    _legalName.dispose();
    _businessName.dispose();
    _contact.dispose();
    super.dispose();
  }

  bool get _valid =>
      _legalName.text.trim().isNotEmpty && _contact.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'ลงทะเบียนเจ้าของสนาม',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'ส่งคำขอเป็นเจ้าของสนาม ทีมงานจะตรวจสอบและอนุมัติภายใน 1–3 วันทำการ',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _legalName,
                decoration: const InputDecoration(
                  labelText: 'ชื่อผู้ติดต่อ/เจ้าของกิจการ *',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _businessName,
                decoration: const InputDecoration(
                  labelText: 'ชื่อธุรกิจ/สถานที่',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contact,
                decoration: const InputDecoration(
                  labelText: 'เบอร์โทรหรืออีเมล *',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _valid
                      ? () => Navigator.pop(context, (
                          legalName: _legalName.text.trim(),
                          businessName: _businessName.text.trim().isEmpty
                              ? null
                              : _businessName.text.trim(),
                          contact: _contact.text.trim(),
                        ))
                      : null,
                  child: const Text('ส่งคำขอ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
