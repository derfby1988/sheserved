import 'dart:ui';
import 'package:flutter/material.dart';

/// เครื่องมือผู้ช่วยเหลือ (Responder) — วางแบบแนวตั้ง compact
/// ตำแหน่ง: ใต้กล่องยอดนิยมมุมขวาบน (ต่อจากกล่องยอดนิยม)
/// เพื่อไม่ให้ทับกล่องแชท/ปุ่มส่งกำลังใจ/เปิดรับบริจาคด้านล่าง
/// อ้างอิง VIDEO_SYSTEM_PLAN.md — Mission Lock UI Adjustment
class RescueControlPanelWidget extends StatelessWidget {
  final VoidCallback onOpenInMaps;
  final Function(String) onUpdateStatus;

  const RescueControlPanelWidget({
    super.key,
    required this.onOpenInMaps,
    required this.onUpdateStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: Colors.white.withOpacity(0.1), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.emergency_share,
                        color: Colors.blue, size: 16),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'เครื่องมือผู้ช่วยเหลือ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          fontSize: 10,
                          fontFamily: 'SukhumvitSet',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _buildControlStatusBadge(),
                  ],
                ),
                const SizedBox(height: 10),
                _buildToolButton(
                  context: context,
                  icon: Icons.navigation,
                  label: 'นำทาง Maps',
                  backgroundColor: Colors.blue.shade50.withOpacity(0.6),
                  foregroundColor: Colors.blue,
                  onTap: onOpenInMaps,
                ),
                const SizedBox(height: 8),
                _buildToolButton(
                  context: context,
                  icon: Icons.location_on,
                  label: 'ถึงที่เกิดเหตุแล้ว',
                  backgroundColor: Colors.orange.shade50.withOpacity(0.6),
                  foregroundColor: Colors.orange.shade900,
                  onTap: () => onUpdateStatus('arrived'),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () => onUpdateStatus('resolved'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.withOpacity(0.9),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text(
                      'จบภารกิจ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFamily: 'SukhumvitSet',
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 36,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.normal,
            fontFamily: 'SukhumvitSet',
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildControlStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue.shade100.withOpacity(0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'กำลังปฏิบัติการ',
        style: TextStyle(
          fontSize: 8,
          color: Colors.blue,
          fontWeight: FontWeight.bold,
          fontFamily: 'SukhumvitSet',
        ),
      ),
    );
  }
}
