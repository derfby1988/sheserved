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

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    try {
      final members = await _repository.getGroupMembers(widget.profession.id);
      setState(() {
        _members = members;
      });
    } catch (e) {
      debugPrint('Error loading members: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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
          : _members.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _members.length,
                  itemBuilder: (context, index) {
                    final member = _members[index];
                    final userId = member['user_id'] as String;
                    final roleLevel = member['role_level'] as int;
                    final userData = member['users'] ?? {};
                    final email = userData['email'] ?? 'Unknown User';
                    final meta = userData['raw_user_meta_data'] ?? {};
                    final name = '${meta['first_name'] ?? ''} ${meta['last_name'] ?? ''}'.trim();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: AppColors.border),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          child: const Icon(Icons.person, color: AppColors.primary),
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
        ],
      ),
    );
  }
}
