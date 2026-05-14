import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../features/chat/data/models/chat_models.dart';

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

  MedicationItem({
    this.name = '',
    this.dose = '',
    this.frequency = '',
    this.duration = '',
    this.notes = '',
  });
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

  final List<MedicationItem> _medications = [
    MedicationItem(),
  ]; // Start with 1 empty field
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLayoutPreference();
  }

  @override
  void dispose() {
    _notesController.dispose();
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

      await Supabase.instance.client
          .from('user_ui_preferences')
          .upsert({
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
  }

  void _removeMedication(int index) {
    setState(() {
      _medications.removeAt(index);
    });
  }

  Future<void> _submitPrescription() async {
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) return;

      final medicationsList = _medications.map((m) => {
        'name': m.name,
        'dose': m.dose,
        'frequency': m.frequency,
        'duration': m.duration,
        'notes': m.notes,
      }).toList();

      final data = {
        'consultation_id': widget.consultationId,
        'provider_id': userId,
        'patient_id': widget.patientId,
        'room_id': widget.consultationId,
        'medications': medicationsList,
        'notes': _notesController.text,
        'status': 'active',
      };

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กำลังบันทึกใบสั่งยา...')),
      );

      final response = await Supabase.instance.client
          .from('prescriptions')
          .insert(data)
          .select()
          .single();

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

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving prescription: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
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
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: med.name,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อยา (Name)',
                          border: InputBorder.none,
                        ),
                        onChanged: (val) => med.name = val,
                      ),
                    ),
                    if (_medications.length > 1)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeMedication(index),
                      ),
                  ],
                ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: med.dose,
                        decoration: const InputDecoration(
                          labelText: 'ขนาด (Dose)',
                          border: InputBorder.none,
                        ),
                        onChanged: (val) => med.dose = val,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: med.frequency,
                        decoration: const InputDecoration(
                          labelText: 'ความถี่ (Freq)',
                          border: InputBorder.none,
                        ),
                        onChanged: (val) => med.frequency = val,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: med.duration,
                        decoration: const InputDecoration(
                          labelText: 'ระยะเวลา',
                          border: InputBorder.none,
                        ),
                        onChanged: (val) => med.duration = val,
                      ),
                    ),
                  ],
                ),
              ],
            ),
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

  Widget _buildGeneralNotes() {
    return TextField(
      controller: _notesController,
      maxLines: 3,
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
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
                            Text(
                              section.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
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
    );
  }
}
