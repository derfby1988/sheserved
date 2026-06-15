import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../features/chat/data/models/chat_models.dart';
import '../../../../features/pharmacy/data/services/drug_risk_screening_service.dart';
import '../../../../features/pharmacy/presentation/widgets/prescription_risk_dialog.dart';
import '../../../../features/pharmacy/data/models/medication_models.dart';
import '../../data/repositories/prescription_workflow_repository.dart';

class PrescriptionSection {
  final String id;
  final String label;

  PrescriptionSection({required this.id, required this.label});
}

class MedicationItem {
  String name;
  String dose;
  String frequency;
  String duration;
  String notes;
  final TextEditingController nameController;
  final TextEditingController doseController;
  final TextEditingController frequencyController;
  final TextEditingController durationController;
  final TextEditingController notesController;
  final FocusNode focusNode;

  MedicationItem({
    this.name = '',
    this.dose = '',
    this.frequency = '',
    this.duration = '',
    this.notes = '',
  })  : nameController = TextEditingController(text: name),
        doseController = TextEditingController(text: dose),
        frequencyController = TextEditingController(text: frequency),
        durationController = TextEditingController(text: duration),
        notesController = TextEditingController(text: notes),
        focusNode = FocusNode();

  void dispose() {
    nameController.dispose();
    doseController.dispose();
    frequencyController.dispose();
    durationController.dispose();
    notesController.dispose();
    focusNode.dispose();
  }
}

class _MedicationCardWidget extends StatefulWidget {
  final MedicationItem item;
  final bool showDelete;
  final VoidCallback onDelete;
  final VoidCallback? onChanged;

  const _MedicationCardWidget({
    required this.item,
    required this.showDelete,
    required this.onDelete,
    this.onChanged,
    Key? key,
  }) : super(key: key);

  @override
  State<_MedicationCardWidget> createState() => _MedicationCardWidgetState();
}

