import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class KpiRefreshHistoryPage extends StatefulWidget {
  const KpiRefreshHistoryPage({super.key});

  @override
  State<KpiRefreshHistoryPage> createState() => _KpiRefreshHistoryPageState();
}

class _KpiRefreshHistoryPageState extends State<KpiRefreshHistoryPage> {
  final SupabaseClient _client = Supabase.instance.client;
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _client
          .from('kpi_refresh_log')
          .select()
          .order('started_at', ascending: false)
          .limit(100);

      setState(() {
        _logs = (response as List<dynamic>).cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'โหลดประวัติไม่สำเร็จ: $e';
        _isLoading = false;
      });
    }
  }

  String _formatDateTime(String? iso) {
    if (iso == null) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Color _statusColor(String? refreshType, String? errorMessage) {
    if (errorMessage != null && errorMessage.isNotEmpty) {
      return const Color(0xFFEF5350);
    }
    if (refreshType == 'scheduled') {
      return const Color(0xFF2196F3);
    }
    if (refreshType == 'manual') {
      return const Color(0xFF4CAF50);
    }
    return Colors.grey;
  }

  String _statusLabel(String? refreshType, String? errorMessage) {
    if (errorMessage != null && errorMessage.isNotEmpty) return 'ผิดพลาด';
    switch (refreshType) {
      case 'scheduled':
        return 'อัตโนมัติ';
      case 'manual':
        return 'ด้วยมือ';
      case 'initial':
        return 'เริ่มต้น';
      default:
        return refreshType ?? 'ไม่ระบุ';
    }
  }

  String _targetTypeLabel(String? type) {
    switch (type) {
      case 'revenue':
        return 'ยอดขาย';
      case 'net_profit':
        return 'กำไรสุทธิ';
      case 'consultations':
        return 'การปรึกษา';
      case 'appointments':
        return 'นัดหมาย';
      case 'all':
        return 'ทั้งหมด';
      default:
        return type ?? 'ไม่ระบุ';
    }
  }

  String _periodLabel(String? period) {
    switch (period) {
      case 'daily':
        return 'รายวัน';
      case 'weekly':
        return 'รายสัปดาห์';
      case 'monthly':
        return 'รายเดือน';
      case 'quarterly':
        return 'รายไตรมาส';
      case 'yearly':
        return 'รายปี';
      default:
        return period ?? 'ไม่ระบุ';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติการรีเฟรช'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadLogs,
            tooltip: 'รีเฟรช',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: Colors.red[600])),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadLogs,
                        child: const Text('ลองอีกครั้ง'),
                      ),
                    ],
                  ),
                )
              : _logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text(
                            'ยังไม่มีประวัติการรีเฟรช',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadLogs,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          final statusColor = _statusColor(
                            log['refresh_type'] as String?,
                            log['error_message'] as String?,
                          );

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusColor.withAlpha(30),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          _statusLabel(
                                            log['refresh_type'] as String?,
                                            log['error_message'] as String?,
                                          ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _formatDateTime(log['started_at'] as String?),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildInfoItem(
                                          'ประเภท',
                                          _targetTypeLabel(log['target_type'] as String?),
                                        ),
                                      ),
                                      Expanded(
                                        child: _buildInfoItem(
                                          'ช่วงเวลา',
                                          _periodLabel(log['period_type'] as String?),
                                        ),
                                      ),
                                      Expanded(
                                        child: _buildInfoItem(
                                          'จำนวน',
                                          '${log['records_processed'] ?? 0} รายการ',
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (log['error_message'] != null &&
                                      (log['error_message'] as String).isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(top: 12),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.red[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.red[200]!),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.error_outline,
                                              size: 16, color: Colors.red[600]),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              log['error_message'] as String,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.red[700],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[500],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
