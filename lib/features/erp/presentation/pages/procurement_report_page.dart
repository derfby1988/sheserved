import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/glass_card.dart';

class ProcurementReportPage extends StatefulWidget {
  final String professionId;
  final String? branchId;

  const ProcurementReportPage({
    super.key,
    required this.professionId,
    this.branchId,
  });

  @override
  State<ProcurementReportPage> createState() => _ProcurementReportPageState();
}

class _ProcurementReportPageState extends State<ProcurementReportPage> {
  String _selectedReportType = 'po_summary';
  DateTimeRange? _dateRange;
  List<Map<String, dynamic>> _data = [];
  bool _isLoading = false;
  String? _errorMessage;

  static const _reportTypes = [
    {'value': 'po_summary', 'label': 'สรุปใบสั่งซื้อ (PO)'},
    {'value': 'gr_summary', 'label': 'สรุปรับของ (GR)'},
    {'value': 'back_order_summary', 'label': 'รายการค้างส่ง (Back Order)'},
    {'value': 'price_variance', 'label': 'เปรียบเทียบราคาซื้อ'},
    {'value': 'supplier_performance', 'label': 'สถิติผู้จัดจำหน่าย'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadReport());
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final now = DateTime.now();
      final start = _dateRange?.start ?? now.subtract(const Duration(days: 30));
      final end = _dateRange?.end ?? now;

      final response = await Supabase.instance.client.rpc(
        'get_procurement_report',
        params: {
          'p_profession_id': widget.professionId,
          'p_report_type': _selectedReportType,
          'p_filters': {
            'start_date': start.toIso8601String().split('T')[0],
            'end_date': end.toIso8601String().split('T')[0],
          },
        },
      );

      final result = response as Map<String, dynamic>;
      final data = result['data'] as List? ?? [];
      if (mounted) {
        setState(() {
          _data = data.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'โหลดรายงานล้มเหลว: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _dateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _loadReport();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('รายงานจัดซื้อ / Procurement Report'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickDateRange,
            tooltip: 'เลือกช่วงวันที่',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadReport,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          if (_dateRange != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_dateRange!.start.toIso8601String().split('T')[0]} → ${_dateRange!.end.toIso8601String().split('T')[0]}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _reportTypes.map((rt) {
            final isSelected = _selectedReportType == rt['value'];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(rt['label']!),
                selected: isSelected,
                onSelected: (_) {
                  setState(() => _selectedReportType = rt['value']!);
                  _loadReport();
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadReport, child: const Text('ลองใหม่')),
          ],
        ),
      );
    }
    if (_data.isEmpty) {
      return Center(
        child: Text(
          'ไม่มีข้อมูลในช่วงเวลาที่เลือก',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _buildTable(),
      ),
    );
  }

  Widget _buildTable() {
    final columns = _getColumnsForReport(_selectedReportType);
    return GlassCard(
      section: GlassSection.card,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DataTable(
          columnSpacing: 24,
          columns: columns
              .map((c) => DataColumn(
                    label: Text(c, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ))
              .toList(),
          rows: _data.map((row) {
            return DataRow(
              cells: _getCellsForReport(_selectedReportType, row),
            );
          }).toList(),
        ),
      ),
    );
  }

  List<String> _getColumnsForReport(String type) {
    switch (type) {
      case 'po_summary':
        return ['เลข PO', 'ผู้จัดจำหน่าย', 'สถานะ', 'ยอดรวม', 'วันที่'];
      case 'gr_summary':
        return ['เลข GR', 'เลข PO', 'ผู้จัดจำหน่าย', 'วันที่รับ', 'จำนวนรับ'];
      case 'back_order_summary':
        return ['เลข PO', 'ผู้จัดจำหน่าย', 'สินค้า', 'จำนวนค้าง', 'สถานะ', 'กำหนดส่ง'];
      case 'price_variance':
        return ['สินค้า', 'ผู้จัดจำหน่าย', 'ราคา/หน่วย', 'วันที่'];
      case 'supplier_performance':
        return ['ผู้จัดจำหน่าย', 'จำนวน PO', 'ยอดรวม', 'จำนวน GR', 'Back Order', 'Lead Time (วัน)'];
      default:
        return ['ข้อมูล'];
    }
  }

  List<DataCell> _getCellsForReport(String type, Map<String, dynamic> row) {
    switch (type) {
      case 'po_summary':
        return [
          DataCell(Text(row['po_number']?.toString() ?? '-')),
          DataCell(Text(row['supplier_name']?.toString() ?? '-')),
          DataCell(Text(row['status']?.toString() ?? '-')),
          DataCell(Text('฿${(row['grand_total'] as num?)?.toStringAsFixed(2) ?? '0.00'}')),
          DataCell(Text(row['created_at']?.toString().split('T')[0] ?? '-')),
        ];
      case 'gr_summary':
        return [
          DataCell(Text(row['gr_number']?.toString() ?? '-')),
          DataCell(Text(row['po_number']?.toString() ?? '-')),
          DataCell(Text(row['supplier_name']?.toString() ?? '-')),
          DataCell(Text(row['receipt_date']?.toString().split('T')[0] ?? '-')),
          DataCell(Text('${row['total_accepted'] ?? 0}')),
        ];
      case 'back_order_summary':
        return [
          DataCell(Text(row['po_number']?.toString() ?? '-')),
          DataCell(Text(row['supplier_name']?.toString() ?? '-')),
          DataCell(Text(row['product_name']?.toString() ?? '-')),
          DataCell(Text('${row['quantity_remaining'] ?? 0}')),
          DataCell(Text(row['status']?.toString() ?? '-')),
          DataCell(Text(row['expected_delivery_date']?.toString().split('T')[0] ?? '-')),
        ];
      case 'price_variance':
        return [
          DataCell(Text(row['product_name']?.toString() ?? '-')),
          DataCell(Text(row['supplier_name']?.toString() ?? '-')),
          DataCell(Text('฿${(row['unit_price'] as num?)?.toStringAsFixed(2) ?? '0.00'}')),
          DataCell(Text(row['effective_date']?.toString().split('T')[0] ?? '-')),
        ];
      case 'supplier_performance':
        return [
          DataCell(Text(row['supplier_name']?.toString() ?? '-')),
          DataCell(Text('${row['po_count'] ?? 0}')),
          DataCell(Text('฿${(row['total_amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}')),
          DataCell(Text('${row['gr_count'] ?? 0}')),
          DataCell(Text('${row['bo_count'] ?? 0}')),
          DataCell(Text('${row['lead_time_days'] ?? 0}')),
        ];
      default:
        return [DataCell(Text(row.toString()))];
    }
  }
}
