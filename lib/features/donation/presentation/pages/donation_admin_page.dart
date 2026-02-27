import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../services/service_locator.dart';
import '../../data/repositories/donation_repository.dart';
import '../../models/donation_models.dart';

class DonationAdminPage extends StatefulWidget {
  const DonationAdminPage({super.key});

  @override
  State<DonationAdminPage> createState() => _DonationAdminPageState();
}

class _DonationAdminPageState extends State<DonationAdminPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DonationRepository _repository;
  String? _currentUserId;
  bool _isStorageAdmin = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _repository = DonationRepository(Supabase.instance.client);
    _loadUserContext();
  }

  Future<void> _loadUserContext() async {
    // ✅ ใช้ ServiceLocator ตาม Auth Data Guidelines (ห้ามใช้ Supabase Auth โดยตรง)
    final user = ServiceLocator.instance.currentUser;
    if (user != null) {
      setState(() {
        _currentUserId = user.id;
        // TODO: ตรวจสอบ role จาก public.users table แทน email
        _isStorageAdmin = true; // ชั่วคราว - ผู้ใช้ที่ login แล้วถือว่ามีสิทธิ
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 60),
        child: Container(
          color: AppColors.primary,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'จัดการระบบบริจาค',
                        style: AppTextStyles.heading3.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  isScrollable: true,
                  tabs: const [
                    Tab(text: 'หมวดหมู่'),
                    Tab(text: 'คำร้องขอ'),
                    Tab(text: 'ศูนย์อนุมัติ'),
                    Tab(text: 'ประวัติ'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _CategoryManagementPanel(repository: _repository),
          _RequestManagementPanel(repository: _repository),
          _ApprovalCenterPanel(repository: _repository, userId: _currentUserId, isStorageAdmin: _isStorageAdmin),
          _ContributionHistoryPanel(repository: _repository),
        ],
      ),
    );
  }
}

/// แผงจัดการหมวดหมู่
class _CategoryManagementPanel extends StatefulWidget {
  final DonationRepository repository;
  const _CategoryManagementPanel({required this.repository});

  @override
  State<_CategoryManagementPanel> createState() => _CategoryManagementPanelState();
}

class _CategoryManagementPanelState extends State<_CategoryManagementPanel> {
  List<DonationCategory> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    try {
      final cats = await widget.repository.getCategories();
      setState(() {
        _categories = cats;
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
    }
  }

  void _showCategoryDialog([DonationCategory? category]) {
    final nameController = TextEditingController(text: category?.name);
    final iconController = TextEditingController(text: category?.iconName);
    bool isEmergency = category?.isEmergency ?? false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(category == null ? 'เพิ่มหมวดหมู่' : 'แก้ไขหมวดหมู่'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'ชื่อหมวดหมู่')),
              TextField(controller: iconController, decoration: const InputDecoration(labelText: 'ชื่อไอคอน (Material/Slug)')),
              SwitchListTile(
                title: const Text('เป็นเหตุฉุกเฉิน?'),
                value: isEmergency,
                onChanged: (val) => setDialogState(() => isEmergency = val),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
            TextButton(
              onPressed: () async {
                final data = {
                  'name': nameController.text,
                  'icon_name': iconController.text,
                  'is_emergency': isEmergency,
                };
                if (category == null) {
                  await widget.repository.createCategory(data);
                } else {
                  await widget.repository.updateCategory(category.id, data);
                }
                if (mounted) Navigator.pop(context);
                _loadCategories();
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
            onPressed: () => _showCategoryDialog(),
            icon: const Icon(Icons.add),
            label: const Text('เพิ่มหมวดหมู่ใหม่'),
          ),
        ),
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cat.isEmergency ? Colors.red.shade100 : Colors.blue.shade100,
                        child: Icon(cat.isEmergency ? Icons.emergency : Icons.category, 
                                    color: cat.isEmergency ? Colors.red : Colors.blue),
                      ),
                      title: Text(cat.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit), onPressed: () => _showCategoryDialog(cat)),
                          IconButton(icon: const Icon(Icons.delete, color: Colors.red), 
                                     onPressed: () async {
                                       await widget.repository.deleteCategory(cat.id);
                                       _loadCategories();
                                     }),
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
}

/// แผงจัดการคำร้องขอ
class _RequestManagementPanel extends StatefulWidget {
  final DonationRepository repository;
  const _RequestManagementPanel({required this.repository});

  @override
  State<_RequestManagementPanel> createState() => _RequestManagementPanelState();
}

class _RequestManagementPanelState extends State<_RequestManagementPanel> {
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
    final results = await Future.wait([
      widget.repository.getRequests(),
      widget.repository.getCategories(),
      widget.repository.getCommunities(),
    ]);
    setState(() {
      _requests = results[0] as List<DonationRequest>;
      _categories = results[1] as List<DonationCategory>;
      _communities = results[2] as List<Map<String, dynamic>>;
      _isLoading = false;
    });
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    final reqs = await widget.repository.getRequests();
    setState(() {
      _requests = reqs;
      _isLoading = false;
    });
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
                  'status': 'active', // overall logical status
                };
                if (request == null) {
                  await widget.repository.createRequest(data);
                } else {
                  await widget.repository.updateRequest(request.id, data);
                }
                if (mounted) Navigator.pop(context);
                _loadData();
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
          ),
        ),
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: _requests.length,
                itemBuilder: (context, index) {
                  final req = _requests[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      title: Text(req.title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('เป้าหมาย: ${req.targetAmount?.toInt() ?? 0} | ได้รับแล้ว: ${req.currentAmount.toInt()}'),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getStatusColor(req.approvalStatus).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getStatusLabel(req.approvalStatus),
                              style: TextStyle(color: _getStatusColor(req.approvalStatus), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: req.progress, color: AppColors.primary),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (req.isTrending) const Icon(Icons.trending_up, color: Colors.orange),
                          IconButton(icon: const Icon(Icons.edit), onPressed: () => _showRequestDialog(req)),
                          IconButton(icon: const Icon(Icons.delete, color: Colors.red), 
                                     onPressed: () async {
                                       await widget.repository.deleteRequest(req.id);
                                       _loadRequests();
                                     }),
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

/// แผงศูนย์อนุมัติ (Approval Center)
class _ApprovalCenterPanel extends StatefulWidget {
  final DonationRepository repository;
  final String? userId;
  final bool isStorageAdmin;
  const _ApprovalCenterPanel({required this.repository, this.userId, required this.isStorageAdmin});

  @override
  State<_ApprovalCenterPanel> createState() => _ApprovalCenterPanelState();
}

class _ApprovalCenterPanelState extends State<_ApprovalCenterPanel> {
  List<DonationRequest> _pendingRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    if (widget.userId == null) return;
    setState(() => _isLoading = true);
    final reqs = await widget.repository.getPendingRequests(widget.userId!, isStorageAdmin: widget.isStorageAdmin);
    setState(() {
      _pendingRequests = reqs;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId == null) return const Center(child: Text('กรุณาเข้าสู่ระบบ'));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            widget.isStorageAdmin 
              ? 'รายการรอพิจารณาสถานที่จัดเก็บ' 
              : 'รายการรอพิจารณาที่คุณได้รับสิทธิ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : _pendingRequests.isEmpty
                ? const Center(child: Text('ไม่มีรายการรออนุมัติ'))
                : ListView.builder(
                    itemCount: _pendingRequests.length,
                    itemBuilder: (context, index) {
                      final req = _pendingRequests[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          title: Text(req.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('สถานะปัจจุบัน: ${_getStatusLabel(req.approvalStatus)}'),
                              if (req.approvalStatus == DonationApprovalStatus.pending_local) ...[
                                const SizedBox(height: 4),
                                Text('📍 สถานที่ใช้: ${req.usageLocation ?? "-"}', style: const TextStyle(fontSize: 12)),
                                Text('🏠 ที่อยู่ผู้ร้อง: ${req.requesterAddress ?? "-"}', style: const TextStyle(fontSize: 12)),
                              ],
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                                onPressed: () async {
                                  await widget.repository.approveRequest(req.id, req.approvalStatus, widget.userId!);
                                  _loadPending();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.red),
                                onPressed: () async {
                                  await widget.repository.rejectRequest(req.id);
                                  _loadPending();
                                },
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

  String _getStatusLabel(DonationApprovalStatus status) {
    switch (status) {
      case DonationApprovalStatus.pending_local: return 'รอผู้นำชุมชนยืนยัน';
      case DonationApprovalStatus.pending_storage: return 'รอตรวจสถานที่เก็บ';
      default: return 'อื่นๆ';
    }
  }
}


/// แผงประวัติการบริจาค
class _ContributionHistoryPanel extends StatefulWidget {
  final DonationRepository repository;
  const _ContributionHistoryPanel({required this.repository});

  @override
  State<_ContributionHistoryPanel> createState() => _ContributionHistoryPanelState();
}

class _ContributionHistoryPanelState extends State<_ContributionHistoryPanel> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final history = await widget.repository.getContributions();
      setState(() {
        _history = history;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return ListView.builder(
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final item = _history[index];
        final user = item['user'] as Map?;
        final request = item['request'] as Map?;
        return ListTile(
          leading: const Icon(Icons.history, color: Colors.green),
          title: Text('${user?['username'] ?? 'ไม่ระบุชื่อ'} บริจาค ${item['amount']} บาท'),
          subtitle: Text('ให้กับ: ${request?['title'] ?? 'ไม่ทราบรายการ'}'),
          trailing: Text(item['created_at'].toString().split('T')[0]),
        );
      },
    );
  }
}
