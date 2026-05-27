import 'package:flutter/material.dart';
import '../../../../../../core/constants/app_colors.dart';
import 'health_data_chip.dart';
import 'history_tile.dart';
import 'medication_tile.dart';
import 'metric_group_card.dart';
import 'general_section_content.dart';

class GrantedSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const GrantedSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class GrantedHealthSections extends StatelessWidget {
  final Map<String, dynamic> data;

  const GrantedHealthSections({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[];
    final granted = data['grantedFields'] as Map<String, dynamic>? ?? {};

    final general = data['general'] as Map<String, dynamic>?;
    if (granted['general'] == true && general != null && general.isNotEmpty) {
      sections.add(
        GrantedSectionCard(
          icon: Icons.favorite_outline,
          title: 'ข้อมูลสุขภาพทั่วไป',
          children: [GeneralSectionContent(general: general)],
        ),
      );
    }

    final history = (data['history'] as List?)?.cast<Map<String, dynamic>>();
    if (granted['history'] == true && history != null && history.isNotEmpty) {
      sections.add(
        GrantedSectionCard(
          icon: Icons.event_note,
          title: 'ประวัติการรักษาในคำปรึกษานี้',
          children: history.map((e) => HistoryTile(note: e)).toList(),
        ),
      );
    }

    final labs = (data['labs'] as Map<String, dynamic>?)?['metrics']
        as Map<String, dynamic>?;
    if (granted['labs'] == true && labs != null && labs.isNotEmpty) {
      sections.add(
        GrantedSectionCard(
          icon: Icons.analytics_outlined,
          title: 'ข้อมูลจากอุปกรณ์สุขภาพ',
          children:
              labs.entries.map((entry) => MetricGroupCard(metricType: entry.key, entries: entry.value)).toList(),
        ),
      );
    }

    final meds = (data['medications'] as List?)?.cast<Map<String, dynamic>>();
    if (granted['medications'] == true && meds != null && meds.isNotEmpty) {
      sections.add(
        GrantedSectionCard(
          icon: Icons.medication_liquid,
          title: 'รายการยาที่สั่งในคำปรึกษานี้',
          children: meds.map((e) => MedicationTile(prescription: e)).toList(),
        ),
      );
    }

    if (sections.isEmpty) {
      sections.add(
        Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            'ไม่มีข้อมูลสุขภาพที่สามารถแสดงได้',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }
}
