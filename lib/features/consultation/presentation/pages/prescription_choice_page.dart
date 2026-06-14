import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../services/auth_service.dart';
import '../../data/repositories/prescription_workflow_repository.dart';

class PrescriptionChoicePage extends StatefulWidget {
  final String consultationId;
  final String patientId;
  final String? prescriptionId;

  const PrescriptionChoicePage({
    super.key,
    required this.consultationId,
    required this.patientId,
    this.prescriptionId,
  });

  @override
  State<PrescriptionChoicePage> createState() => _PrescriptionChoicePageState();
}

class _PrescriptionChoicePageState extends State<PrescriptionChoicePage> {
  final PrescriptionWorkflowRepository _repository =
      PrescriptionWorkflowRepository(Supabase.instance.client);

  bool _isLoading = true;
  bool _isSubmitting = false;
  Map<String, dynamic>? _prescription;
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _selectionHistory = [];
  String? _selectedTemplateId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final prescription = widget.prescriptionId != null
          ? await _repository.getPrescriptionById(widget.prescriptionId!)
          : null;

      final providerId = prescription?['provider_id'] as String?;
      final templates = providerId != null && providerId.isNotEmpty
          ? await _repository.getProviderTemplates(providerId)
          : await _repository.getSharedTemplatesForConsultation(
              consultationId: widget.consultationId,
            );

      final history = await _repository.getSelectionHistory(
        consultationId: widget.consultationId,
        patientId: widget.patientId,
      );

      if (!mounted) return;
      setState(() {
        _prescription = prescription;
        _templates = templates;
        _selectionHistory = history;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[PrescriptionChoicePage] _loadData error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _chooseTemplate(Map<String, dynamic> template) async {
    final patientId = AuthService.instance.currentUser?.id;
    if (patientId == null) return;

    final providerId = template['provider_id'] as String? ?? '';
    final templateId = template['id'] as String? ?? '';
    final templateName = template['template_name'] as String? ?? 'ไม่ระบุชื่อ';
    final selectedItems = (template['medications_snapshot'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        <Map<String, dynamic>>[];

    setState(() => _isSubmitting = true);
    try {
      await _repository.recordPatientSelection(
        consultationId: widget.consultationId,
        patientId: patientId,
        providerId: providerId,
        templateId: templateId,
        templateName: templateName,
        selectedItems: selectedItems,
        prescriptionId: widget.prescriptionId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เลือกชุดยา "$templateName" แล้ว')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เลือกชุดยาไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildCurrentPrescriptionCard() {
    final rx = _prescription;
    if (rx == null) {
      return const SizedBox.shrink();
    }
    final medications = (rx['medications'] as List? ?? []);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.medication, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'ใบสั่งยาปัจจุบัน',
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'สถานะ: ${rx['status'] ?? '-'}',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 8),
            ...medications.map((med) {
              final m = Map<String, dynamic>.from(med as Map);
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '- ${m['name'] ?? ''} ${m['dose'] ?? ''}',
                  style: AppTextStyles.bodySmall,
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateCard(Map<String, dynamic> template) {
    final isSelected = _selectedTemplateId == template['id']?.toString();
    final items = (template['items'] as List?) ?? [];
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(color: AppColors.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _selectedTemplateId = template['id']?.toString()),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bookmark_outline, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      template['template_name']?.toString() ?? 'ไม่ระบุชื่อ',
                      style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${items.length} รายการยา',
                style: AppTextStyles.bodyMedium.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              ...items.take(3).map((item) {
                final i = Map<String, dynamic>.from(item as Map);
                return Text(
                  '- ${i['item_name'] ?? ''} ${i['dosage'] ?? ''}',
                  style: AppTextStyles.bodySmall,
                );
              }).toList(),
              if (items.length > 3)
                Text(
                  '+ ${items.length - 3} รายการอื่น',
                  style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
                ),
              const SizedBox(height: 12),
              if (isSelected)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : () => _chooseTemplate(template),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('เลือกชุดยานี้'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionHistoryCard(Map<String, dynamic> history) {
    final items = (history['selected_items'] as List?) ?? [];
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    history['template_name']?.toString() ?? 'ไม่ระบุชื่อ',
                    style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'เลือกเมื่อ: ${history['selected_at']?.toString() ?? '-'}',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            ...items.take(2).map((item) {
              final i = Map<String, dynamic>.from(item as Map);
              return Text(
                '- ${i['name'] ?? i['item_name'] ?? ''}',
                style: AppTextStyles.bodySmall,
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        title: const Text('เลือกชุดยา / ประวัติ'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_prescription != null) ...[
                    _buildCurrentPrescriptionCard(),
                    const SizedBox(height: 24),
                  ],
                  if (_templates.isNotEmpty) ...[
                    Text(
                      'ชุดยาที่แพทย์เสนอ',
                      style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    ..._templates.map((t) => _buildTemplateCard(t)).toList(),
                    const SizedBox(height: 24),
                  ],
                  if (_selectionHistory.isNotEmpty) ...[
                    Text(
                      'ประวัติการเลือกของคุณ',
                      style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    ..._selectionHistory.map((h) => _buildSelectionHistoryCard(h)).toList(),
                  ],
                  if (_prescription == null && _templates.isEmpty && _selectionHistory.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          'ยังไม่มีชุดยาหรือใบสั่งยาในคำปรึกษานี้',
                          style: AppTextStyles.bodyMedium.copyWith(color: Colors.grey),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
