import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('จัดการสมาชิก: ${widget.profession.name}'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
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

                    // Get role level from nested list or default to 3 (Member)
                    int roleLevel = 3;
                    final roles = user['user_group_roles'] as List?;
                    if (roles != null && roles.isNotEmpty) {
                      roleLevel = roles.first['role_level'] as int? ?? 3;
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: AppColors.border),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          backgroundImage: profileUrl != null ? NetworkImage(profileUrl) : null,
                          child: profileUrl == null ? const Icon(Icons.person, color: AppColors.primary) : null,
                        ),
                        title: Text(
                          name.isNotEmpty ? name : email,
                          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'สิทธิระดับ (Role Level): $roleLevel',
                          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                        ),
                        trailing: PopupMenuButton<int>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) {
                            if (value == 0) {
                              _removeMember(userId);
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
