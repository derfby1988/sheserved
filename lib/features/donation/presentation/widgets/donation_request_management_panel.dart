import 'package:flutter/material.dart';
import '../../data/repositories/donation_repository.dart';
import '../../models/donation_models.dart';
import '../../../../core/constants/app_colors.dart';

class DonationRequestManagementPanel extends StatefulWidget {
  final DonationRepository repository;
  final String? userId; // If provided, only show requests for this user
  
  const DonationRequestManagementPanel({
    super.key, 
    required this.repository,
    this.userId,
  });

  @override
  State<DonationRequestManagementPanel> createState() => _DonationRequestManagementPanelState();
}

class _DonationRequestManagementPanelState extends State<DonationRequestManagementPanel> {
  List<DonationRequest> _requests = [];
  List<DonationCategory> _categories = [];
  List<Map<String, dynamic>> _communities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        widget.repository.getRequests(userId: widget.userId, bypassStatusFilter: true),
        widget.repository.getCategories(),
        widget.repository.getCommunities(),
      ]);
      if (mounted) {
        setState(() {
          _requests = results[0] as List<DonationRequest>;
          _categories = results[1] as List<DonationCategory>;
          _communities = results[2] as List<Map<String, dynamic>>;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading donation management data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final reqs = await widget.repository.getRequests(userId: widget.userId, bypassStatusFilter: true);
      if (mounted) {
        setState(() {
          _requests = reqs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading requests: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showRequestDialog([DonationRequest? request]) {
    final titleController = TextEditingController(text: request?.title);
    final descController = TextEditingController(text: request?.description);
    final targetController = TextEditingController(text: request?.targetAmount?.toString());
    final currentController = TextEditingController(text: request?.currentAmount.toString());
    final usageLocationController = TextEditingController(text: request?.usageLocation);
    final requesterAddressController = TextEditingController(text: request?.requesterAddress);
    
    DateTime? selectedNeededDate = request?.neededDate;
    String? selectedCategoryId = request?.categoryId ?? (_categories.isNotEmpty ? _categories.first.id : null);
    String? selectedCommunityId = request?.communityId;
    bool isTrending = request?.isTrending ?? false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(request == null ? 'เพิ่มรายการใหม่' : 'แก้ไขรายการ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'ชื่อเรื่อง')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedCategoryId,
                  decoration: const InputDecoration(labelText: 'หมวดหมู่'),
                  items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (val) => setDialogState(() => selectedCategoryId = val),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedCommunityId,
                  decoration: const InputDecoration(labelText: 'ชุมชน/พื้นที่ (สำหรับผู้นำชุมชนยืนยัน)'),
                  items: _communities.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'] ?? 'ไม่ทราบชื่อ'))).toList(),
                  onChanged: (val) => setDialogState(() => selectedCommunityId = val),
                ),
                TextField(controller: descController, decoration: const InputDecoration(labelText: 'รายละเอียด (Description)'), maxLines: 3),
                TextField(controller: targetController, decoration: const InputDecoration(labelText: 'ยอดที่ต้องการ (เป้าหมาย)')),
                TextField(controller: currentController, decoration: const InputDecoration(labelText: 'ยอดที่ได้ปัจจุบัน')),
                const SizedBox(height: 16),
                const Align(alignment: Alignment.centerLeft, child: Text('ข้อมูลเพิ่มเติม (Step 2)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                TextField(controller: usageLocationController, decoration: const InputDecoration(labelText: 'สถานที่ใช้ความช่วยเหลือ')),
                TextField(controller: requesterAddressController, decoration: const InputDecoration(labelText: 'ที่อยู่ผู้ร้องขอ')),
                ListTile(
                  title: Text(selectedNeededDate == null ? 'เลือกวันที่จำเป็นต้องใช้' : 'ต้องใช้ภายใน: ${selectedNeededDate.toString().split(' ')[0]}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedNeededDate ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) setDialogState(() => selectedNeededDate = date);
                  },
                ),
                SwitchListTile(
                  title: const Text('กำลังยอดนิยม?'),
                  value: isTrending,
                  onChanged: (val) => setDialogState(() => isTrending = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
            TextButton(
              onPressed: () async {
                if (selectedCategoryId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาเลือกหมวดหมู่')));
                  return;
                }
                final data = {
                  'title': titleController.text,
                  'description': descController.text,
                  'category_id': selectedCategoryId,
                  'community_id': selectedCommunityId,
                  'target_amount': double.tryParse(targetController.text) ?? 0.0,
                  'current_amount': double.tryParse(currentController.text) ?? 0.0,
                  'usage_location': usageLocationController.text,
                  'requester_address': requesterAddressController.text,
                  'needed_date': selectedNeededDate?.toIso8601String(),
                  'is_trending': isTrending,
                  'status': 'active',
                  if (request == null && widget.userId != null) 'user_id': widget.userId,
                };
                try {
                  if (request == null) {
                    await widget.repository.createRequest(data);
                  } else {
                    await widget.repository.updateRequest(request.id, data);
                  }
                  if (mounted) Navigator.pop(context);
                  _loadData();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
                  }
                }
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: () => _showRequestDialog(),
            icon: const Icon(Icons.add),
            label: const Text('เพิ่มคำร้องใหม่'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : _requests.isEmpty 
              ? const Center(child: Text('ไม่มีรายการคำร้องขอ'))
              : ListView.builder(
                  itemCount: _requests.length,
                  itemBuilder: (context, index) {
                    final req = _requests[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(req.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Text('เป้าหมาย: ${req.targetAmount?.toInt() ?? 0} | ได้รับแล้ว: ${req.currentAmount.toInt()}',
                                 style: const TextStyle(fontSize: 13)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getStatusColor(req.approvalStatus).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _getStatusLabel(req.approvalStatus),
                                style: TextStyle(
                                  color: _getStatusColor(req.approvalStatus), 
                                  fontSize: 11, 
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: req.progress, 
                                minHeight: 6,
                                color: AppColors.primary,
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (req.isTrending) const Icon(Icons.trending_up, color: Colors.orange),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue), 
                              onPressed: () => _showRequestDialog(req),
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red), 
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('ยืนยัน'),
                                    content: const Text('ต้องการลบคำร้องขอนี้ใช่หรือไม่?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
                                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('ลบ', style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await widget.repository.deleteRequest(req.id);
                                  _loadRequests();
                                }
                              },
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Color _getStatusColor(DonationApprovalStatus status) {
    switch (status) {
      case DonationApprovalStatus.pending_local: return Colors.deepPurple;
      case DonationApprovalStatus.pending_storage: return Colors.orange;
      case DonationApprovalStatus.active: return Colors.green;
      case DonationApprovalStatus.rejected: return Colors.red;
    }
  }

  String _getStatusLabel(DonationApprovalStatus status) {
    switch (status) {
      case DonationApprovalStatus.pending_local: return 'รอผู้นำชุมชนยืนยัน';
      case DonationApprovalStatus.pending_storage: return 'รอตรวจสถานที่จัดเก็บ';
      case DonationApprovalStatus.active: return 'อนุมัติแล้ว';
      case DonationApprovalStatus.rejected: return 'ปฏิเสธ';
    }
  }
}
