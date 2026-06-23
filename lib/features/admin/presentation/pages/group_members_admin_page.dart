import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../services/auth_service.dart';
import '../../models/profession.dart';
import '../../data/repositories/group_role_repository.dart';

class GroupMembersAdminPage extends StatefulWidget {
  final Profession profession;

  const GroupMembersAdminPage({super.key, required this.profession});

  @override
  State<GroupMembersAdminPage> createState() => _GroupMembersAdminPageState();
}

class _GroupMembersAdminPageState extends State<GroupMembersAdminPage> {
  late GroupRoleRepository _repository;
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;

  // Bulk selection state
  final Set<String> _selectedUserIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _repository = GroupRoleRepository(Supabase.instance.client);
    _loadMembers();
  }

  String? _errorMessage;

  Future<void> _loadMembers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      debugPrint('GroupMembersAdminPage: Loading members for profession ${widget.profession.id} (${widget.profession.name})');
      final members = await _repository.getGroupMembers(widget.profession.id);
      debugPrint('GroupMembersAdminPage: Found ${members.length} members');
      
      if (mounted) {
        setState(() {
          _members = members;
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('Error loading members: $e');
      debugPrint('Stack trace: $stack');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateRole(String userId, int newRole) async {
    try {
      await _repository.updateUserRole(widget.profession.id, userId, newRole);
      _loadMembers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัพเดตสิทธิเรียบร้อยแล้ว')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถแก้ไขสิทธิได้: $e')),
        );
      }
    }
  }

  Future<void> _toggleSystemAdmin(String userId, bool makeAdmin) async {
    try {
      final currentUserId = AuthService.instance.userId;
      await _repository.setSystemAdminRole(
        userId,
        makeAdmin,
        changedByUserId: currentUserId,
        reason: makeAdmin ? 'ตั้งเป็น Admin ระบบ (single)' : 'ยกเลิกสิทธิ์ Admin ระบบ (single)',
      );
      _loadMembers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              makeAdmin
                ? 'ตั้งเป็น Admin ระบบเรียบร้อยแล้ว'
                : 'ยกเลิกสิทธิ์ Admin ระบบเรียบร้อยแล้ว',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถแก้ไขสิทธิ์ Admin ระบบได้: $e')),
        );
      }
    }
  }

  Future<void> _removeMember(String userId) async {
    try {
      await _repository.removeUserFromGroup(widget.profession.id, userId);
      _loadMembers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('นำสมาชิกออกจากกลุ่มเรียบร้อยแล้ว')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถนำสมาชิกออกได้: $e')),
        );
      }
    }
  }

  // ─── Bulk Actions ───────────────────────────────────────────

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
      if (_selectedUserIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _enterSelectionMode(String userId) {
    setState(() {
      _isSelectionMode = true;
      _selectedUserIds.add(userId);
    });
  }

  void _selectAll() {
    setState(() {
      _selectedUserIds.addAll(_members.map((m) => m['id'] as String));
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedUserIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _bulkSetAdmin(bool makeAdmin) async {
    final currentUserId = AuthService.instance.userId;
    int successCount = 0;
    int failCount = 0;

    for (final userId in _selectedUserIds.toList()) {
      try {
        await _repository.setSystemAdminRole(
          userId,
          makeAdmin,
          changedByUserId: currentUserId,
          reason: makeAdmin ? 'ตั้งเป็น Admin ระบบ (bulk)' : 'ยกเลิกสิทธิ์ Admin ระบบ (bulk)',
        );
        successCount++;
      } catch (e) {
        failCount++;
        debugPrint('Bulk role change failed for $userId: $e');
      }
    }

    _loadMembers();
    _deselectAll();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            makeAdmin
              ? 'ตั้งเป็น Admin ระบบ: $successCount คน สำเร็จ${failCount > 0 ? ', $failCount คน ล้มเหลว' : ''}'
              : 'ยกเลิกสิทธิ์ Admin ระบบ: $successCount คน สำเร็จ${failCount > 0 ? ', $failCount คน ล้มเหลว' : ''}',
          ),
        ),
      );
    }
  }

  Future<void> _bulkRemoveFromGroup() async {
    int successCount = 0;
    int failCount = 0;

    for (final userId in _selectedUserIds.toList()) {
      try {
        await _repository.removeUserFromGroup(widget.profession.id, userId);
        successCount++;
      } catch (e) {
        failCount++;
        debugPrint('Bulk remove failed for $userId: $e');
      }
    }

    _loadMembers();
    _deselectAll();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'นำออกจากกลุ่ม: $successCount คน สำเร็จ${failCount > 0 ? ', $failCount คน ล้มเหลว' : ''}',
          ),
        ),
      );
    }
  }

  // ─── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
          ? Text('เลือก ${_selectedUserIds.length} คน')
          : Text('จัดการสมาชิก: ${widget.profession.name}'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: _isSelectionMode
          ? IconButton(
              icon: const Icon(Icons.close),
              onPressed: _deselectAll,
            )
          : null,
        actions: _isSelectionMode
          ? [
              TextButton(
                onPressed: _selectAll,
                child: const Text('เลือกทั้งหมด', style: TextStyle(color: Colors.white)),
              ),
            ]
          : [],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : _members.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _members.length,
                  itemBuilder: (context, index) {
                    final user = _members[index];
                    final userId = user['id'] as String;
                    final email = user['email'] ?? 'Unknown User';
                    final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
                    final profileUrl = user['profile_image_url'] as String?;

                    final roleLevel = user['role_level'] as int? ?? 3;
                    final isSystemAdmin = user['role'] == 'admin';
                    final isSelected = _selectedUserIds.contains(userId);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isSystemAdmin ? AppColors.primary : AppColors.border,
                          width: isSystemAdmin ? 2 : 1,
                        ),
                      ),
                      child: ListTile(
                        onTap: _isSelectionMode
                          ? () => _toggleSelection(userId)
                          : null,
                        onLongPress: () {
                          if (!_isSelectionMode) {
                            _enterSelectionMode(userId);
                          }
                        },
                        leading: _isSelectionMode
                          ? Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(userId),
                              activeColor: AppColors.primary,
                            )
                          : CircleAvatar(
                              backgroundColor: AppColors.primary.withOpacity(0.1),
                              backgroundImage: profileUrl != null ? NetworkImage(profileUrl) : null,
                              child: profileUrl == null ? const Icon(Icons.person, color: AppColors.primary) : null,
                            ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name.isNotEmpty ? name : email,
                                style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (isSystemAdmin)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Admin ระบบ',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          'สิทธิระดับ (Role Level): $roleLevel',
                          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                        ),
                        trailing: _isSelectionMode
                          ? null
                          : PopupMenuButton<int>(
                              icon: const Icon(Icons.more_vert),
                              onSelected: (value) {
                                if (value == 0) {
                                  _removeMember(userId);
                                } else if (value == 99) {
                                  _toggleSystemAdmin(userId, !isSystemAdmin);
                                } else {
                                  _updateRole(userId, value);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 1,
                                  child: Text('ตั้งเป็น Level 1 (Admin)'),
                                ),
                                const PopupMenuItem(
                                  value: 2,
                                  child: Text('ตั้งเป็น Level 2 (Editor)'),
                                ),
                                const PopupMenuItem(
                                  value: 3,
                                  child: Text('ตั้งเป็น Level 3 (Member)'),
                                ),
                                const PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 99,
                                  child: Text(
                                    isSystemAdmin ? 'ยกเลิกสิทธิ์ Admin ระบบ' : 'ตั้งเป็น Admin ระบบ',
                                    style: TextStyle(
                                      color: isSystemAdmin ? Colors.orange : AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 0,
                                  child: Text('นำออกจากกลุ่ม', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                      ),
                    );
                  },
                ),
      bottomNavigationBar: _isSelectionMode
        ? SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _bulkSetAdmin(true),
                      icon: const Icon(Icons.admin_panel_settings, size: 18),
                      label: const Text('ตั้งเป็น Admin'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _bulkSetAdmin(false),
                      icon: const Icon(Icons.remove_moderator, size: 18),
                      label: const Text('ยกเลิก Admin'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('ยืนยันการนำออก'),
                            content: Text('นำสมาชิก ${_selectedUserIds.length} คน ออกจากกลุ่ม?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('ยกเลิก'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _bulkRemoveFromGroup();
                                },
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                child: const Text('ยืนยัน'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.group_remove, size: 18),
                      label: const Text('นำออก'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_outlined, size: 64, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text(
            'ยังไม่มีสมาชิกในกลุ่มนี้',
            style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'ID: ${widget.profession.id}',
            style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadMembers,
            icon: const Icon(Icons.refresh),
            label: const Text('ลองโหลดใหม่'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'เกิดข้อผิดพลาดในการดึงข้อมูล',
              style: AppTextStyles.bodyLarge.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadMembers,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่'),
            ),
          ],
        ),
      ),
    );
  }
}
