import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/consultation_entry.dart';
import '../../data/models/consultation_request_model.dart';
import '../widgets/health_data/body_map_chat_bar.dart';

class BodyMapChatController {
  String? activeBodyPart;
  String? activeBodyPartLabel;
  final Map<String, int> bodyPartMessageCount = {};
  final List<BodyPartChipData> bodyPartChips = [];
  final TextEditingController msgController;

  BodyMapChatController({required this.msgController});

  void clear() {
    activeBodyPart = null;
    activeBodyPartLabel = null;
    bodyPartMessageCount.clear();
    bodyPartChips.clear();
  }

  List<BodyPartChipData> resolveBodyPartChips({
    ConsultationRequestModel? request,
    ConsultationEntry? entry,
    Map<String, dynamic>? consultationData,
  }) {
    bodyPartChips.clear();
    final seenKeys = <String>{};

    void addChip(String key, String label) {
      final normalizedKey = key.toLowerCase().trim();
      if (normalizedKey.isEmpty || seenKeys.contains(normalizedKey)) return;
      seenKeys.add(normalizedKey);
      bodyPartChips.add(BodyPartChipData(key: normalizedKey, label: label));
    }

    void collectFromSymptoms(List<dynamic>? symptoms) {
      for (final s in symptoms ?? []) {
        if (s is Map<String, dynamic>) {
          final regionId = s['region_id']?.toString().trim() ?? '';
          final label = s['display_label']?.toString().trim() ?? '';
          if (regionId.isNotEmpty && label.isNotEmpty) {
            addChip(regionId, label);
          }
        }
      }
    }

    collectFromSymptoms(request?.symptoms);
    collectFromSymptoms(consultationData?['symptoms']);

    void collectFromBodyArea(Map<String, dynamic>? bodyArea) {
      if (bodyArea == null) return;
      for (final key in bodyArea.keys) {
        if (['gender', 'age', 'lang', 'sex'].contains(key)) continue;
        final label = key.toString().trim();
        if (label.isNotEmpty) addChip(label, label);
      }
    }

    collectFromBodyArea(request?.bodyArea);
    collectFromBodyArea(consultationData?['body_area']);

    final entryBodyAreaStr = entry?.bodyArea;
    if (entryBodyAreaStr != null &&
        entryBodyAreaStr.isNotEmpty &&
        entryBodyAreaStr != 'ไม่ระบุ') {
      for (final part in entryBodyAreaStr.split(',')) {
        final trimmed = part.trim();
        if (trimmed.isNotEmpty) addChip(trimmed, trimmed);
      }
    }

    void collectFromSymptomsChart(Map<String, dynamic>? chart) {
      final parts = chart?['parts'];
      if (parts is List) {
        for (final p in parts) {
          if (p is Map<String, dynamic>) {
            final key = p['key']?.toString().trim() ??
                p['name']?.toString().trim() ?? '';
            final label = p['label']?.toString().trim() ??
                p['name']?.toString().trim() ?? key;
            if (key.isNotEmpty) addChip(key, label);
          }
        }
      }
    }

    collectFromSymptomsChart(request?.symptomsChart);
    collectFromSymptomsChart(entry?.symptomsChart);
    collectFromSymptomsChart(consultationData?['symptoms_chart']);

    return bodyPartChips;
  }

  Future<void> loadMessageCounts({
    required String? roomId,
    required String? currentUserId,
  }) async {
    if (roomId == null || currentUserId == null) return;

    try {
      final response = await Supabase.instance.client
          .from('chat_messages')
          .select('body_part')
          .eq('room_id', roomId)
          .eq('sender_id', currentUserId)
          .not('body_part', 'is', null);

      bodyPartMessageCount.clear();
      for (final row in response) {
        final bp = row['body_part']?.toString().toLowerCase().trim();
        if (bp != null && bp.isNotEmpty) {
          bodyPartMessageCount[bp] = (bodyPartMessageCount[bp] ?? 0) + 1;
        }
      }
    } catch (e) {
      debugPrint('[BodyMapChatController] loadMessageCounts error: $e');
    }
  }

  void onChipSelected(String? key) {
    activeBodyPart = key;
    if (key == null) {
      activeBodyPartLabel = null;
      _stripPrefix();
    } else {
      final chip = bodyPartChips.firstWhere(
        (c) => c.key == key,
        orElse: () => BodyPartChipData(key: key, label: key),
      );
      activeBodyPartLabel = chip.label;
      _applyPrefix(chip.label);
    }
  }

  void clearBodyPart() {
    activeBodyPart = null;
    activeBodyPartLabel = null;
    _stripPrefix();
  }

  void _applyPrefix(String label) {
    final prefix = '$label: ';
    final currentText = msgController.text;
    if (currentText.contains(': ')) {
      final idx = currentText.indexOf(': ');
      msgController.text = prefix + currentText.substring(idx + 2);
    } else {
      msgController.text = prefix + currentText;
    }
  }

  void _stripPrefix() {
    final text = msgController.text;
    if (text.contains(': ')) {
      msgController.text = text.substring(text.indexOf(': ') + 2);
    }
  }
}