class _MedicationCardWidgetState extends State<_MedicationCardWidget> {
  List<MedicationModel> _results = [];
  bool _loading = false;
  Timer? _timer;
  int _token = 0;
  bool _ignoreNextChange = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      if (mounted) setState(() { _results = []; _loading = false; });
      return;
    }
    final myToken = ++_token;
    if (mounted) setState(() => _loading = true);
    try {
      final results = await ServiceLocator.instance.pharmacyRepository.getMedications(
        searchQuery: query.trim(),
        page: 1,
        pageSize: 10,
      );
      if (mounted && _token == myToken) {
        setState(() { _results = results; _loading = false; });
      }
    } catch (e) {
      debugPrint('[MedicationCard] search error: $e');
      if (mounted && _token == myToken) setState(() => _loading = false);
    }
  }

  void _select(MedicationModel model) {
    _timer?.cancel();
    _token++;
    _ignoreNextChange = true;
    final item = widget.item;
    item.name = model.tradeName;
    item.dose = model.strength ?? '';
    FocusScope.of(context).unfocus();
    item.nameController.text = model.tradeName;
    item.doseController.text = model.strength ?? '';
    widget.onChanged?.call();
    debugPrint('[MedicationCard] selected: name="${model.tradeName}" strength="${model.strength}"');
    if (mounted) {
      setState(() {
        _results = [];
        _loading = false;
      });
    }
    Future.microtask(() => _ignoreNextChange = false);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: item.nameController,
                      focusNode: item.focusNode,
                      decoration: InputDecoration(
                        labelText: 'ชื่อยา (Name)',
                        border: InputBorder.none,
                        suffixIcon: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : null,
                      ),
                      onChanged: (val) {
                        item.name = val;
                        widget.onChanged?.call();
                        if (_ignoreNextChange) return;
                        _timer?.cancel();
                        _timer = Timer(
                          const Duration(milliseconds: 400),
                          () => _search(val),
                        );
                      },
                    ),
                    if (_results.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                            itemCount: _results.length,
                            itemBuilder: (ctx, i) {
                              final m = _results[i];
                              final display = (m.genericName != null && m.genericName!.isNotEmpty)
                                  ? '${m.tradeName} (${m.genericName})'
                                  : m.tradeName;
                              return InkWell(
                                onTap: () => _select(m),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(display, style: const TextStyle(fontSize: 13)),
                                      if (m.strength != null && m.strength!.isNotEmpty)
                                        Text(m.strength!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.showDelete)
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: widget.onDelete,
                ),
            ],
          ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: item.doseController,
                  decoration: const InputDecoration(
                    labelText: 'ขนาด (Dose)',
                    border: InputBorder.none,
                  ),
                  onChanged: (val) {
                    item.dose = val;
                    widget.onChanged?.call();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: item.frequencyController,
                  decoration: const InputDecoration(
                    labelText: 'ความถี่ (Freq)',
                    border: InputBorder.none,
                  ),
                  onChanged: (val) {
                    item.frequency = val;
                    widget.onChanged?.call();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: item.durationController,
                  decoration: const InputDecoration(
                    labelText: 'ระยะเวลา',
                    border: InputBorder.none,
                  ),
                  onChanged: (val) {
                    item.duration = val;
                    widget.onChanged?.call();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PrescriptionEditorPage extends StatefulWidget {
  final String consultationId;
  final String patientId;

  const PrescriptionEditorPage({
    super.key,
    required this.consultationId,
    required this.patientId,
  });

  @override
  State<PrescriptionEditorPage> createState() => _PrescriptionEditorPageState();
}

class _PrescriptionEditorPageState extends State<PrescriptionEditorPage> {
  bool _isEditMode = false;
  bool _isLoading = true;
  bool _isSavingTemplate = false;
  String? _selectedTemplateId;
  String? _selectedTemplateName;
  List<Map<String, dynamic>> _savedTemplates = [];

  final PrescriptionWorkflowRepository _workflowRepository =
      PrescriptionWorkflowRepository(Supabase.instance.client);

  final Map<String, PrescriptionSection> _sectionDefinitions = {
    'medications': PrescriptionSection(
      id: 'medications',
      label: 'รายการยา (Medications)',
    ),
    'general_notes': PrescriptionSection(
      id: 'general_notes',
      label: 'คำแนะนำเพิ่มเติม (General Notes)',
    ),
  };

  List<String> _sectionOrder = ['medications', 'general_notes'];
  final TextEditingController _templateNameController = TextEditingController();

  final List<MedicationItem> _medications = [
    MedicationItem(),
  ]; // Start with 1 empty field
  final TextEditingController _notesController = TextEditingController();

  String get _draftKey => 'prescription_draft_${widget.consultationId}';
  Timer? _draftSaveTimer;
  DateTime? _draftLastSavedAt;

  @override
  void initState() {
    super.initState();
    _loadLayoutPreference();
    _loadSavedTemplates();
    _loadDraft();
  }

  @override
  void dispose() {
    _templateNameController.dispose();
    _notesController.dispose();
    for (final med in _medications) {
      med.dispose();
    }
    _draftSaveTimer?.cancel();
    super.dispose();
  }

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 800), _saveDraft);
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = {
        'medications': _medications.map((m) => {
          'name': m.name,
          'dose': m.dose,
          'frequency': m.frequency,
          'duration': m.duration,
          'notes': m.notes,
        }).toList(),
        'general_notes': _notesController.text,
        'template_id': _selectedTemplateId,
        'template_name': _selectedTemplateName,
        'saved_at': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_draftKey, jsonEncode(draft));
      _draftLastSavedAt = DateTime.now();
      debugPrint('[PrescriptionEditor] Draft saved for ${widget.consultationId}');
    } catch (e) {
      debugPrint('[PrescriptionEditor] Draft save error: $e');
    }
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_draftKey);
      if (jsonStr == null) return;
      final draft = jsonDecode(jsonStr) as Map<String, dynamic>;

      final meds = (draft['medications'] as List?)?.cast<Map<String, dynamic>>();
      if (meds != null && meds.isNotEmpty) {
        for (final med in _medications) {
          med.dispose();
        }
        _medications.clear();
        for (final m in meds) {
          final item = MedicationItem(
            name: m['name'] ?? '',
            dose: m['dose'] ?? '',
            frequency: m['frequency'] ?? '',
            duration: m['duration'] ?? '',
            notes: m['notes'] ?? '',
          );
          _medications.add(item);
        }
      }

      final notes = draft['general_notes'] as String? ?? '';
      _notesController.text = notes;

      _selectedTemplateId = draft['template_id'] as String?;
      _selectedTemplateName = draft['template_name'] as String?;

      setState(() {});
      debugPrint('[PrescriptionEditor] Draft loaded for ${widget.consultationId}');
    } catch (e) {
      debugPrint('[PrescriptionEditor] Draft load error: $e');
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
      _draftLastSavedAt = null;
      debugPrint('[PrescriptionEditor] Draft cleared for ${widget.consultationId}');
    } catch (e) {
      debugPrint('[PrescriptionEditor] Draft clear error: $e');
    }
  }

  List<Map<String, dynamic>> _buildMedicationSnapshot() {
    return _medications
        .where((m) => m.name.trim().isNotEmpty)
        .map(
          (m) => {
            'name': m.name.trim(),
            'dose': m.dose.trim(),
            'frequency': m.frequency.trim(),
            'duration': m.duration.trim(),
            'notes': m.notes.trim(),
          },
        )
        .toList();
  }

  Future<void> _loadSavedTemplates() async {
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) return;

      final templates = _savedTemplates.isNotEmpty
        ? _savedTemplates
        : await _workflowRepository.getProviderTemplates(userId);
      if (!mounted) return;
      setState(() {
        _savedTemplates = templates;
      });
    } catch (e) {
      debugPrint('Error loading templates: $e');
    }
  }

  Future<void> _showTemplateDialog() async {
    final userId = AuthService.instance.currentUser?.id;
    final professionId = AuthService.instance.currentUser?.professionId;
    if (userId == null || professionId == null || professionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบข้อมูลผู้สั่งจ่ายหรืออาชีพของผู้ใช้')),
      );
      return;
    }

    _templateNameController.text = _selectedTemplateName ?? 'ชุดยาที่บันทึกใหม่';

    final templates = await _workflowRepository.getProviderTemplates(userId);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bookmark_add_outlined, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            'ชุดยาและประวัติ',
                            style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _templateNameController,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อชุดยา',
                          hintText: 'เช่น ชุดยาเบื้องต้น / ชุดยาไข้หวัด',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSavingTemplate
                              ? null
                              : () async {
                                  final meds = _buildMedicationSnapshot();
                                  if (meds.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('กรุณากรอกรายการยาอย่างน้อย 1 รายการก่อนบันทึกชุดยา')),
                                    );
                                    return;
                                  }
                                  final templateName = _templateNameController.text.trim().isEmpty
                                      ? 'ชุดยาจากการสั่งครั้งนี้'
                                      : _templateNameController.text.trim();
                                  setState(() => _isSavingTemplate = true);
                                  try {
                                    await _workflowRepository.saveTemplate(
                                      providerId: userId,
                                      professionId: professionId,
                                      templateName: templateName,
                                      medications: meds,
                                      consultationId: widget.consultationId,
                                      description: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
                                      isSharedWithPatient: true,
                                    );
                                    if (!mounted) return;
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('บันทึกชุดยา "$templateName" แล้ว')),
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('บันทึกชุดยาไม่สำเร็จ: $e')),
                                    );
                                  } finally {
                                    if (mounted) setState(() => _isSavingTemplate = false);
                                  }
                                },
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('บันทึกชุดยา'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'ชุดยาที่บันทึกไว้',
                        style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      if (templates.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('ยังไม่มีชุดยาที่บันทึกไว้'),
                        )
                      else
                        ...templates.map((template) {
                          final items = (template['items'] as List?) ?? const [];
                          return Card(
                            child: ListTile(
                              title: Text(template['template_name']?.toString() ?? '-'),
                              subtitle: Text('${items.length} รายการ • ${template['created_at']?.toString() ?? ''}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                final medications = (template['medications_snapshot'] as List?)
                                        ?.map((item) => Map<String, dynamic>.from(item as Map))
                                        .toList() ??
                                    <Map<String, dynamic>>[];
                                setState(() {
                                  _selectedTemplateId = template['id']?.toString();
                                  _selectedTemplateName = template['template_name']?.toString();
                                  for (final old in _medications) {
                                    old.dispose();
                                  }
                                  _medications
                                    ..clear()
                                    ..addAll(
                                      medications.map(
                                        (item) => MedicationItem(
                                          name: item['name']?.toString() ?? '',
                                          dose: item['dose']?.toString() ?? '',
                                          frequency: item['frequency']?.toString() ?? '',
                                          duration: item['duration']?.toString() ?? '',
                                          notes: item['notes']?.toString() ?? '',
                                        ),
                                      ),
                                    );
                                  if (_medications.isEmpty) {
                                    _medications.add(MedicationItem());
                                  }
                                });
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('ใช้ชุดยา ${template['template_name']} แล้ว')),
                                );
                              },
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadLayoutPreference() async {
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) return;

      final prefs = await Supabase.instance.client
          .from('user_ui_preferences')
          .select('preference_value')
          .eq('user_id', userId)
          .eq('preference_key', 'prescription_layout')
          .maybeSingle();

      if (prefs != null && prefs['preference_value'] != null) {
        final List<dynamic> savedOrder = jsonDecode(prefs['preference_value']);
        setState(() {
          _sectionOrder = savedOrder.cast<String>();
        });
      }
    } catch (e) {
      debugPrint('Error loading layout: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveLayoutPreference() async {
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) return;

      final jsonValue = jsonEncode(_sectionOrder);

      await Supabase.instance.client.from('user_ui_preferences').upsert({
        'user_id': userId,
        'preference_key': 'prescription_layout',
        'preference_value': jsonValue,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกรูปแบบฟอร์มสำเร็จ')),
        );
      }
    } catch (e) {
      debugPrint('Error saving layout: $e');
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _sectionOrder.removeAt(oldIndex);
      _sectionOrder.insert(newIndex, item);
    });
  }

  void _addMedication() {
    setState(() {
      _medications.add(MedicationItem());
    });
    _scheduleDraftSave();
  }

  void _removeMedication(int index) {
    setState(() {
      _medications[index].dispose();
      _medications.removeAt(index);
    });
    _scheduleDraftSave();
  }

  Future<void> _submitPrescription() async {
    _draftSaveTimer?.cancel(); // Cancel any pending draft save before submit
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) return;
      final professionId = AuthService.instance.currentUser?.professionId;
      if (professionId == null || professionId.isEmpty) {
        throw Exception('ไม่พบอาชีพของผู้สั่งจ่าย');
      }

      // 1. สร้างรายการยา
      final medicationsList = _buildMedicationSnapshot();

      if (medicationsList.isEmpty || medicationsList.every((m) => (m['name'] ?? '').isEmpty)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('กรุณาระบุรายการยาอย่างน้อย 1 รายการ')),
          );
        }
        return;
      }

      // 2. ตรวจสอบความเสี่ยงยาก่อนสั่งจ่าย
      setState(() => _isLoading = true);
      final screener = DrugRiskScreeningService(Supabase.instance.client);
      final screenResults = await screener.screenPrescription(
        medications: medicationsList,
        providerId: userId,
        isTelemedicine: true,
      );
      setState(() => _isLoading = false);

      // 3. แสดง Dialog ผลการตรวจสอบ
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PrescriptionRiskDialog(
          results: screenResults,
          onNavigateToUpload: () {
            // Navigate to ProfilePage so provider can upload missing license
            // After upload, provider should return to this prescription editor
            Navigator.pushNamed(context, '/profile');
          },
        ),
      );

      if (proceed != true) return;

      // 4. บันทึกใบสั่งยา
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กำลังบันทึกใบสั่งยา...')),
      );

      final response = await _workflowRepository.createPrescription(
        consultationId: widget.consultationId,
        providerId: userId,
        patientId: widget.patientId,
        roomId: widget.consultationId,
        medications: medicationsList,
        notes: _notesController.text,
        templateId: _selectedTemplateId,
        templateName: _selectedTemplateName,
        selectionSnapshot: medicationsList,
      );

      final prescriptionId = response['id'];

      // Send chat message
      final chatRepo = ServiceLocator.instance.chatRepository;
      final msg = ChatMessage(
        id: const Uuid().v4(),
        roomId: widget.consultationId,
        senderId: userId,
        type: 'prescription',
        content: 'ใบสั่งยา (Prescription)',
        attachmentUrl: prescriptionId,
        createdAt: DateTime.now(),
      );
      await chatRepo.sendMessage(msg);
      await _clearDraft();

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving prescription: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    }
  }

  Widget _buildMedicationsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._medications.asMap().entries.map((entry) {
          final index = entry.key;
          final med = entry.value;
          return _MedicationCardWidget(
            key: ValueKey(med),
            item: med,
            showDelete: _medications.length > 1,
            onDelete: () => _removeMedication(index),
            onChanged: _scheduleDraftSave,
          );
        }).toList(),
        if (!_isEditMode)
          TextButton.icon(
            onPressed: _addMedication,
            icon: const Icon(Icons.add),
            label: const Text('เพิ่มรายการยา'),
          ),
      ],
    );
  }

  Widget _buildTemplateHeaderCard() {
    final hasTemplate = _selectedTemplateName != null && _selectedTemplateName!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.bookmark_outline, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasTemplate
                  ? 'กำลังใช้ชุดยา: $_selectedTemplateName'
                  : 'สามารถบันทึกชุดยานี้เป็น template ให้ผู้ป่วยเลือกในภายหลัง',
              style: AppTextStyles.bodySmall.copyWith(
                color: Colors.green.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: _showTemplateDialog,
            child: const Text('จัดการชุดยา'),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralNotes() {
    return TextField(
      controller: _notesController,
      maxLines: 3,
      onChanged: (_) => _scheduleDraftSave(),
      decoration: InputDecoration(
        hintText: 'คำแนะนำการทานยาเพิ่มเติม...',
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(12),
      ),
    );
  }

  bool get _hasUnsavedChanges {
    return _medications.any((m) => m.name.trim().isNotEmpty) ||
        _notesController.text.trim().isNotEmpty ||
        _selectedTemplateId != null;
  }

  Future<bool> _showExitConfirmationDialog() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการออก'),
        content: const Text('ข้อมูลใบสั่งยายังไม่ได้บันทึก หากออกไปตอนนี้ข้อมูลจะสูญหาย ต้องการออกหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('อยู่ต่อ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('ออกโดยไม่บันทึก'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return WillPopScope(
      onWillPop: _showExitConfirmationDialog,
      child: Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'ออกใบสั่งยา',
          style: TextStyle(color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'บันทึกเป็นชุดยา',
            onPressed: _showTemplateDialog,
          ),
          IconButton(
            icon: Icon(
              _isEditMode ? Icons.check : Icons.format_list_bulleted,
              color: _isEditMode ? Colors.green : AppColors.primary,
            ),
            tooltip: 'ปรับแต่งฟอร์ม',
            onPressed: () {
              setState(() {
                _isEditMode = !_isEditMode;
              });
              if (!_isEditMode) {
                _saveLayoutPreference();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTemplateHeaderCard(),
          if (_isEditMode)
            Container(
              color: Colors.green.shade50,
              padding: const EdgeInsets.all(12),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ลากเพื่อสลับตำแหน่งส่วนประกอบฟอร์มใบสั่งยา\nระบบจะจดจำรูปแบบนี้ไว้',
                      style: TextStyle(color: Colors.green, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ReorderableListView(
              padding: const EdgeInsets.all(16),
              onReorder: _onReorder,
              children: _sectionOrder.map((key) {
                final section = _sectionDefinitions[key]!;
                return Container(
                  key: ValueKey(key),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (_isEditMode)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(
                                  Icons.drag_indicator,
                                  color: Colors.grey,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                section.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!_isEditMode) ...[
                          const SizedBox(height: 12),
                          if (key == 'medications') _buildMedicationsList(),
                          if (key == 'general_notes') _buildGeneralNotes(),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (!_isEditMode)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitPrescription,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'บันทึก & ส่งใบสั่งยา',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),);
  }
}
