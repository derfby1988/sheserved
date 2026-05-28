import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/core/constants/app_text_styles.dart';
import 'package:sheserved/services/service_locator.dart';

class QuickReply {
  final String id;
  final String providerId;
  final String content;
  final int sortOrder;

  QuickReply({required this.id, required this.providerId, required this.content, required this.sortOrder});

  factory QuickReply.fromMap(Map<String, dynamic> map) {
    return QuickReply(
      id: map['id'] as String,
      providerId: map['provider_id'] as String,
      content: map['content'] as String,
      sortOrder: map['sort_order'] as int,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'provider_id': providerId,
        'content': content,
        'sort_order': sortOrder,
      };
}

class ManageQuickRepliesPage extends StatefulWidget {
  const ManageQuickRepliesPage({Key? key}) : super(key: key);

  @override
  State<ManageQuickRepliesPage> createState() => _ManageQuickRepliesPageState();
}

class _ManageQuickRepliesPageState extends State<ManageQuickRepliesPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<QuickReply> _replies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchReplies();
  }

  Future<void> _fetchReplies() async {
    setState(() => _isLoading = true);
    try {
      // ✅ ใช้ ServiceLocator.instance.currentUser ตาม auth_data_guidelines.md
      final providerId = ServiceLocator.instance.currentUser?.id ?? '';
      if (providerId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนใช้งาน')),
          );
        }
        return;
      }
      final response = await _supabase
          .from('doctor_quick_replies')
          .select()
          .eq('provider_id', providerId)
          .order('sort_order');
      
      final data = response as List<dynamic>;
      setState(() {
        _replies = data.map((e) => QuickReply.fromMap(e as Map<String, dynamic>)).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load quick replies: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showAddEditDialog({QuickReply? reply}) async {
    final TextEditingController controller = TextEditingController(text: reply?.content ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(reply == null ? 'เพิ่ม Quick Reply' : 'แก้ไข Quick Reply'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'ข้อความด่วน'),
          maxLines: null,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () async {
              final content = controller.text.trim();
              if (content.isEmpty) return;
              Navigator.pop(ctx);
              await _saveReply(content, reply: reply);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveReply(String content, {QuickReply? reply}) async {
    try {
      // ✅ ใช้ ServiceLocator.instance.currentUser ตาม auth_data_guidelines.md
      final providerId = ServiceLocator.instance.currentUser?.id ?? '';
      if (reply == null) {
        // Insert new
        final newOrder = (_replies.isNotEmpty) ? _replies.last.sortOrder + 1 : 0;
        await _supabase.from('doctor_quick_replies').insert({
          'provider_id': providerId,
          'content': content,
          'sort_order': newOrder,
        });
      } else {
        // Update existing
        await _supabase
            .from('doctor_quick_replies')
            .update({'content': content})
            .eq('id', reply.id);
      }
      _fetchReplies();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  Future<void> _deleteReply(QuickReply reply) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบ Quick Reply'),
        content: const Text('คุณต้องการลบข้อความด่วนนี้หรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _supabase.from('doctor_quick_replies').delete().eq('id', reply.id);
      _fetchReplies();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการ Quick Replies'),
        backgroundColor: AppColors.primary,
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _showAddEditDialog()),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _replies.isEmpty
              ? const Center(child: Text('ไม่มี Quick Replies'))
              : ListView.separated(
                  itemCount: _replies.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final reply = _replies[index];
                    return ListTile(
                      title: Text(reply.content),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit), onPressed: () => _showAddEditDialog(reply: reply)),
                          IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteReply(reply)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
