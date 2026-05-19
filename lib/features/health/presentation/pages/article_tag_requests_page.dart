import 'package:flutter/material.dart';
import '../../../../services/service_locator.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../services/auth_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ArticleTagRequestsPage extends StatefulWidget {
  const ArticleTagRequestsPage({super.key});

  @override
  State<ArticleTagRequestsPage> createState() => _ArticleTagRequestsPageState();
}

class _ArticleTagRequestsPageState extends State<ArticleTagRequestsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final userId = AuthService.instance.userId;
      if (userId == null) return;

      final repo = ServiceLocator.instance.healthArticleRepository;
      final requests = await repo.getPendingTagRequests(userId);

      if (mounted) {
        setState(() {
          _requests = requests;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    }
  }

  Future<void> _approveRequest(String requestId) async {
    try {
      final repo = ServiceLocator.instance.healthArticleRepository;
      final success = await repo.approveArticleProduct(requestId);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อนุมัติแท็กเรียบร้อยแล้ว')),
        );
        _loadRequests();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('อนุมัติไม่สำเร็จ: $e')));
      }
    }
  }

  Future<void> _deleteRequest(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: const Text('คุณต้องการลบคำขอแท็กนี้ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final repo = ServiceLocator.instance.healthArticleRepository;
        final success = await repo.deleteArticleProduct(requestId);
        if (success && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('ลบคำขอเรียบร้อยแล้ว')));
          _loadRequests();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('ลบไม่สำเร็จ: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'จัดการการขอระบุแท็กสินค้า',
          style: TextStyle(
            fontFamily: 'SukhumvitSet',
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadRequests,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _requests.length,
                itemBuilder: (context, index) {
                  return _buildRequestCard(_requests[index]);
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.tag_faces, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'ยังไม่มีการขอระบุแท็กใหม่',
            style: AppTextStyles.bodyLarge.copyWith(
              color: Colors.grey,
              fontFamily: 'SukhumvitSet',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final userData = request['users'] as Map<String, dynamic>?;
    final articleData = request['health_articles'] as Map<String, dynamic>?;
    final username = userData?['username'] ?? 'ไม่ระบุชื่อ';
    final userImage = userData?['profile_image_url'] as String?;
    final articleTitle = articleData?['title'] ?? 'บทความที่ถูกลบ';
    final createdAt = DateTime.parse(request['created_at']);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: userImage != null
                      ? CachedNetworkImageProvider(userImage)
                      : null,
                  child: userImage == null ? const Icon(Icons.person) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          fontFamily: 'SukhumvitSet',
                        ),
                      ),
                      Text(
                        'ขอระบุแท็กใน: $articleTitle',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontFamily: 'SukhumvitSet',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.medication, color: Colors.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    request['name'] ?? 'ไม่มีชื่อสินค้า',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'SukhumvitSet',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _deleteRequest(request['id']),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'ปฏิเสธ/ลบ',
                      style: TextStyle(fontFamily: 'SukhumvitSet'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _approveRequest(request['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6CB0C5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'อนุมัติแท็ก',
                      style: TextStyle(fontFamily: 'SukhumvitSet'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
