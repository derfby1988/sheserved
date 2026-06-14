import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../services/auth_service.dart';
import '../../data/models/drug_risk_classification_models.dart';
import '../../data/repositories/drug_risk_classification_repository.dart';

class DrugRiskClassificationAdminPage extends StatefulWidget {
  const DrugRiskClassificationAdminPage({super.key});

  @override
  State<DrugRiskClassificationAdminPage> createState() => _DrugRiskClassificationAdminPageState();
}

class _DrugRiskClassificationAdminPageState extends State<DrugRiskClassificationAdminPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DrugRiskClassificationRepository _repo;

  bool _isLoading = true;
  String? _error;

  // Tab 1 data
  List<DangerousDrugSubcategory> _subcategories = [];
  // Tab 2 data
  List<CustomRiskLevel> _riskLevels = [];
  // Tab 3 data
  List<Map<String, dynamic>> _searchResults = [];
  final TextEditingController _searchController = TextEditingController();
  // Tab 4 data
  List<MedicationRiskOverrideLog> _recentOverrides = [];
  int _customMedsWithoutRisk = 0;
  List<Map<String, dynamic>> _adminLogs = [];

  // Soft delete visibility
  bool _showDeletedSubcategories = false;
  bool _showDeletedRiskLevels = false;

  String get _currentUserId => AuthService.instance.currentUser?.id ?? 'unknown';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Rebuild for floatingActionButton visibility
    });
    _repo = DrugRiskClassificationRepository(Supabase.instance.client);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.removeListener(() {});
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await Future.wait([
        _loadSubcategories(),
        _loadRiskLevels(),
        _loadReports(),
      ]);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSubcategories() async {
    _subcategories = await _repo.getAllSubcategories(includeDeleted: _showDeletedSubcategories);
  }

  Future<void> _loadRiskLevels() async {
    _riskLevels = await _repo.getAllRiskLevels(includeDeleted: _showDeletedRiskLevels);
  }

  Future<void> _loadReports() async {
    _recentOverrides = await _repo.getRecentOverrides();
    _customMedsWithoutRisk = await _repo.getCustomMedicationsWithoutRiskLevel();
    _adminLogs = await _repo.getAdminLogs();
  }

  Future<void> _searchMedications(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final results = await _repo.searchMedications(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการหมวดหมู่ความเสี่ยงยา'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'reset_subcategories') {
                final inserted = await _repo.resetSubcategorySeed(performedBy: _currentUserId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('รีเซ็ตหมวดยาอันตราย: ${inserted.length} รายการ')),
                  );
                }
                _loadSubcategories();
                setState(() {});
              } else if (value == 'reset_risk_levels') {
                final inserted = await _repo.resetRiskLevelSeed(performedBy: _currentUserId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('รีเซ็ตระดับความเสี่ยง: ${inserted.length} รายการ')),
                  );
                }
                _loadRiskLevels();
                setState(() {});
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'reset_subcategories', child: Text('รีเซ็ตค่าเริ่มต้น: หมวดยาอันตราย')),
              const PopupMenuItem(value: 'reset_risk_levels', child: Text('รีเซ็ตค่าเริ่มต้น: ระดับความเสี่ยง')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.category_outlined, size: 20), text: 'หมวดยาอันตราย'),
            Tab(icon: Icon(Icons.scale_outlined, size: 20), text: 'ระดับความเสี่ยง'),
            Tab(icon: Icon(Icons.medical_services_outlined, size: 20), text: 'ตรวจสอบยา'),
            Tab(icon: Icon(Icons.bar_chart_outlined, size: 20), text: 'รายงาน'),
          ],
        ),
      ),
      body: _isLoading && _subcategories.isEmpty && _riskLevels.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSubcategoriesTab(),
                    _buildRiskLevelsTab(),
                    _buildMedicationReviewTab(),
                    _buildReportsTab(),
                  ],
                ),
      floatingActionButton: _tabController.index < 2
          ? FloatingActionButton(
              onPressed: () => _showAddDialog(_tabController.index),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  // ═══════════════════════════════════════════
  // TAB 1: Dangerous Drug Subcategories
  // ═══════════════════════════════════════════

  Widget _buildSubcategoriesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              FilterChip(
                label: Text(_showDeletedSubcategories ? 'ซ่อนรายการที่ลบ' : 'แสดงรายการที่ลบ'),
                selected: _showDeletedSubcategories,
                onSelected: (v) {
                  setState(() => _showDeletedSubcategories = v);
                  _loadSubcategories();
                  setState(() {});
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _subcategories.isEmpty
              ? const Center(child: Text('ไม่มีข้อมูลหมวดหมู่ยาอันตรายย่อย'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _subcategories.length,
                  itemBuilder: (context, index) {
                    final item = _subcategories[index];
                    return _buildSubcategoryCard(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSubcategoryCard(DangerousDrugSubcategory item) {
    final isDeleted = item.deletedAt != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDeleted ? Colors.grey.shade200 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isDeleted
                      ? Colors.grey.shade400
                      : (item.isTelemedicineProhibited ? Colors.red.shade100 : Colors.green.shade100),
                  child: Icon(
                    isDeleted ? Icons.delete_outline : (item.isTelemedicineProhibited ? Icons.block : Icons.check_circle),
                    color: isDeleted ? Colors.grey : (item.isTelemedicineProhibited ? Colors.red : Colors.green),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.nameTh,
                        style: AppTextStyles.bodyLarge.copyWith(
                          decoration: isDeleted ? TextDecoration.lineThrough : null,
                          color: isDeleted ? Colors.grey : null,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.code,
                        style: AppTextStyles.bodySmall.copyWith(fontFamily: 'monospace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.description!,
                          style: AppTextStyles.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildCardActions(
                  isDeleted: isDeleted,
                  onRestore: () => _reactivateSubcategory(item),
                  isActive: item.isActive,
                  onToggle: (v) => _toggleSubcategoryActive(item, v),
                  onEdit: () => _showEditSubcategoryDialog(item),
                  onDelete: () => _confirmDeleteSubcategory(item),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (isDeleted)
                  _buildStatusChip('ถูกลบ', Colors.red)
                else ...[
                  _buildStatusChip(
                    item.isTelemedicineProhibited ? 'ห้าม Telemedicine' : 'อนุญาต Telemedicine',
                    item.isTelemedicineProhibited ? Colors.red : Colors.green,
                  ),
                  if (!item.isActive) _buildStatusChip('ปิดใช้งาน', Colors.orange),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // TAB 2: Custom Risk Levels
  // ═══════════════════════════════════════════

  Widget _buildRiskLevelsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              FilterChip(
                label: Text(_showDeletedRiskLevels ? 'ซ่อนรายการที่ลบ' : 'แสดงรายการที่ลบ'),
                selected: _showDeletedRiskLevels,
                onSelected: (v) {
                  setState(() => _showDeletedRiskLevels = v);
                  _loadRiskLevels();
                  setState(() {});
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _riskLevels.isEmpty
              ? const Center(child: Text('ไม่มีข้อมูลระดับความเสี่ยง'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _riskLevels.length,
                  itemBuilder: (context, index) {
                    final item = _riskLevels[index];
                    return _buildRiskLevelCard(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRiskLevelCard(CustomRiskLevel item) {
    final isDeleted = item.deletedAt != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDeleted ? Colors.grey.shade200 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isDeleted ? Colors.grey.shade400 : _riskLevelColor(item.code),
                  child: Text(
                    isDeleted ? 'X' : item.code.toUpperCase(),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.nameTh,
                        style: AppTextStyles.bodyLarge.copyWith(
                          decoration: isDeleted ? TextDecoration.lineThrough : null,
                          color: isDeleted ? Colors.grey : null,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.code,
                        style: AppTextStyles.bodySmall.copyWith(fontFamily: 'monospace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.description!,
                          style: AppTextStyles.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildCardActions(
                  isDeleted: isDeleted,
                  onRestore: () => _reactivateRiskLevel(item),
                  isActive: item.isActive,
                  onToggle: (v) => _toggleRiskLevelActive(item, v),
                  onEdit: () => _showEditRiskLevelDialog(item),
                  onDelete: () => _confirmDeleteRiskLevel(item),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (isDeleted)
                  _buildStatusChip('ถูกลบ', Colors.red)
                else ...[
                  _buildStatusChip(
                    item.isTelemedicineProhibited ? 'ห้าม Telemedicine' : 'อนุญาต Telemedicine',
                    item.isTelemedicineProhibited ? Colors.red : Colors.green,
                  ),
                  if (!item.isActive) _buildStatusChip('ปิดใช้งาน', Colors.orange),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardActions({
    required bool isDeleted,
    required VoidCallback onRestore,
    required bool isActive,
    required ValueChanged<bool> onToggle,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    if (isDeleted) {
      return IconButton(
        icon: const Icon(Icons.restore, color: Colors.green),
        tooltip: 'คืนค่า',
        onPressed: onRestore,
        iconSize: 22,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 42,
          height: 32,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Switch(
              value: isActive,
              onChanged: onToggle,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit, size: 20),
          onPressed: onEdit,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
          onPressed: onDelete,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  Color _riskLevelColor(String code) {
    switch (code) {
      case 'low': return Colors.green.shade200;
      case 'medium': return Colors.yellow.shade200;
      case 'high': return Colors.orange.shade200;
      case 'very_high': return Colors.deepOrange.shade200;
      case 'prohibited': return Colors.red.shade200;
      default: return Colors.grey.shade200;
    }
  }

  // ═══════════════════════════════════════════
  // TAB 3: Medication Review & Override
  // ═══════════════════════════════════════════

  Widget _buildMedicationReviewTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'ค้นหาตามชื่อยา (Trade/Generic)...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  _searchMedications('');
                },
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: _searchMedications,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _searchResults.isEmpty
                ? const Center(child: Text('พิมพ์ชื่อยาเพื่อค้นหา'))
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final med = _searchResults[index];
                      return _buildMedicationCard(med);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationCard(Map<String, dynamic> med) {
    final fdaStatus = med['fda_risk_status'] as String?;
    final subCategory = med['dangerous_sub_category'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med['trade_name'] ?? 'ไม่ระบุชื่อ',
                        style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (med['generic_name'] != null)
                        Text('Generic: ${med['generic_name']}', style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
                _buildFdaStatusBadge(fdaStatus),
              ],
            ),
            const SizedBox(height: 8),
            if (subCategory != null)
              Text('Subcategory: $subCategory', style: AppTextStyles.bodySmall),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showOverrideDialog(med),
                  icon: const Icon(Icons.edit),
                  label: const Text('Override'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFdaStatusBadge(String? status) {
    final colors = {
      'ND': Colors.green,
      'D': Colors.orange,
      'S': Colors.red,
      'N': Colors.red.shade800,
      'P': Colors.purple,
    };
    final labels = {
      'ND': 'ND (สามัญ)',
      'D': 'D (อันตราย)',
      'S': 'S (ควบคุม)',
      'N': 'N (เสพติด)',
      'P': 'P (จิตเวช)',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (colors[status] ?? Colors.grey).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors[status] ?? Colors.grey),
      ),
      child: Text(
        labels[status] ?? 'ไม่ระบุ',
        style: TextStyle(
          color: colors[status] ?? Colors.grey,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // TAB 4: Reports
  // ═══════════════════════════════════════════

  Widget _buildReportsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          _buildReportCard(
            title: 'ยาที่องค์กรสร้างเองไม่มีระดับความเสี่ยง',
            value: '$_customMedsWithoutRisk',
            icon: Icons.warning_amber,
            color: Colors.orange,
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('ประวัติการ Override ล่าสุด'),
          const SizedBox(height: 8),
          if (_recentOverrides.isEmpty)
            const Center(child: Text('ไม่มีประวัติการ Override')),
          ..._recentOverrides.map((log) => _buildOverrideLogTile(log)),
          const SizedBox(height: 24),
          _buildSectionTitle('ประวัติการจัดการ Master Data'),
          const SizedBox(height: 8),
          if (_adminLogs.isEmpty)
            const Center(child: Text('ไม่มีประวัติการจัดการ')),
          ..._adminLogs.map((log) => _buildAdminLogTile(log)),
        ],
      ),
    );
  }

  Widget _buildReportCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        trailing: Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: AppTextStyles.heading5.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildOverrideLogTile(MedicationRiskOverrideLog log) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        title: Text('Override ยา #${log.medicationId.substring(0, 8)}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (log.oldFdaRiskStatus != log.newFdaRiskStatus)
              Text('FDA: ${log.oldFdaRiskStatus ?? '-'} → ${log.newFdaRiskStatus ?? '-'}'),
            if (log.oldSubCategory != log.newSubCategory)
              Text('Subcategory: ${log.oldSubCategory ?? '-'} → ${log.newSubCategory ?? '-'}'),
            if (log.reason != null) Text('เหตุผล: ${log.reason}'),
            Text('โดย: ${log.overriddenBy ?? 'ไม่ระบุ'}'),
          ],
        ),
        trailing: Text(
          '${log.createdAt.day}/${log.createdAt.month}/${log.createdAt.year}',
          style: AppTextStyles.bodySmall,
        ),
      ),
    );
  }

  Widget _buildAdminLogTile(Map<String, dynamic> log) {
    final actionLabels = {
      'create': 'สร้าง',
      'update': 'แก้ไข',
      'soft_delete': 'ลบ',
      'reactivate': 'คืนค่า',
      'reset_seed': 'รีเซ็ตค่าเริ่มต้น',
    };
    final actionColor = {
      'create': Colors.green,
      'update': Colors.blue,
      'soft_delete': Colors.red,
      'reactivate': Colors.orange,
      'reset_seed': Colors.purple,
    };
    final action = log['action'] as String? ?? 'unknown';
    final tableName = log['table_name'] as String? ?? '';
    final createdAt = log['created_at'] != null
        ? DateTime.parse(log['created_at'])
        : DateTime.now();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: (actionColor[action] ?? Colors.grey).withOpacity(0.1),
          child: Icon(
            action == 'create' ? Icons.add_circle
            : action == 'update' ? Icons.edit
            : action == 'soft_delete' ? Icons.delete
            : action == 'reactivate' ? Icons.restore
            : Icons.refresh,
            color: actionColor[action] ?? Colors.grey,
            size: 18,
          ),
        ),
        title: Text(
          '${actionLabels[action] ?? action} — ${tableName == 'dangerous_drug_subcategories' ? 'หมวดยาอันตราย' : 'ระดับความเสี่ยง'}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Record: ${(log['record_id'] as String? ?? '').substring(0, (log['record_id'] as String? ?? '').length.clamp(0, 8))}',
          style: AppTextStyles.bodySmall,
        ),
        trailing: Text(
          '${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
          style: AppTextStyles.bodySmall,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // Dialogs & Actions
  // ═══════════════════════════════════════════

  void _showAddDialog(int tabIndex) {
    if (tabIndex == 0) {
      _showEditSubcategoryDialog(null);
    } else if (tabIndex == 1) {
      _showEditRiskLevelDialog(null);
    }
  }

  Future<void> _showEditSubcategoryDialog(DangerousDrugSubcategory? existing) async {
    final codeController = TextEditingController(text: existing?.code ?? '');
    final nameThController = TextEditingController(text: existing?.nameTh ?? '');
    final nameEnController = TextEditingController(text: existing?.nameEn ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');
    bool isProhibited = existing?.isTelemedicineProhibited ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'เพิ่มหมวดหมู่ยาอันตรายย่อย' : 'แก้ไขหมวดหมู่ยาอันตรายย่อย'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: codeController, decoration: const InputDecoration(labelText: 'Code *')),
                TextField(controller: nameThController, decoration: const InputDecoration(labelText: 'ชื่อภาษาไทย *')),
                TextField(controller: nameEnController, decoration: const InputDecoration(labelText: 'ชื่อภาษาอังกฤษ')),
                TextField(controller: descController, decoration: const InputDecoration(labelText: 'คำอธิบาย')),
                SwitchListTile(
                  title: const Text('ห้ามสั่งผ่าน Telemedicine'),
                  value: isProhibited,
                  onChanged: (v) => setDialogState(() => isProhibited = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
            FilledButton(
              onPressed: () async {
                if (codeController.text.isEmpty || nameThController.text.isEmpty) return;
                try {
                  if (existing == null) {
                    await _repo.createSubcategory(
                      code: codeController.text,
                      nameTh: nameThController.text,
                      nameEn: nameEnController.text.isNotEmpty ? nameEnController.text : null,
                      description: descController.text.isNotEmpty ? descController.text : null,
                      isTelemedicineProhibited: isProhibited,
                      performedBy: _currentUserId,
                    );
                  } else {
                    await _repo.updateSubcategory(
                      existing.id,
                      code: codeController.text,
                      nameTh: nameThController.text,
                      nameEn: nameEnController.text.isNotEmpty ? nameEnController.text : null,
                      description: descController.text.isNotEmpty ? descController.text : null,
                      isTelemedicineProhibited: isProhibited,
                      performedBy: _currentUserId,
                    );
                  }
                  if (mounted) Navigator.pop(context, true);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _loadSubcategories();
      setState(() {});
    }
  }

  Future<void> _showEditRiskLevelDialog(CustomRiskLevel? existing) async {
    final codeController = TextEditingController(text: existing?.code ?? '');
    final nameThController = TextEditingController(text: existing?.nameTh ?? '');
    final nameEnController = TextEditingController(text: existing?.nameEn ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');
    bool isProhibited = existing?.isTelemedicineProhibited ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'เพิ่มระดับความเสี่ยง' : 'แก้ไขระดับความเสี่ยง'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: codeController, decoration: const InputDecoration(labelText: 'Code *')),
                TextField(controller: nameThController, decoration: const InputDecoration(labelText: 'ชื่อภาษาไทย *')),
                TextField(controller: nameEnController, decoration: const InputDecoration(labelText: 'ชื่อภาษาอังกฤษ')),
                TextField(controller: descController, decoration: const InputDecoration(labelText: 'คำอธิบาย')),
                SwitchListTile(
                  title: const Text('ห้ามสั่งผ่าน Telemedicine'),
                  value: isProhibited,
                  onChanged: (v) => setDialogState(() => isProhibited = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
            FilledButton(
              onPressed: () async {
                if (codeController.text.isEmpty || nameThController.text.isEmpty) return;
                try {
                  if (existing == null) {
                    await _repo.createRiskLevel(
                      code: codeController.text,
                      nameTh: nameThController.text,
                      nameEn: nameEnController.text.isNotEmpty ? nameEnController.text : null,
                      description: descController.text.isNotEmpty ? descController.text : null,
                      isTelemedicineProhibited: isProhibited,
                      performedBy: _currentUserId,
                    );
                  } else {
                    await _repo.updateRiskLevel(
                      existing.id,
                      code: codeController.text,
                      nameTh: nameThController.text,
                      nameEn: nameEnController.text.isNotEmpty ? nameEnController.text : null,
                      description: descController.text.isNotEmpty ? descController.text : null,
                      isTelemedicineProhibited: isProhibited,
                      performedBy: _currentUserId,
                    );
                  }
                  if (mounted) Navigator.pop(context, true);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _loadRiskLevels();
      setState(() {});
    }
  }

  Future<void> _showOverrideDialog(Map<String, dynamic> med) async {
    final fdaController = TextEditingController(text: med['fda_risk_status'] ?? '');
    final subCatController = TextEditingController(text: med['dangerous_sub_category'] ?? '');
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Override: ${med['trade_name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: fdaController,
                decoration: const InputDecoration(labelText: 'FDA Risk Status (ND/D/S/N/P)'),
              ),
              TextField(
                controller: subCatController,
                decoration: const InputDecoration(labelText: 'Dangerous Sub Category'),
              ),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'เหตุผล *'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () async {
              if (reasonController.text.isEmpty) return;
              try {
                final userId = AuthService.instance.currentUser?.id ?? 'unknown';
                await _repo.updateMedicationClassification(
                  medicationId: med['id'] as String,
                  fdaRiskStatus: fdaController.text.isNotEmpty ? fdaController.text : null,
                  dangerousSubCategory: subCatController.text.isNotEmpty ? subCatController.text : null,
                  reason: reasonController.text,
                  overriddenBy: userId,
                );
                if (mounted) {
                  Navigator.pop(context, true);
                  _searchMedications(_searchController.text);
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            },
            child: const Text('บันทึก Override'),
          ),
        ],
      ),
    );

    if (result == true) {
      _loadReports();
      setState(() {});
    }
  }

  Future<void> _toggleSubcategoryActive(DangerousDrugSubcategory item, bool value) async {
    try {
      await _repo.updateSubcategory(item.id, isActive: value, performedBy: _currentUserId);
      await _loadSubcategories();
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _toggleRiskLevelActive(CustomRiskLevel item, bool value) async {
    try {
      await _repo.updateRiskLevel(item.id, isActive: value, performedBy: _currentUserId);
      await _loadRiskLevels();
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _confirmDeleteSubcategory(DangerousDrugSubcategory item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ลบ "${item.nameTh}"? (สามารถคืนค่าได้ภายหลัง)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _repo.softDeleteSubcategory(item.id, performedBy: _currentUserId);
        await _loadSubcategories();
        setState(() {});
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _reactivateSubcategory(DangerousDrugSubcategory item) async {
    try {
      await _repo.reactivateSubcategory(item.id, performedBy: _currentUserId);
      await _loadSubcategories();
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _confirmDeleteRiskLevel(CustomRiskLevel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ลบ "${item.nameTh}"? (สามารถคืนค่าได้ภายหลัง)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _repo.softDeleteRiskLevel(item.id, performedBy: _currentUserId);
        await _loadRiskLevels();
        setState(() {});
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _reactivateRiskLevel(CustomRiskLevel item) async {
    try {
      await _repo.reactivateRiskLevel(item.id, performedBy: _currentUserId);
      await _loadRiskLevels();
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}
