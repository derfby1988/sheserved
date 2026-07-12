import 'package:flutter/material.dart';
import '../../data/services/drug_risk_screening_service.dart';

/// Dialog แสดงผลการตรวจสอบความเสี่ยงยาแบบละเอียด
class PrescriptionRiskDialog extends StatelessWidget {
  final List<DrugRiskScreeningResult> results;
  final VoidCallback? onProceed;
  final VoidCallback? onCancel;
  final VoidCallback? onNavigateToUpload;

  const PrescriptionRiskDialog({
    super.key,
    required this.results,
    this.onProceed,
    this.onCancel,
    this.onNavigateToUpload,
  });

  bool get hasBlocked => results.any((r) => r.isBlocked);
  bool get hasWarnings => results.any((r) => r.isWarning);
  int get blockedCount => results.where((r) => r.isBlocked).length;
  int get warningCount => results.where((r) => r.isWarning).length;

  bool get hasMissingLicense => results.any(
    (r) => r.requiredLicense != null && !r.providerHasLicense,
  );
  List<String> get missingLicenses => results
      .where((r) => r.requiredLicense != null && !r.providerHasLicense)
      .map((r) => r.requiredLicense!)
      .toSet()
      .toList();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _buildTitle(),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSummaryBanner(),
              const SizedBox(height: 16),
              ...results.map((r) => _buildResultCard(r)),
            ],
          ),
        ),
      ),
      actions: [
        if (hasMissingLicense && onNavigateToUpload != null)
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop(false);
              onNavigateToUpload!();
            },
            icon: const Icon(Icons.upload_file),
            label: const Text('อัปโหลดใบอนุญาต'),
          ),
        TextButton(
          onPressed: onCancel ?? () => Navigator.of(context).pop(false),
          child: const Text('ยกเลิก'),
        ),
        if (!hasBlocked)
          ElevatedButton(
            onPressed: onProceed ?? () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: hasWarnings ? Colors.orange : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(hasWarnings ? 'ยืนยัน (มีข้อควรระวัง)' : 'ยืนยันสั่งจ่าย'),
          ),
      ],
    );
  }

  Widget _buildTitle() {
    if (hasBlocked) {
      return Row(
        children: [
          const Icon(Icons.block, color: Colors.red, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'ห้ามสั่งจ่าย ($blockedCount รายการ)',
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      );
    }
    if (hasWarnings) {
      return Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'ตรวจสอบความเสี่ยง ($warningCount รายการ)',
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 28),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'ผ่านการตรวจสอบ',
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBanner() {
    if (hasBlocked) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'พบ $blockedCount รายการที่ห้ามสั่งผ่าน Telemedicine',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red.shade800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasMissingLicense
                  ? 'แพทย์ยังไม่มีใบอนุญาตที่จำเป็น กรุณาอัปโหลดเอกสารก่อนสั่งจ่าย หรือให้ผู้ป่วยมาตรวจที่คลินิกแบบ Face-to-Face'
                  : 'กรุณาลบรายการที่ถูกบล็อกออกจากใบสั่งยา หรือให้ผู้ป่วยมาตรวจที่คลินิกแบบ Face-to-Face',
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ],
        ),
      );
    }
    if (hasWarnings) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'พบ $warningCount รายการที่ต้องระวัง',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'ยาเหล่านี้สามารถสั่งได้ แต่ต้องแจ้งผู้ป่วยถึงความเสี่ยง และติดตามอาการอย่างใกล้ชิด',
              style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'รายการยาทั้งหมดปลอดภัยสำหรับ Telemedicine',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green.shade800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ยาทุกรายการผ่านการตรวจสอบตามกฎหมายและสามารถสั่งจ่ายผ่านระบบได้',
            style: TextStyle(color: Colors.green.shade700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(DrugRiskScreeningResult result) {
    final Color statusColor = result.isBlocked
        ? Colors.red
        : result.isWarning
            ? Colors.orange
            : Colors.green;

    final IconData statusIcon = result.isBlocked
        ? Icons.block
        : result.isWarning
            ? Icons.warning_amber
            : Icons.check_circle;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: ExpansionTile(
        leading: Icon(statusIcon, color: statusColor, size: 28),
        title: Row(
          children: [
            Expanded(
              child: Text(
                result.medicationName,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: result.isBlocked ? Colors.red.shade800 : null,
                ),
              ),
            ),
            if (result.hasOverride) ...[
              const SizedBox(width: 8),
              _buildOverrideBadge(result.overrideScope),
            ],
          ],
        ),
        subtitle: Text(
          result.summary,
          style: TextStyle(
            color: statusColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // รหัส FDA
                if (result.fdaRiskStatus.isNotEmpty) ...[
                  _buildInfoRow(
                    icon: Icons.label,
                    title: 'รหัส FDA',
                    content: '${result.fdaRiskStatus} — ${result.fdaStatusNameTh}',
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(height: 8),
                ],

                // หมวดหมู่ยาอันตรายย่อย
                if (result.dangerousSubCategory != null) ...[
                  _buildInfoRow(
                    icon: Icons.category,
                    title: 'หมวดหมู่ยาอันตราย',
                    content: result.dangerousSubCategoryName ?? result.dangerousSubCategory!,
                    color: Colors.purple.shade700,
                  ),
                  const SizedBox(height: 8),
                ],

                // Custom Risk Level
                if (result.customRiskLevel != null) ...[
                  _buildInfoRow(
                    icon: Icons.trending_up,
                    title: 'ระดับความเสี่ยง (Custom)',
                    content: result.customRiskLevelName ?? result.customRiskLevel!,
                    color: Colors.teal.shade700,
                  ),
                  const SizedBox(height: 8),
                ],

                // สาเหตุที่ถูกบล็อก/เตือน
                if (result.blockReason.isNotEmpty) ...[
                  _buildInfoRow(
                    icon: result.isBlocked ? Icons.block : Icons.info,
                    title: result.isBlocked ? 'สาเหตุที่ห้าม' : 'ข้อควรระวัง',
                    content: result.blockReason,
                    color: statusColor,
                    isHighlight: true,
                  ),
                  const SizedBox(height: 8),
                ],

                // ฐานทางกฎหมาย
                _buildInfoRow(
                  icon: Icons.gavel,
                  title: 'ฐานทางกฎหมาย',
                  content: result.legalBasis,
                  color: Colors.indigo.shade700,
                ),
                const SizedBox(height: 8),

                // เงื่อนไขการสั่งจ่าย
                _buildInfoRow(
                  icon: Icons.assignment,
                  title: 'เงื่อนไขการสั่งจ่าย',
                  content: result.prescriptionCondition,
                  color: Colors.deepOrange.shade700,
                ),
                const SizedBox(height: 8),

                // สิทธิ์จ่ายยาของเภสัชกร
                _buildInfoRow(
                  icon: Icons.local_pharmacy,
                  title: 'สิทธิ์จ่ายยาของเภสัชกร',
                  content: result.pharmacistDispensingRule,
                  color: Colors.cyan.shade700,
                ),
                const SizedBox(height: 8),

                // ใบอนุญาตที่ต้องมี
                if (result.requiredLicense != null) ...[
                  _buildInfoRow(
                    icon: result.providerHasLicense ? Icons.verified : Icons.cancel,
                    title: 'ใบอนุญาตที่ต้องมี',
                    content: result.providerHasLicense
                        ? 'แพทย์มีใบอนุญาตที่จำเป็น (${result.requiredLicense})'
                        : 'แพทย์ไม่มีใบอนุญาตที่จำเป็น: ${result.requiredLicense}',
                    color: result.providerHasLicense ? Colors.green.shade700 : Colors.red.shade700,
                    isHighlight: !result.providerHasLicense,
                  ),
                  const SizedBox(height: 8),
                ],

                // หมายเหตุเพิ่มเติม
                if (result.additionalNotes.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'หมายเหตุ:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...result.additionalNotes.map((note) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('• ', style: TextStyle(color: Colors.grey.shade600)),
                              Expanded(
                                child: Text(
                                  note,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String content,
    required Color color,
    bool isHighlight = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isHighlight ? color.withOpacity(0.1) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: isHighlight ? Border.all(color: color.withOpacity(0.3)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade800,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverrideBadge(String? scope) {
    final isOrg = scope == 'organization';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (isOrg ? Colors.teal : Colors.purple).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isOrg ? Colors.teal : Colors.purple, width: 0.5),
      ),
      child: Text(
        isOrg ? 'Override องค์กร' : 'Override ส่วนตัว',
        style: TextStyle(
          fontSize: 8,
          color: isOrg ? Colors.teal : Colors.purple,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
