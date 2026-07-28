import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/repositories/consultation_repository.dart';
import '../../../../features/chat/data/models/chat_models.dart';

class ConsultationNoteField {
  final String id;
  final String label;
  final String hint;
  final int maxLines;

  ConsultationNoteField({
    required this.id,
    required this.label,
    required this.hint,
    this.maxLines = 3,
  });
}

class ConsultationNoteEditorPage extends StatefulWidget {
  final String consultationId;
  final String patientId;

  const ConsultationNoteEditorPage({
    super.key,
    required this.consultationId,
    required this.patientId,
  });

  @override
  State<ConsultationNoteEditorPage> createState() =>
      _ConsultationNoteEditorPageState();
}

class _ConsultationNoteEditorPageState
    extends State<ConsultationNoteEditorPage> {
  final _repository = ServiceLocator.instance.consultationRepository;
  bool _isEditMode = false;
  bool _isLoading = true;

  // Available fields
  final Map<String, ConsultationNoteField> _fieldDefinitions = {
    'chief_complaint': ConsultationNoteField(
      id: 'chief_complaint',
      label: 'อาการสำคัญ (Chief Complaint)',
      hint: 'ผู้ป่วยมาด้วยอาการ...',
    ),
    'diagnosis': ConsultationNoteField(
      id: 'diagnosis',
      label: 'การวินิจฉัย (Diagnosis)',
      hint: 'ผลการวินิจฉัยโรค...',
    ),
    'treatment_plan': ConsultationNoteField(
      id: 'treatment_plan',
      label: 'แผนการรักษา (Treatment Plan)',
      hint: 'แนวทางการรักษา...',
    ),
    'recommendations': ConsultationNoteField(
      id: 'recommendations',
      label: 'คำแนะนำ (Recommendations)',
      hint: 'ข้อปฏิบัติตัวสำหรับผู้ป่วย...',
    ),
  };

  // Default order
  List<String> _fieldOrder = [
    'chief_complaint',
    'diagnosis',
    'treatment_plan',
    'recommendations',
  ];

  final Map<String, TextEditingController> _controllers = {};

  DateTime? _followUpDate;

  @override
  void initState() {
    super.initState();
    for (var key in _fieldDefinitions.keys) {
      _controllers[key] = TextEditingController();
    }
    _loadLayoutPreference();
  }

  @override
  void dispose() {
    for (var ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLayoutPreference() async {
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) return;

      final prefs = await Supabase.instance.client
          .from('user_ui_preferences')
          .select('preference_value')
          .eq('user_id', userId)
          .eq('preference_key', 'consultation_note_layout')
          .maybeSingle();

      if (prefs != null && prefs['preference_value'] != null) {
        final List<dynamic> savedOrder = jsonDecode(prefs['preference_value']);
        setState(() {
          _fieldOrder = savedOrder.cast<String>();
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

      final jsonValue = jsonEncode(_fieldOrder);

      await Supabase.instance.client.from('user_ui_preferences').upsert({
        'user_id': userId,
        'preference_key': 'consultation_note_layout',
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
      final item = _fieldOrder.removeAt(oldIndex);
      _fieldOrder.insert(newIndex, item);
    });
  }

  Future<void> _submitNote() async {
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) return;

      final data = {
        'consultation_id': widget.consultationId,
        'provider_id': userId,
        'patient_id': widget.patientId,
        'chief_complaint': _controllers['chief_complaint']?.text,
        'diagnosis': _controllers['diagnosis']?.text,
        'treatment_plan': _controllers['treatment_plan']?.text,
        'recommendations': _controllers['recommendations']?.text,
        'follow_up_date': _followUpDate?.toIso8601String(),
        'is_visible_to_patient': true,
      };

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กำลังบันทึกข้อมูล...')));

      final response = await Supabase.instance.client
          .from('consultation_notes')
          .insert(data)
          .select()
          .single();

      final noteId = response['id'];

      // Send chat message
      final chatRepo = ServiceLocator.instance.chatRepository;
      final msg = ChatMessage(
        id: const Uuid().v4(),
        roomId: widget.consultationId,
        senderId: userId,
        type: 'note',
        content: 'บันทึกการตรวจ (Consultation Note)',
        attachmentUrl: noteId,
        createdAt: DateTime.now(),
      );
      await chatRepo.sendMessage(msg, callerId: userId);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving note: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'บันทึกการตรวจ',
          style: TextStyle(color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
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
                // Just turned off edit mode -> save layout
                _saveLayoutPreference();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isEditMode)
            Container(
              color: Colors.blue.shade50,
              padding: const EdgeInsets.all(12),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ลากเพื่อสลับตำแหน่งหัวข้อในฟอร์ม\nระบบจะจดจำรูปแบบนี้ไว้ใช้ครั้งถัดไป',
                      style: TextStyle(color: Colors.blue, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ReorderableListView(
              padding: const EdgeInsets.all(16),
              onReorder: _onReorder,
              children: _fieldOrder.map((key) {
                final field = _fieldDefinitions[key]!;
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
                            Text(
                              field.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        if (!_isEditMode) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _controllers[key],
                            maxLines: field.maxLines,
                            decoration: InputDecoration(
                              hintText: field.hint,
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.all(12),
                            ),
                          ),
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
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (date != null) {
                            setState(() => _followUpDate = date);
                          }
                        },
                        icon: const Icon(Icons.calendar_month),
                        label: Text(
                          _followUpDate == null
                              ? 'นัดติดตามอาการ'
                              : '${_followUpDate!.day}/${_followUpDate!.month}/${_followUpDate!.year}',
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submitNote,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'บันทึก & ส่ง',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
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
}
