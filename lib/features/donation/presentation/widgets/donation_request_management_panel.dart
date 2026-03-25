import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/repositories/donation_repository.dart';
import '../../models/donation_models.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/thai_buddhist_date_picker.dart';
import '../../../../shared/widgets/thai_address_picker/thai_address_picker.dart';

class DonationRequestManagementPanel extends StatefulWidget {
  final DonationRepository repository;
  final String? userId; // If provided, only show requests for this user
  /// ถ้า false จะซ่อนปุ่ม "สร้างใหม่" (เมื่อฝังใน Profile tab แทนหน้า dashboard)
  final bool showCreateButton;
  
  const DonationRequestManagementPanel({
    super.key, 
    required this.repository,
    this.userId,
    this.showCreateButton = true,
  });

  @override
  State<DonationRequestManagementPanel> createState() => _DonationRequestManagementPanelState();
}

class _DonationRequestManagementPanelState extends State<DonationRequestManagementPanel> {
  List<DonationRequest> _requests = [];
  List<DonationCategory> _categories = [];
  List<Map<String, dynamic>> _communities = [];
  
  // Approvals tracker
  Map<String, int> _approvedCounts = {}; // req.id -> count

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant DonationRequestManagementPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userId != oldWidget.userId) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        widget.repository.getRequests(userId: widget.userId, bypassStatusFilter: true),
        widget.repository.getCategories(),
        widget.repository.getCommunities(),
      ]);
      
      final reqs = results[0] as List<DonationRequest>;
      final cats = results[1] as List<DonationCategory>;
      final comms = results[2] as List<Map<String, dynamic>>;

      // Fetch approvals for progress tracking
      final reqIds = reqs.map((e) => e.id).toList();
      Map<String, int> counts = {};
      if (reqIds.isNotEmpty) {
        final apprResp = await Supabase.instance.client
           .from('donation_request_approvals')
           .select('request_id')
           .inFilter('request_id', reqIds)
           .eq('status', 'approved');
        
        for (var row in (apprResp as List)) {
          final rid = row['request_id'].toString();
          counts[rid] = (counts[rid] ?? 0) + 1;
        }
      }

      if (mounted) {
        setState(() {
          _requests = reqs;
          _categories = cats;
          _communities = comms;
          _approvedCounts = counts;
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
      
      final reqIds = reqs.map((e) => e.id).toList();
      Map<String, int> counts = {};
      if (reqIds.isNotEmpty) {
        final apprResp = await Supabase.instance.client
           .from('donation_request_approvals')
           .select('request_id')
           .inFilter('request_id', reqIds)
           .eq('status', 'approved');
        
        for (var row in (apprResp as List)) {
          final rid = row['request_id'].toString();
          counts[rid] = (counts[rid] ?? 0) + 1;
        }
      }

      if (mounted) {
        setState(() {
          _requests = reqs;
          _approvedCounts = counts;
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

    DateTime? selectedNeededDate = request?.neededDate;
    String? selectedCategoryId = request?.categoryId ?? (_categories.isNotEmpty ? _categories.first.id : null);
    String? selectedCommunityId = request?.communityId;
    bool isTrending = request?.isTrending ?? false;
    // ที่อยู่ผู้ร้องขอ — ใช้ ThaiAddress แทน controller
    // parse จากข้อมูลเดิมเพื่อแสดงให้ถูกต้องใน summary text (initialAddress ใช้ไม่ได้เพราะไม่มี postal code)
    ThaiAddress? selectedRequesterAddress;
    bool addressError = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(request == null ? 'เพิ่มคำร้องใหม่' : 'แก้ไขคำร้อง', style: AppTextStyles.heading3),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(controller: titleController, decoration: InputDecoration(labelText: 'ชื่อเรื่อง', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedCategoryId,
                    decoration: InputDecoration(labelText: 'หมวดหมู่', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                    onChanged: (val) => setModalState(() => selectedCategoryId = val),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedCommunityId,
                    decoration: InputDecoration(labelText: 'ชุมชน/พื้นที่', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    items: _communities.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'] ?? 'ไม่ทราบชื่อ'))).toList(),
                    onChanged: (val) => setModalState(() => selectedCommunityId = val),
                  ),
                  const SizedBox(height: 16),
                  TextField(controller: descController, decoration: InputDecoration(labelText: 'รายละเอียด', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), maxLines: 3),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: targetController, decoration: InputDecoration(labelText: 'ยอดที่ต้องการ', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), keyboardType: TextInputType.number)),
                      const SizedBox(width: 16),
                      Expanded(child: TextField(controller: currentController, decoration: InputDecoration(labelText: 'ยอดปัจจุบัน', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), keyboardType: TextInputType.number)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('ข้อมูลเพิ่มเติม', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 16)),
                  const SizedBox(height: 16),
                  TextField(controller: usageLocationController, decoration: InputDecoration(labelText: 'สถานที่ใช้ความช่วยเหลือ', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                  const SizedBox(height: 16),
                  
                  // ── ที่อยู่ผู้ร้องขอ — ThaiAddressPicker ──
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ที่อยู่ผู้ร้องขอ',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: addressError ? Colors.redAccent : Colors.grey.shade300,
                            width: 1.5,
                          ),
                        ),
                        child: ThaiAddressPicker(
                          initialAddress: selectedRequesterAddress,
                          onAddressSelected: (address) {
                            setModalState(() {
                              selectedRequesterAddress = address;
                              addressError = false;
                            });
                          },
                        ),
                      ),
                      if (addressError)
                        const Padding(
                          padding: EdgeInsets.only(left: 4, top: 4),
                          child: Text('กรุณาระบุที่อยู่ผู้ร้องขอ', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ThaiBuddhistDatePickerField(
                    value: selectedNeededDate,
                    label: 'วันที่จำเป็นต้องใช้',
                    hint: 'เลือกวันที่จำเป็นต้องใช้',
                    onDateSelected: (date) => setModalState(() => selectedNeededDate = date),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('กำลังยอดนิยม?', style: TextStyle(fontWeight: FontWeight.bold)),
                    value: isTrending,
                    activeThumbColor: Colors.orange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    tileColor: Colors.orange.withValues(alpha: 0.1),
                    onChanged: (val) => setModalState(() => isTrending = val),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
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
                          'requester_address': selectedRequesterAddress?.fullAddress ?? '',
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
                          _loadRequests();
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
                        }
                      },
                      child: const Text('บันทึก', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildRequestCard(DonationRequest req, DonationCategory? cat) {
    final requiredApprovals = cat?.approverProfessionIds.length ?? 0;
    final currentApprovals = _approvedCounts[req.id] ?? 0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(req.title, style: AppTextStyles.heading3, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (req.isTrending) 
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4)),
                    child: const Row(
                      children: [
                        Icon(Icons.local_fire_department, size: 14, color: Colors.orange),
                        SizedBox(width: 4),
                        Text('ยอดฮิต', style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            
            if (requiredApprovals > 0 && req.approvalStatus == DonationApprovalStatus.pending_local) ...[
              const Text('สถานะการอนุมัติ:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Row(
                children: List.generate(requiredApprovals, (index) {
                  final isColor = index < currentApprovals;
                  return Expanded(
                    child: Container(
                      height: 6,
                      margin: EdgeInsets.only(right: index == requiredApprovals - 1 ? 0 : 4),
                      decoration: BoxDecoration(
                        color: isColor ? Colors.deepPurple : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 6),
              Text('ผ่านแล้ว $currentApprovals / $requiredApprovals หมวดหมู่อาชีพ', style: const TextStyle(fontSize: 11, color: Colors.deepPurple, fontWeight: FontWeight.bold)),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(req.approvalStatus).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _getStatusLabel(req.approvalStatus),
                  style: TextStyle(color: _getStatusColor(req.approvalStatus), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('เป้าหมาย', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    Text('${req.targetAmount?.toInt() ?? 0} บาท', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('ได้รับแล้ว', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    Text('${req.currentAmount.toInt()} บาท', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: req.progress, 
                minHeight: 6,
                color: AppColors.primary,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              ),
            ),
            
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit, size: 16), 
                  label: const Text('แก้ไข'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    side: const BorderSide(color: Colors.blue),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  ),
                  onPressed: () => _showRequestDialog(req),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete, size: 16), 
                  label: const Text('ลบ'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  ),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('ยืนยันลบคำร้อง', style: TextStyle(color: Colors.red)),
                        content: const Text('คุณแน่ใจหรือไม่ว่าต้องการลบคำร้องขอนี้? ข้อมูลจะไม่สามารถกู้คืนได้'),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            onPressed: () => Navigator.pop(context, true), 
                            child: const Text('ยืนยันลบ')
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await widget.repository.deleteRequest(req.id);
                      _loadRequests();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.showCreateButton
                      ? 'รายการคำร้องขอของคุณ'
                      : 'คำร้องขอของคุณ',
                  style: AppTextStyles.heading3.copyWith(color: AppColors.primary),
                ),
                if (!widget.showCreateButton)
                  Text(
                    'คำร้องที่ส่งแล้ว รอสถานะจากกลุ่มอาชีพ',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
            if (widget.showCreateButton)
              ElevatedButton.icon(
                onPressed: () => _showRequestDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('สร้างใหม่', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        
        if (_requests.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(Icons.assignment_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text('ไม่มีรายการคำร้องขอ', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _requests.length,
            itemBuilder: (context, index) {
              final req = _requests[index];
              final cat = _categories.where((c) => c.id == req.categoryId).firstOrNull;
              return _buildRequestCard(req, cat);
            },
          ),
          
        const SizedBox(height: 32),
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
      case DonationApprovalStatus.pending_local: return 'รอการอนุมัติจากหมวดหมู่';
      case DonationApprovalStatus.pending_storage: return 'รอคลังสินค้าตรวจสอบ';
      case DonationApprovalStatus.active: return 'อนุมัติแล้ว (รับบริจาคได้)';
      case DonationApprovalStatus.rejected: return 'ถูกปฏิเสธ';
    }
  }
}
