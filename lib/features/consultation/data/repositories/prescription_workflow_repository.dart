import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PrescriptionWorkflowRepository {
  final SupabaseClient _client;

  PrescriptionWorkflowRepository(this._client);

  List<Map<String, dynamic>> _castRows(dynamic response) {
    if (response is! List) return <Map<String, dynamic>>[];
    return response
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Map<String, dynamic> _withItems(
    Map<String, dynamic> template,
    List<Map<String, dynamic>> items,
  ) {
    return {
      ...template,
      'items': items.where((item) => item['template_id'] == template['id']).toList(),
    };
  }

  Future<Map<String, dynamic>?> getPrescriptionById(String prescriptionId) async {
    try {
      final response = await _client
          .from('prescriptions')
          .select()
          .eq('id', prescriptionId)
          .maybeSingle();
      return response == null ? null : Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('[PrescriptionWorkflowRepository] getPrescriptionById error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getPrescriptionsForConsultation({
    required String consultationId,
    required String patientId,
  }) async {
    try {
      final response = await _client
          .from('prescriptions')
          .select('id, medications, notes, status, issued_at, provider_id, template_id, template_name, selected_items_snapshot, selected_by_patient_at, selection_history_id')
          .eq('consultation_id', consultationId)
          .eq('patient_id', patientId)
          .order('issued_at', ascending: false);
      return _castRows(response);
    } catch (e) {
      debugPrint('[PrescriptionWorkflowRepository] getPrescriptionsForConsultation error: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> getProviderTemplates(String providerId) async {
    try {
      final templatesResponse = await _client
          .from('prescription_templates')
          .select()
          .eq('provider_id', providerId)
          .eq('is_active', true)
          .order('created_at', ascending: false);
      final templates = _castRows(templatesResponse);
      if (templates.isEmpty) return templates;

      final templateIds = templates.map((e) => e['id'] as String).toList();
      final itemsResponse = await _client
          .from('prescription_template_items')
          .select()
          .inFilter('template_id', templateIds)
          .order('sort_order', ascending: true);
      final items = _castRows(itemsResponse);

      return templates.map((template) => _withItems(template, items)).toList();
    } catch (e) {
      debugPrint('[PrescriptionWorkflowRepository] getProviderTemplates error: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> getSharedTemplatesForConsultation({
    required String consultationId,
  }) async {
    try {
      final templatesResponse = await _client
          .from('prescription_templates')
          .select()
          .eq('consultation_id', consultationId)
          .eq('is_active', true)
          .eq('is_shared_with_patient', true)
          .order('created_at', ascending: false);
      final templates = _castRows(templatesResponse);
      if (templates.isEmpty) return templates;

      final templateIds = templates.map((e) => e['id'] as String).toList();
      final itemsResponse = await _client
          .from('prescription_template_items')
          .select()
          .inFilter('template_id', templateIds)
          .order('sort_order', ascending: true);
      final items = _castRows(itemsResponse);

      return templates.map((template) => _withItems(template, items)).toList();
    } catch (e) {
      debugPrint('[PrescriptionWorkflowRepository] getSharedTemplatesForConsultation error: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>> saveTemplate({
    required String providerId,
    required String professionId,
    required String templateName,
    required List<Map<String, dynamic>> medications,
    String? consultationId,
    String? sourcePrescriptionId,
    String? description,
    bool isSharedWithPatient = true,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final templateResponse = await _client
          .from('prescription_templates')
          .insert({
            'provider_id': providerId,
            'profession_id': professionId,
            'consultation_id': consultationId,
            'source_prescription_id': sourcePrescriptionId,
            'template_name': templateName,
            'description': description,
            'is_shared_with_patient': isSharedWithPatient,
            'is_active': true,
            'medications_snapshot': medications,
            'created_at': now,
            'updated_at': now,
          })
          .select()
          .single();

      final template = Map<String, dynamic>.from(templateResponse);
      final templateId = template['id'] as String;
      final itemRows = medications.asMap().entries.map((entry) {
        final med = entry.value;
        return {
          'template_id': templateId,
          'item_name': med['name'] ?? '',
          'dosage': med['dose'],
          'frequency': med['frequency'],
          'duration': med['duration'],
          'route': med['route'] ?? 'oral',
          'quantity': med['quantity'] ?? 1,
          'sort_order': entry.key,
          'created_at': now,
        };
      }).toList();

      if (itemRows.isNotEmpty) {
        await _client.from('prescription_template_items').insert(itemRows);
      }

      template['items'] = itemRows;
      return template;
    } catch (e) {
      debugPrint('[PrescriptionWorkflowRepository] saveTemplate error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createPrescription({
    required String consultationId,
    required String providerId,
    required String patientId,
    required List<Map<String, dynamic>> medications,
    String? roomId,
    String? notes,
    String? templateId,
    String? templateName,
    List<Map<String, dynamic>>? selectionSnapshot,
    String status = 'active',
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final data = {
        'consultation_id': consultationId,
        'provider_id': providerId,
        'patient_id': patientId,
        'room_id': roomId,
        'medications': medications,
        'notes': notes,
        'status': status,
        'template_id': templateId,
        'template_name': templateName,
        'template_snapshot': medications,
        'selected_items_snapshot': selectionSnapshot ?? medications,
        'issued_at': now,
        'created_at': now,
        'updated_at': now,
      };

      final response = await _client
          .from('prescriptions')
          .insert(data)
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('[PrescriptionWorkflowRepository] createPrescription error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> recordPatientSelection({
    required String consultationId,
    required String patientId,
    required String providerId,
    required String templateId,
    required String templateName,
    required List<Map<String, dynamic>> selectedItems,
    String selectionSource = 'patient',
    String? prescriptionId,
    String? notes,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final response = await _client
          .from('prescription_selection_history')
          .insert({
            'consultation_id': consultationId,
            'prescription_id': prescriptionId,
            'patient_id': patientId,
            'provider_id': providerId,
            'template_id': templateId,
            'template_name': templateName,
            'selection_source': selectionSource,
            'selected_items': selectedItems,
            'notes': notes,
            'selected_at': now,
            'created_at': now,
            'updated_at': now,
          })
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('[PrescriptionWorkflowRepository] recordPatientSelection error: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getSelectionHistory({
    required String consultationId,
    required String patientId,
  }) async {
    try {
      final response = await _client
          .from('prescription_selection_history')
          .select()
          .eq('consultation_id', consultationId)
          .eq('patient_id', patientId)
          .order('selected_at', ascending: false)
          .limit(20);
      return _castRows(response);
    } catch (e) {
      debugPrint('[PrescriptionWorkflowRepository] getSelectionHistory error: $e');
      return <Map<String, dynamic>>[];
    }
  }
}
