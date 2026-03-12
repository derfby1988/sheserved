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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.emergency_share, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                'เครื่องมือสำหรับผู้ช่วยเหลือ (Responder Tools)',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
              ),
              const Spacer(),
              _buildControlStatusBadge(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onOpenInMaps,
                  icon: const Icon(Icons.navigation),
                  label: const Text('นำทาง (Maps)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade50,
                    foregroundColor: Colors.blue,
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => onUpdateStatus('arrived'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade50,
                    foregroundColor: Colors.orange.shade900,
                    elevation: 0,
                  ),
                  child: const Text('ถึงที่เกิดเหตุแล้ว'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => onUpdateStatus('resolved'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 45),
              elevation: 0,
            ),
            child: const Text('จบภารกิจ (Resolved)', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildControlStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'กำลังปฏิบัติการ',
        style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold),
      ),
    );
  }
}
