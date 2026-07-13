import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/features/admin/models/profession.dart';
import 'package:sheserved/features/admin/data/repositories/profession_repository.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../services/auth_service.dart';
import '../../data/models/drug_risk_classification_models.dart';
import '../../data/repositories/drug_risk_classification_repository.dart';

enum DrugRiskPageMode { globalAdmin, organizationOverride, personalOverride }

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
  Timer? _searchDebounce;
  // Tab 4 data
  List<MedicationRiskOverrideLog> _recentOverrides = [];
  int _customMedsWithoutRisk = 0;
  List<Map<String, dynamic>> _adminLogs = [];

  // Override history data (for Org/Personal modes)
  List<DrugRiskOverrideHistory> _overrideHistory = [];

  // Soft delete visibility
  bool _showDeletedSubcategories = false;
  bool _showDeletedRiskLevels = false;
  Profession? _currentUserProfession;
  bool _isProfessionLoaded = false;

  String get _currentUserId => AuthService.instance.currentUser?.id ?? 'unknown';

  DrugRiskPageMode get _pageMode {
    final user = AuthService.instance.currentUser;
    if (user == null) return DrugRiskPageMode.personalOverride;
    if (user.isAdmin) return DrugRiskPageMode.globalAdmin;
    if (_currentUserProfession?.canManageDrugRisk == true) {
      return DrugRiskPageMode.organizationOverride;
    }
    return DrugRiskPageMode.personalOverride;
  }

  @override
  void initState() {
    super.initState();
    final user = AuthService.instance.currentUser;
    final tabLength = user?.isAdmin == true ? 4 : 2;
    _tabController = TabController(length: tabLength, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Rebuild for floatingActionButton visibility
    });
    _repo = DrugRiskClassificationRepository(Supabase.instance.client);
    _initializePage();
  }

  Future<void> _initializePage() async {
    final user = AuthService.instance.currentUser;
    if (user != null && !user.isAdmin && user.professionId != null) {
      try {
        _currentUserProfession = await ProfessionRepository(Supabase.instance.client)
            .getProfessionById(user.professionId!);
      } catch (e) {
        debugPrint('DrugRisk: failed to load current profession: $e');
      }
    }
    _isProfessionLoaded = true;

    if (mounted) {
      setState(() {});
      await _loadAllData();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(() {});
    _tabController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final mode = _pageMode;
      if (mode == DrugRiskPageMode.globalAdmin) {
        await Future.wait([
          _loadSubcategories(),
          _loadRiskLevels(),
          _loadReports(),
        ]);
      } else {
        await _loadReports();
      }
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
    final mode = _pageMode;
    if (mode == DrugRiskPageMode.globalAdmin) {
      _recentOverrides = await _repo.getRecentOverrides();
      _customMedsWithoutRisk = await _repo.getCustomMedicationsWithoutRiskLevel();
      _adminLogs = await _repo.getAdminLogs();
    } else {
      final user = AuthService.instance.currentUser;
      if (user != null) {
        _overrideHistory = await _repo.getOverrideHistory(
          professionId: mode == DrugRiskPageMode.organizationOverride ? user.professionId : null,
          userId: mode == DrugRiskPageMode.personalOverride ? user.id : null,
        );
      }
    }
  }

  Future<void> _enrichSearchResults() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    final userId = user.id;
    final professionId = user.professionId;
    final mode = _pageMode;

    for (int i = 0; i < _searchResults.length; i++) {
      final med = _searchResults[i];
      final medId = med['id'] as String;

      final effective = await _repo.getMedicationRiskEffective(
        medicationId: medId,
        currentUserId: mode == DrugRiskPageMode.personalOverride ? userId : null,
        professionId: mode == DrugRiskPageMode.organizationOverride ? professionId : null,
      );

      final modifier = await _repo.resolveEffectiveModifier(
        medicationId: medId,
        userId: mode == DrugRiskPageMode.personalOverride ? userId : null,
        professionId: mode == DrugRiskPageMode.organizationOverride ? professionId : null,
      );

      final activeOverride = await _repo.getOverride(
        userId: mode == DrugRiskPageMode.personalOverride ? userId : null,
        professionId: mode == DrugRiskPageMode.organizationOverride ? professionId : null,
        medicationId: medId,
      );

      _searchResults[i] = {
        ...med,
        'effective_risk': effective,
        'effective_modifier': modifier,
        'active_override': activeOverride,
      };
    }
  }

  Future<void> _searchMedications(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final results = await _repo.searchMedications(query);
      _searchResults = results;
      if (_pageMode != DrugRiskPageMode.globalAdmin) {
        await _enrichSearchResults();
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatRelativeTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 0) return 'เมื่อ ${diff.inDays} วันที่แล้ว';
    if (diff.inHours > 0) return 'เมื่อ ${diff.inHours} ชั่วโมงที่แล้ว';
    if (diff.inMinutes > 0) return 'เมื่อ ${diff.inMinutes} นาทีที่แล้ว';
    return 'เมื่อสักครู่';
  }

  Widget _buildCardBanner(EffectiveModifierInfo modifier, DrugRiskOverride? activeOverride) {
    String text = '';
    Color color = Colors.orange.shade800;
    Color bgColor = Colors.orange.shade50;

    final notes = activeOverride?.overrideNotes ?? '';
    final notesSuffix = notes.isNotEmpty ? '\n"$notes"' : '';
    final relativeTime = _formatRelativeTime(modifier.modifiedAt);
    final timeStr = relativeTime.isNotEmpty ? ' $relativeTime' : '';

    if (modifier.status == 'active') {
      text = '⚠️ แก้ไขล่าสุดโดย ${modifier.name}$timeStr$notesSuffix';
    } else if (modifier.status == 'fallback_history') {
      final displayName = modifier.snapshotName ?? modifier.name;
      text = '⚠️ ตั้งค่าโดยอดีตเจ้าหน้าที่ (โอนย้ายสิทธิ์ดูแลให้ $displayName [Active]$timeStr)$notesSuffix';
      color = Colors.blue.shade900;
      bgColor = Colors.blue.shade50;
    } else if (modifier.status == 'fallback_system') {
      text = '⚠️ ดูแลโดย System Admin (เนื่องจากผู้ตั้งค่าพ้นสภาพการเป็นผู้ดูแลระบบ)$notesSuffix';
      color = Colors.red.shade900;
      bgColor = Colors.red.shade50;
    }

    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildModeBanner(DrugRiskPageMode mode) {
    String text;
    Color bgColor;
    Color textColor;
    IconData icon;

    switch (mode) {
      case DrugRiskPageMode.globalAdmin:
        text = '🌐 โหมดจัดการส่วนกลาง — เปลี่ยนแปลงส่งผลต่อทุกผู้ใช้';
        bgColor = Colors.blue.shade50;
        textColor = Colors.blue.shade900;
        icon = Icons.public;
        break;
      case DrugRiskPageMode.organizationOverride:
        text = '🏥 ตั้งค่าสำหรับองค์กร — จะมีผลกับทุกคนในคลินิก/ร้านยาของคุณ';
        bgColor = Colors.teal.shade50;
        textColor = Colors.teal.shade900;
        icon = Icons.local_hospital;
        break;
      case DrugRiskPageMode.personalOverride:
        text = '👤 ตั้งค่าส่วนตัว — จะใช้เฉพาะกับการออกใบสั่งยาของคุณเท่านั้น';
        bgColor = Colors.purple.shade50;
        textColor = Colors.purple.shade900;
        icon = Icons.person;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: bgColor,
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = _pageMode;
    String title;
    List<Tab> tabs;
    List<Widget> tabViews;

    switch (mode) {
      case DrugRiskPageMode.globalAdmin:
        title = 'จัดการหมวดหมู่ความเสี่ยงยา';
        tabs = const [
          Tab(icon: Icon(Icons.category_outlined, size: 20), text: 'หมวดยาอันตราย'),
          Tab(icon: Icon(Icons.scale_outlined, size: 20), text: 'ระดับความเสี่ยง'),
          Tab(icon: Icon(Icons.medical_services_outlined, size: 20), text: 'ตรวจสอบยา'),
          Tab(icon: Icon(Icons.bar_chart_outlined, size: 20), text: 'รายงาน'),
        ];
        tabViews = [
          _buildSubcategoriesTab(),
          _buildRiskLevelsTab(),
          _buildMedicationReviewTab(),
          _buildReportsTab(),
        ];
        break;

      case DrugRiskPageMode.organizationOverride:
        title = 'จัดการความเสี่ยงยา (Organization)';
        tabs = const [
          Tab(icon: Icon(Icons.medical_services_outlined, size: 20), text: 'ค้นหายา'),
          Tab(icon: Icon(Icons.history, size: 20), text: 'ประวัติการตั้งค่า'),
        ];
        tabViews = [
          _buildMedicationReviewTab(),
          _buildHistoryTab(),
        ];
        break;

      case DrugRiskPageMode.personalOverride:
        title = 'จัดการความเสี่ยงยา (Personal)';
        tabs = const [
          Tab(icon: Icon(Icons.medical_services_outlined, size: 20), text: 'ค้นหายา'),
          Tab(icon: Icon(Icons.history, size: 20), text: 'ประวัติการตั้งค่า'),
        ];
        tabViews = [
          _buildMedicationReviewTab(),
          _buildHistoryTab(),
        ];
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: mode == DrugRiskPageMode.globalAdmin
            ? [
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
              ]
            : null,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: mode == DrugRiskPageMode.globalAdmin,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13),
          tabs: tabs,
        ),
      ),
      body: !_isProfessionLoaded && mode != DrugRiskPageMode.globalAdmin
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildModeBanner(mode),
                Expanded(
                  child: _isLoading && _subcategories.isEmpty && _riskLevels.isEmpty && _overrideHistory.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text('Error: $_error'))
                          : TabBarView(
                              controller: _tabController,
                              children: tabViews,
                            ),
                ),
              ],
            ),
      floatingActionButton: mode == DrugRiskPageMode.globalAdmin && _tabController.index < 2
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
                    color: isDeleted
                        ? Colors.grey.shade700
                        : (item.isTelemedicineProhibited ? Colors.red : Colors.green),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(item.nameTh, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                          if (item.nameEn != null) ...[
                            const SizedBox(width: 6),
                            Text('(${item.nameEn})', style: AppTextStyles.bodySmall),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('Code: ${item.code}', style: AppTextStyles.bodySmall),
                      if (item.description != null) ...[
                        const SizedBox(height: 4),
                        Text(item.description!, style: AppTextStyles.bodySmall.copyWith(color: Colors.grey.shade600)),
                      ],
                    ],
                  ),
                ),
                _buildCardActions(
                  isDeleted: isDeleted,
                  onRestore: () => _reactivateSubcategory(item),
                  isActive: item.isActive,
                  onToggle: (val) => _toggleSubcategoryActive(item, val),
                  onEdit: () => _showEditSubcategoryDialog(item),
                  onDelete: () => _confirmDeleteSubcategory(item),
                ),
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
                  backgroundColor: isDeleted
                      ? Colors.grey.shade400
                      : _riskLevelColor(item.code).withOpacity(0.2),
                  child: Icon(
                    isDeleted ? Icons.delete_outline : (item.isTelemedicineProhibited ? Icons.block : Icons.check_circle),
                    color: isDeleted
                        ? Colors.grey.shade700
                        : _riskLevelColor(item.code),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(item.nameTh, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                          if (item.nameEn != null) ...[
                            const SizedBox(width: 6),
                            Text('(${item.nameEn})', style: AppTextStyles.bodySmall),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text('Code: ${item.code}', style: AppTextStyles.bodySmall),
                          const SizedBox(width: 8),
                          _buildStatusChip(
                            item.isTelemedicineProhibited ? 'ห้าม Telemed' : 'อนุญาต Telemed',
                            item.isTelemedicineProhibited ? Colors.red : Colors.green,
                          ),
                        ],
                      ),
                      if (item.description != null) ...[
                        const SizedBox(height: 4),
                        Text(item.description!, style: AppTextStyles.bodySmall.copyWith(color: Colors.grey.shade600)),
                      ],
                    ],
                  ),
                ),
                _buildCardActions(
                  isDeleted: isDeleted,
                  onRestore: () => _reactivateRiskLevel(item),
                  isActive: item.isActive,
                  onToggle: (val) => _toggleRiskLevelActive(item, val),
                  onEdit: () => _showEditRiskLevelDialog(item),
                  onDelete: () => _confirmDeleteRiskLevel(item),
                ),
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
      case 'low': return Colors.green;
      case 'medium': return Colors.amber;
      case 'high': return Colors.orange;
      case 'very_high': return Colors.deepOrange;
      case 'prohibited': return Colors.red;
      default: return Colors.grey;
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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'ค้นหาตามชื่อยา (Trade/Generic)...',
                    prefixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () {
                        _searchMedications(_searchController.text);
                      },
                    ),
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
                  onChanged: (value) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
                      _searchMedications(value);
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  _searchMedications(_searchController.text);
                },
                child: const Text('ค้นหา'),
              ),
            ],
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
    final mode = _pageMode;
    String? fdaStatus = med['fda_risk_status'] as String?;
    String? subCategory = med['dangerous_sub_category'] as String?;
    bool hasOverride = false;
    String? overrideScope;
    EffectiveModifierInfo? modifier;
    DrugRiskOverride? activeOverride;

    if (mode != DrugRiskPageMode.globalAdmin) {
      final effective = med['effective_risk'] as Map<String, dynamic>?;
      modifier = med['effective_modifier'] as EffectiveModifierInfo?;
      activeOverride = med['active_override'] as DrugRiskOverride?;

      if (effective != null) {
        fdaStatus = effective['fda_risk_status'] as String?;
        subCategory = effective['dangerous_sub_category'] as String?;
        hasOverride = effective['has_override'] == true;
        overrideScope = effective['override_scope'] as String?;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (modifier != null && modifier.status != 'no_override')
              _buildCardBanner(modifier, activeOverride),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              med['trade_name'] ?? 'ไม่ระบุชื่อ',
                              style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (hasOverride) ...[
                            const SizedBox(width: 8),
                            _buildOverrideScopeBadge(overrideScope),
                          ],
                        ],
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
                if (mode != DrugRiskPageMode.globalAdmin && activeOverride != null) ...[
                  TextButton.icon(
                    onPressed: () => _removeOverride(med),
                    icon: const Icon(Icons.restore, color: Colors.red),
                    label: const Text('คืนค่า Default', style: TextStyle(color: Colors.red)),
                  ),
                  const SizedBox(width: 8),
                ],
                TextButton.icon(
                  onPressed: () => _showOverrideDialog(med),
                  icon: const Icon(Icons.edit),
                  label: Text(mode == DrugRiskPageMode.globalAdmin ? 'Override' : 'ตั้งค่า Override'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverrideScopeBadge(String? scope) {
    final isOrg = scope == 'organization';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (isOrg ? Colors.teal : Colors.purple).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isOrg ? Colors.teal : Colors.purple, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOrg ? Icons.local_hospital : Icons.person,
            size: 10,
            color: isOrg ? Colors.teal : Colors.purple,
          ),
          const SizedBox(width: 4),
          Text(
            isOrg ? 'Override องค์กร' : 'Override ส่วนตัว',
            style: TextStyle(
              fontSize: 9,
              color: isOrg ? Colors.teal : Colors.purple,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
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
  // Org / Personal Override History Tab
  // ═══════════════════════════════════════════

  Widget _buildHistoryTab() {
    if (_overrideHistory.isEmpty) {
      return const Center(child: Text('ไม่มีประวัติการตั้งค่า Override'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _overrideHistory.length,
      itemBuilder: (context, index) {
        final log = _overrideHistory[index];
        final isOrg = log.professionId != null;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isOrg ? Colors.teal : Colors.purple).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isOrg ? Colors.teal : Colors.purple),
                      ),
                      child: Text(
                        isOrg ? '🏥 องค์กร' : '👤 ส่วนตัว',
                        style: TextStyle(
                          color: isOrg ? Colors.teal : Colors.purple,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    Text(
                      '${log.changedAt.day}/${log.changedAt.month}/${log.changedAt.year} ${log.changedAt.hour.toString().padLeft(2, '0')}:${log.changedAt.minute.toString().padLeft(2, '0')}',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'การกระทำ: ${log.action == 'create' ? 'สร้างการ Override' : log.action == 'update' ? 'แก้ไขการ Override' : 'ยกเลิกการ Override (คืนค่า)'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (log.fdaRiskStatusBefore != log.fdaRiskStatusAfter)
                  Text('FDA: ${log.fdaRiskStatusBefore ?? 'ค่าเริ่มต้น'} → ${log.fdaRiskStatusAfter ?? 'ค่าเริ่มต้น'}'),
                if (log.subCategoryBefore != log.subCategoryAfter)
                  Text('Subcategory: ${log.subCategoryBefore ?? 'ค่าเริ่มต้น'} → ${log.subCategoryAfter ?? 'ค่าเริ่มต้น'}'),
                if (log.isTelemedicineProhibitedBefore != log.isTelemedicineProhibitedAfter)
                  Text('ห้าม Telemedicine: ${log.isTelemedicineProhibitedBefore ?? 'ค่าเริ่มต้น'} → ${log.isTelemedicineProhibitedAfter ?? 'ค่าเริ่มต้น'}'),
                const SizedBox(height: 8),
                if (log.changeReason != null && log.changeReason!.isNotEmpty)
                  Text('เหตุผล: ${log.changeReason}', style: const TextStyle(fontStyle: FontStyle.italic)),
                const Divider(),
                Text('ดำเนินการโดย: ${log.changedByName} (ณ ขณะนั้น)', style: AppTextStyles.bodySmall),
              ],
            ),
          ),
        );
      },
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
    final mode = _pageMode;
    if (mode == DrugRiskPageMode.globalAdmin) {
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
    } else {
      final activeOverride = med['active_override'] as DrugRiskOverride?;
      final modifier = med['effective_modifier'] as EffectiveModifierInfo?;

      String? selectedFda = activeOverride?.overrideFdaRiskStatus ?? med['fda_risk_status'];
      String? selectedSubCat = activeOverride?.overrideSubCategory ?? med['dangerous_sub_category'];
      String? selectedCustomCode = activeOverride?.overrideCustomRiskCode;

      bool isTeleProhibited = activeOverride?.overrideIsTelemedicineProhibited ?? 
          (selectedFda == 'S' || selectedFda == 'N' || selectedFda == 'P' || 
           (selectedFda == 'D' && (selectedSubCat == 'hormone_injection' || selectedSubCat == 'chemotherapy' || selectedSubCat == 'abortifacient')));

      final notesController = TextEditingController(text: activeOverride?.overrideNotes ?? '');
      final reasonController = TextEditingController();

      final result = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final isNP = selectedFda == 'N' || selectedFda == 'P';
            if (isNP) {
              isTeleProhibited = true;
            }

            return AlertDialog(
              title: Text('Override: ${med['trade_name']}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (modifier != null && modifier.status != 'no_override') ...[
                      _buildCardBanner(modifier, activeOverride),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String>(
                      value: selectedFda,
                      decoration: const InputDecoration(labelText: 'FDA Risk Status'),
                      items: const [
                        DropdownMenuItem(value: 'ND', child: Text('ND (ยาสามัญประจำบ้าน)')),
                        DropdownMenuItem(value: 'D', child: Text('D (ยาอันตราย)')),
                        DropdownMenuItem(value: 'S', child: Text('S (ยาควบคุมพิเศษ)')),
                        DropdownMenuItem(value: 'N', child: Text('N (ยาเสพติดให้โทษ)')),
                        DropdownMenuItem(value: 'P', child: Text('P (วัตถุออกฤทธิ์ต่อจิต/ประสาท)')),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          selectedFda = val;
                          if (val == 'N' || val == 'P') {
                            isTeleProhibited = true;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: TextEditingController(text: selectedSubCat)..selection = TextSelection.collapsed(offset: (selectedSubCat ?? '').length),
                      decoration: const InputDecoration(
                        labelText: 'Dangerous Subcategory (ถ้ามี)',
                        hintText: 'e.g. hormone_injection',
                      ),
                      onChanged: (val) {
                        selectedSubCat = val.isEmpty ? null : val;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCustomCode,
                      decoration: const InputDecoration(labelText: 'Custom Risk Level (ถ้ามี)'),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('ไม่ได้กำหนด')),
                        DropdownMenuItem(value: 'low', child: Text('ความเสี่ยงต่ำ')),
                        DropdownMenuItem(value: 'medium', child: Text('ความเสี่ยงปานกลาง')),
                        DropdownMenuItem(value: 'high', child: Text('ความเสี่ยงสูง')),
                        DropdownMenuItem(value: 'very_high', child: Text('ความเสี่ยงสูงมาก')),
                        DropdownMenuItem(value: 'prohibited', child: Text('ห้ามใช้')),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          selectedCustomCode = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('ห้ามจ่ายผ่าน Telemedicine'),
                      subtitle: isNP
                          ? const Text('ประเภท N/P ห้ามจ่ายผ่าน Telemedicine ตามกฎหมาย', style: TextStyle(color: Colors.red, fontSize: 11))
                          : null,
                      secondary: isNP
                          ? Chip(
                              label: const Text('บังคับตามกฎหมาย'),
                              backgroundColor: Colors.red.shade100,
                              labelStyle: TextStyle(color: Colors.red.shade900, fontSize: 11),
                            )
                          : null,
                      value: isTeleProhibited,
                      onChanged: isNP
                          ? null
                          : (val) {
                              setDialogState(() {
                                isTeleProhibited = val;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(labelText: 'หมายเหตุการสั่งยาสำหรับหน้างาน (ป้ายคำเตือน)'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonController,
                      decoration: const InputDecoration(
                        labelText: 'เหตุผลการ Override เพื่อบันทึกประวัติ *',
                        hintText: 'ระบุสาเหตุที่ต้องการแก้ไขการจัดหมวดหมู่นี้',
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
                FilledButton(
                  onPressed: () async {
                    if (reasonController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('กรุณาระบุเหตุผลการ Override')),
                      );
                      return;
                    }
                    try {
                      final user = AuthService.instance.currentUser;
                      if (user == null) return;

                      await _repo.setOverride(
                        userId: mode == DrugRiskPageMode.personalOverride ? user.id : null,
                        professionId: mode == DrugRiskPageMode.organizationOverride ? user.professionId : null,
                        medicationId: med['id'] as String,
                        overrideFdaRiskStatus: selectedFda,
                        overrideSubCategory: selectedSubCat,
                        overrideCustomRiskCode: selectedCustomCode,
                        overrideIsTelemedicineProhibited: isTeleProhibited,
                        overrideNotes: notesController.text.isNotEmpty ? notesController.text : null,
                        performedBy: user.id,
                        performedByName: user.fullName,
                        changeReason: reasonController.text,
                      );

                      if (mounted) {
                        FocusScope.of(context).unfocus();
                        Navigator.pop(context, true);
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
            );
          },
        ),
      );

      if (result == true) {
        FocusManager.instance.primaryFocus?.unfocus();
        await _searchMedications(_searchController.text);
        await _loadReports();
        setState(() {});
      }
    }
  }

  Future<void> _removeOverride(Map<String, dynamic> med) async {
    final mode = _pageMode;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการคืนค่าเริ่มต้น'),
        content: const Text('คุณต้องการลบการ Override ยานี้และใช้ค่าเริ่มต้นของ Sheserved หรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ยืนยันการคืนค่า'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) return;

      await _repo.removeOverride(
        userId: mode == DrugRiskPageMode.personalOverride ? user.id : null,
        professionId: mode == DrugRiskPageMode.organizationOverride ? user.professionId : null,
        medicationId: med['id'] as String,
        performedBy: user.id,
        performedByName: user.fullName,
        changeReason: 'คืนค่า Default ของระบบ',
      );

      await _searchMedications(_searchController.text);
      await _loadReports();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
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
