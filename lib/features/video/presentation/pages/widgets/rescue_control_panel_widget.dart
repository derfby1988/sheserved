import 'dart:ui';
import 'package:flutter/material.dart';

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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6), // Further transparency
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.emergency_share, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'เครื่องมือผู้ช่วยเหลือ (Responder)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold, 
                          color: Colors.blue, 
                          fontSize: 11, // Smaller for 1 line
                          fontFamily: 'SukhumvitSet',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    _buildControlStatusBadge(),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onOpenInMaps,
                        icon: const Icon(Icons.navigation, size: 16),
                        label: const Text(
                          'นำทาง Maps',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
                          maxLines: 1,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade50.withValues(alpha: 0.6),
                          foregroundColor: Colors.blue,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => onUpdateStatus('arrived'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade50.withValues(alpha: 0.6),
                          foregroundColor: Colors.orange.shade900,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text(
                          'ถึงที่เกิดเหตุแล้ว',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.center,
                  child: FractionallySizedBox(
                    widthFactor: 0.5, // 50% width
                    child: ElevatedButton(
                      onPressed: () => onUpdateStatus('resolved'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.withValues(alpha: 0.9),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 42), // Width 0 but height 42
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text(
                        'จบภารกิจ', 
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        maxLines: 1,
                      ),
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

  Widget _buildControlStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue.shade100.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'กำลังปฏิบัติการ',
        style: TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold),
      ),
    );
  }
}
