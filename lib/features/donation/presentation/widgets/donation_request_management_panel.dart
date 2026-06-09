import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/websocket_service.dart';
import '../../data/repositories/donation_repository.dart';
import '../../models/donation_models.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/thai_buddhist_date_picker.dart';
import '../../../../shared/widgets/thai_address_picker/thai_address_picker.dart';
import '../pages/donation_create_page.dart';
import 'donation_approval_history_widget.dart';

class DonationRequestManagementPanel extends StatefulWidget {
  final DonationRepository repository;
  final String? userId; // If provided, only show requests for this user
  /// ถ้า false จะซ่อนปุ่ม "สร้างใหม่" (เมื่อฝังใน Profile tab แทนหน้า dashboard)
  final bool showCreateButton;
  
  /// จำกัดความสูงสูงสุด และให้ภายใน Scroll ได้ (ถ้ามีค่า)
  final double? maxHeight;
  
  /// ID ของคำร้องที่ต้องการให้ Focus หรือเปิดประวัติการอนุมัติไว้ตอนเริ่มต้น
  final String? highlightRequestId;
  
  const DonationRequestManagementPanel({
    super.key, 
    required this.repository,
    this.userId,
    this.showCreateButton = true,
    this.maxHeight,
    this.highlightRequestId,
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
  // Expanded History tracking
  String? _expandedHistoryId; // id ของคำร้องที่กำลังดู History

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _expandedHistoryId = widget.highlightRequestId;
    _loadData();
  }

  @override
  void didUpdateWidget(covariant DonationRequestManagementPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userId != oldWidget.userId) {
      _loadData();
    }
    if (widget.highlightRequestId != oldWidget.highlightRequestId) {
      setState(() => _expandedHistoryId = widget.highlightRequestId);
      // รีโหลดรายการเมื่อมี highlightRequestId ใหม่ (เช่นหลังจากสร้างคำร้องใหม่)
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('DonationRequestManagementPanel._loadData: userId=${widget.userId}');
      final results = await Future.wait([
        widget.repository.getRequests(userId: widget.userId, bypassStatusFilter: true),
        widget.repository.getCategories(),
        widget.repository.getCommunities(),
      ]);

      final reqs = results[0] as List<DonationRequest>;
      final cats = results[1] as List<DonationCategory>;
      final comms = results[2] as List<Map<String, dynamic>>;

      debugPrint('DonationRequestManagementPanel._loadData: loaded ${reqs.length} requests, ${cats.length} categories');

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
      debugPrint('DonationRequestManagementPanel._loadData error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('DonationRequestManagementPanel._loadRequests: userId=${widget.userId}');
      final reqs = await widget.repository.getRequests(userId: widget.userId, bypassStatusFilter: true);
      debugPrint('DonationRequestManagementPanel._loadRequests: loaded ${reqs.length} requests');

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
      debugPrint('DonationRequestManagementPanel._loadRequests error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showRequestDialog([DonationRequest? request]) {
    if (request != null && request.approvalStatus != DonationApprovalStatus.pending_local) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('แก้ไขได้เฉพาะคำร้องที่ยังรออนุมัติเท่านั้น')),
      );
      return;
    }

    final titleController = TextEditingController(text: request?.title);
    final descController = TextEditingController(text: request?.description);
    final targetController = TextEditingController(text: request?.targetAmount?.toString());
    final usageLocationController = TextEditingController(text: request?.usageLocation);

    DateTime? selectedNeededDate = request?.neededDate;
    String? selectedCategoryId = request?.categoryId ?? (_categories.isNotEmpty ? _categories.first.id : null);
    String? selectedCommunityId = request?.communityId;
    bool isTrending = request?.isTrending ?? false;
    final existingRequesterAddress = request?.requesterAddress;
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
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('ข้อมูลเพิ่มเติม', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 16)),
                  const SizedBox(height: 16),
                  TextField(controller: usageLocationController, decoration: InputDecoration(labelText: 'สถานที่ใช้ความช่วยเหลือ', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                  const SizedBox(height: 16),

                  if (existingRequesterAddress != null && existingRequesterAddress.isNotEmpty) ...[
                    Text('ที่อยู่ปัจจุบัน', style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(existingRequesterAddress, style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
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
                    tileColor: Colors.orange.withOpacity(0.1),
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
                          'usage_location': usageLocationController.text,
                          'requester_address': selectedRequesterAddress?.fullAddress ?? existingRequesterAddress ?? '',
                          'needed_date': selectedNeededDate?.toIso8601String(),
                          'is_trending': isTrending,
                          if (request == null) 'current_amount': 0.0,
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


  String _formatThaiDate(DateTime date) {
    final months = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
    final d = date;
    return '${d.day} ${months[d.month - 1]} ${d.year + 543}';
  }

  void _showRequestDetail(DonationRequest req, DonationCategory? cat) {
    final requiredApprovals = cat?.approverProfessionIds.length ?? 0;
    final currentApprovals = _approvedCounts[req.id] ?? 0;
    final statusColor = _getStatusColor(req.approvalStatus);
    final statusLabel = _getStatusLabel(req.approvalStatus);
    final target = req.targetAmount ?? 0;
    final current = req.currentAmount;
    final progressPercent = target > 0 ? (current / target * 100).toInt() : 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(req.title, style: AppTextStyles.heading3.copyWith(fontSize: 18)),
                          const SizedBox(height: 4),
                          Text(
                            'สร้างเมื่อ ${_formatThaiDate(req.createdAt)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // ── Body ──
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badges row
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              cat?.name ?? 'ไม่ระบุหมวดหมู่',
                              style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: statusColor.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_getStatusIcon(req.approvalStatus), size: 14, color: statusColor),
                                const SizedBox(width: 4),
                                Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          if (req.isTrending)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(20)),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.local_fire_department, size: 14, color: Colors.orange),
                                  SizedBox(width: 4),
                                  Text('ยอดฮิต', style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // ── Description ──
                      if (req.description != null && req.description!.isNotEmpty)
                        _buildDetailSection(
                          icon: Icons.description_outlined,
                          title: 'รายละเอียด',
                          child: Text(req.description!, style: const TextStyle(fontSize: 14, height: 1.5)),
                        ),

                      // ── Money ──
                      _buildDetailSection(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'ยอดเงิน',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildDetailItem('เป้าหมาย', '${NumberFormat('#,###').format(target.toInt())} บาท'),
                                _buildDetailItem('ได้รับแล้ว', '${NumberFormat('#,###').format(current.toInt())} บาท', valueColor: AppColors.primary),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: req.progress,
                                minHeight: 10,
                                color: AppColors.primary,
                                backgroundColor: AppColors.primary.withOpacity(0.1),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('$progressPercent% ของเป้าหมาย', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),

                      // ── Approval progress ──
                      if (requiredApprovals > 0 && req.approvalStatus == DonationApprovalStatus.pending_local)
                        _buildDetailSection(
                          icon: Icons.how_to_vote_outlined,
                          title: 'สถานะการอนุมัติ',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ผ่านแล้ว $currentApprovals / $requiredApprovals หมวดหมู่อาชีพ', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Row(
                                children: List.generate(requiredApprovals, (index) {
                                  final isApproved = index < currentApprovals;
                                  return Expanded(
                                    child: Container(
                                      height: 8,
                                      margin: EdgeInsets.only(right: index == requiredApprovals - 1 ? 0 : 4),
                                      decoration: BoxDecoration(
                                        color: isApproved ? Colors.deepPurple : Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),

                      // ── Location ──
                      if (req.usageLocation != null && req.usageLocation!.isNotEmpty)
                        _buildDetailSection(
                          icon: Icons.location_on_outlined,
                          title: 'สถานที่ใช้ความช่วยเหลือ',
                          child: Text(req.usageLocation!, style: const TextStyle(fontSize: 14)),
                        ),

                      // ── Requester address ──
                      if (req.requesterAddress != null && req.requesterAddress!.isNotEmpty)
                        _buildDetailSection(
                          icon: Icons.home_outlined,
                          title: 'ที่อยู่ผู้ร้องขอ',
                          child: Text(req.requesterAddress!, style: const TextStyle(fontSize: 14)),
                        ),

                      // ── Needed date ──
                      if (req.neededDate != null)
                        _buildDetailSection(
                          icon: Icons.event_outlined,
                          title: 'วันที่จำเป็นต้องใช้',
                          child: Text(_formatThaiDate(req.neededDate!), style: const TextStyle(fontSize: 14)),
                        ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCloseDialog(DonationRequest req) {
    final reasonController = TextEditingController();
    String selectedReason = 'ได้รับความช่วยเหลือพอแล้ว';
    final reasons = [
      'ได้รับความช่วยเหลือพอแล้ว',
      'ครบตามเป้าหมายแล้ว',
      'อื่น ๆ',
    ];

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
                      Text('ปิดรับบริจาค', style: AppTextStyles.heading3),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'คำร้อง: ${req.title}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ยอดที่ได้รับ: ${NumberFormat('#,###').format(req.currentAmount.toInt())} บาท',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 20),
                  const Text('เหตุผลการปิดรับ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...reasons.map((r) => RadioListTile<String>(
                    title: Text(r, style: const TextStyle(fontSize: 14)),
                    value: r,
                    groupValue: selectedReason,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setModalState(() => selectedReason = val!),
                  )),
                  if (selectedReason == 'อื่น ๆ') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonController,
                      decoration: InputDecoration(
                        hintText: 'ระบุเหตุผล',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      maxLines: 2,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0066CC),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () async {
                        final reason = selectedReason == 'อื่น ๆ'
                            ? (reasonController.text.isEmpty ? 'อื่น ๆ' : reasonController.text)
                            : selectedReason;
                        try {
                          await widget.repository.closeRequest(req.id, reason: reason);
                          // แจ้งผู้ดูไลฟ์ว่าปิดรับแล้ว
                          if (req.videoId != null) {
                            WebSocketService().socket?.emit('donation-closed', {
                              'videoId': req.videoId,
                              'requestId': req.id,
                              'title': req.title,
                              'currentAmount': req.currentAmount,
                              'reason': reason,
                            });
                          }
                          if (mounted) Navigator.pop(context);
                          _loadRequests();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('ปิดรับบริจาคเรียบร้อย'))
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('เกิดข้อผิดพลาด: $e'))
                            );
                          }
                        }
                      },
                      child: const Text('ยืนยันปิดรับ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection({required IconData icon, required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
            ],
          ),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.only(left: 26), child: child),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: valueColor ?? Colors.black87)),
      ],
    );
  }

  Widget _buildRequestCard(DonationRequest req, DonationCategory? cat) {
    final requiredApprovals = cat?.approverProfessionIds.length ?? 0;
    final currentApprovals = _approvedCounts[req.id] ?? 0;
    final statusColor = _getStatusColor(req.approvalStatus);
    final statusLabel = _getStatusLabel(req.approvalStatus);
    final target = req.targetAmount ?? 0;
    final current = req.currentAmount;
    final progressPercent = target > 0 ? (current / target * 100).toInt() : 0;
    final canEdit = req.approvalStatus == DonationApprovalStatus.pending_local;

    return InkWell(
      onTap: () => _showRequestDetail(req, cat),
      borderRadius: BorderRadius.circular(16),
      child: Card(
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
            // ── Top Row: Category badge + Status badge ──
            Row(
              children: [
                // Category badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    cat?.name ?? 'ไม่ระบุหมวดหมู่',
                    style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getStatusIcon(req.approvalStatus), size: 12, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (req.isTrending) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(20)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_fire_department, size: 12, color: Colors.orange),
                        SizedBox(width: 2),
                        Text('ยอดฮิต', style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 12),

            // ── Title ──
            Text(req.title, style: AppTextStyles.heading3.copyWith(fontSize: 16)),

            // ── Description (if any) ──
            if (req.description != null && req.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                req.description!,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // ── Date ──
            const SizedBox(height: 8),
            Text(
              'สร้างเมื่อ ${_formatThaiDate(req.createdAt)}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // ── Approval Progress (if pending with required approvals) ──
            if (requiredApprovals > 0 && req.approvalStatus == DonationApprovalStatus.pending_local) ...[
              Row(
                children: [
                  const Icon(Icons.how_to_vote, size: 14, color: Colors.deepPurple),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'ผ่านแล้ว $currentApprovals / $requiredApprovals หมวดหมู่อาชีพ',
                      style: const TextStyle(fontSize: 12, color: Colors.deepPurple, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(requiredApprovals, (index) {
                  final isApproved = index < currentApprovals;
                  return Expanded(
                    child: Container(
                      height: 6,
                      margin: EdgeInsets.only(right: index == requiredApprovals - 1 ? 0 : 4),
                      decoration: BoxDecoration(
                        color: isApproved ? Colors.deepPurple : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
            ],

            // ── Money Progress ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'เป้าหมาย ${NumberFormat('#,###').format(target.toInt())} บาท',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                Text(
                  '${NumberFormat('#,###').format(current.toInt())} บาท ($progressPercent%)',
                  style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: req.progress,
                minHeight: 8,
                color: AppColors.primary,
                backgroundColor: AppColors.primary.withOpacity(0.1),
              ),
            ),

            const SizedBox(height: 12),

            // ── Approval History Toggle ──
            GestureDetector(
              onTap: () {
                setState(() {
                  _expandedHistoryId = _expandedHistoryId == req.id ? null : req.id;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.deepPurple.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history_edu, size: 14, color: Colors.deepPurple),
                    const SizedBox(width: 6),
                    Text(
                      _expandedHistoryId == req.id ? 'ซ่อนประวัติอนุมัติ' : 'ดูประวัติการอนุมัติ',
                      style: const TextStyle(fontSize: 12, color: Colors.deepPurple, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expandedHistoryId == req.id ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: Colors.deepPurple,
                    ),
                  ],
                ),
              ),
            ),

            // ── Approval History Timeline ──
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              crossFadeState: _expandedHistoryId == req.id
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: DonationApprovalHistoryWidget(
                  requestId: req.id,
                  repository: widget.repository,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Bottom Actions ──
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (req.approvalStatus == DonationApprovalStatus.completed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0066CC).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF0066CC).withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified, size: 14, color: Color(0xFF0066CC)),
                        SizedBox(width: 4),
                        Text('ปิดรับบริจาคแล้ว', style: TextStyle(fontSize: 10, color: Color(0xFF0066CC))),
                      ],
                    ),
                  )
                else if (req.approvalStatus == DonationApprovalStatus.active && req.currentAmount > 0) ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle, size: 16),
                    label: const Text('ปิดรับ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0066CC),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _showCloseDialog(req),
                  ),
                ] else if (req.approvalStatus == DonationApprovalStatus.active && req.currentAmount == 0) ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('ยกเลิก'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('ยืนยันการยกเลิก'),
                          content: const Text('คุณแน่ใจหรือไม่ว่าต้องการยกเลิกคำร้องขอนี้?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ปิด')),
                            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('ยืนยัน')),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await widget.repository.cancelRequest(req.id);
                        _loadRequests();
                      }
                    },
                  ),
                ] else if (canEdit) ...[
                  TextButton.icon(
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('แก้ไข'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => _showRequestDialog(req),
                  ),
                  _buildOverflowMenu(req),
                ] else if (req.approvalStatus == DonationApprovalStatus.cancelled)
                  const SizedBox.shrink(),
              ],
            ),
            if (req.approvalStatus != DonationApprovalStatus.pending_local) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueGrey.withOpacity(0.12)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: req.approvalStatus == DonationApprovalStatus.active
                          ? 'เมื่อคำร้องเริ่มเปิดรับบริจาคแล้ว ระบบจะล็อกการแก้ไข เพื่อให้ข้อมูลที่ผู้บริจาคเห็นตรงกับคำร้องที่อนุมัติ'
                          : req.approvalStatus == DonationApprovalStatus.completed
                              ? 'ปิดรับแล้ว จึงไม่สามารถแก้ไขรายละเอียดได้'
                              : 'คำร้องนี้ไม่อยู่ในสถานะที่สามารถแก้ไขรายละเอียดได้',
                      child: const Icon(Icons.info_outline, size: 16, color: Colors.blueGrey),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        req.approvalStatus == DonationApprovalStatus.active
                            ? 'เริ่มเปิดรับแล้ว: ปุ่มแก้ไขจะหายไปเพื่อรักษาความโปร่งใสต่อผู้บริจาค'
                            : req.approvalStatus == DonationApprovalStatus.completed
                                ? 'ปิดรับแล้ว: รายละเอียดถูกล็อกและไม่สามารถแก้ไขได้'
                                : 'คำร้องนี้ถูกล็อกไม่ให้แก้ไขรายละเอียด',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  }

  IconData _getStatusIcon(DonationApprovalStatus status) {
    switch (status) {
      case DonationApprovalStatus.pending_local: return Icons.hourglass_top;
      case DonationApprovalStatus.active: return Icons.check_circle;
      case DonationApprovalStatus.rejected: return Icons.cancel;
      case DonationApprovalStatus.cancelled: return Icons.delete_outline;
      case DonationApprovalStatus.completed: return Icons.verified;
    }
  }

  Widget _buildOverflowMenu(DonationRequest req) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
      padding: EdgeInsets.zero,
      onSelected: (value) async {
        switch (value) {
          case 'cancel':
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('ยืนยันการยกเลิก'),
                content: const Text('คุณแน่ใจหรือไม่ว่าต้องการยกเลิกคำร้องขอนี้? คำร้องจะไม่ออกแสดงสู่สาธารณะ'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ปิด', style: TextStyle(color: Colors.grey))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('ยืนยันยกเลิก'),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              await widget.repository.cancelRequest(req.id);
              _loadRequests();
            }
            break;
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];
        if (req.approvalStatus == DonationApprovalStatus.pending_local) {
          items.add(
            const PopupMenuItem(value: 'cancel', child: Row(children: [Icon(Icons.cancel_outlined, size: 18, color: Colors.orange), SizedBox(width: 8), Text('ยกเลิก')])),
          );
        }
        return items;
      },
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
                      ? 'ขอรับบริจาค'
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
            Row(
              children: [
                // ปุ่มรีเฟรชรายการ
                IconButton(
                  onPressed: _loadRequests,
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'รีเฟรชรายการ',
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const DonationCreatePage()),
                  ).then((result) {
                    // รีโหลดเสมอหลังจากกลับมา แม้ create page จะใช้ pushNamedAndRemoveUntil
                    _loadRequests();
                  }),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('ขอ', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
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
                Text('ยังไม่ได้ขอรับบริจาค', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
              ],
            ),
          )
        else
          widget.maxHeight != null
              ? ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: widget.maxHeight!),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _requests.length,
                      itemBuilder: (context, index) {
                        final req = _requests[index];
                        final cat = _categories.where((c) => c.id == req.categoryId).firstOrNull;
                        return _buildRequestCard(req, cat);
                      },
                    ),
                  ),
                )
              : ListView.builder(
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
      case DonationApprovalStatus.active: return Colors.green;
      case DonationApprovalStatus.rejected: return Colors.red;
      case DonationApprovalStatus.cancelled: return Colors.grey;
      case DonationApprovalStatus.completed: return const Color(0xFF0066CC);
    }
  }

  String _getStatusLabel(DonationApprovalStatus status) {
    switch (status) {
      case DonationApprovalStatus.pending_local: return 'รอการอนุมัติจากหมวดหมู่';
      case DonationApprovalStatus.active: return 'อนุมัติแล้ว (รับบริจาคได้)';
      case DonationApprovalStatus.rejected: return 'ถูกปฏิเสธ';
      case DonationApprovalStatus.cancelled: return 'ยกเลิกคำร้องแล้ว';
      case DonationApprovalStatus.completed: return 'ปิดรับบริจาคแล้ว';
    }
  }
}
