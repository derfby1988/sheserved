import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../models/profession.dart';

/// หน้าตรวจสอบผู้สมัครลงทะเบียน
class ApplicationReviewPage extends StatefulWidget {
  const ApplicationReviewPage({super.key});

  @override
  State<ApplicationReviewPage> createState() => _ApplicationReviewPageState();
}

class _ApplicationReviewPageState extends State<ApplicationReviewPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<RegistrationApplication> _applications = [];
  bool _isLoading = true;
  VerificationStatus _selectedStatus = VerificationStatus.pending;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedStatus = VerificationStatus.values[_tabController.index];
        });
        _loadApplications();
      }
    });
    _loadApplications();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadApplications() async {
    setState(() => _isLoading = true);

    // TODO: Load from repository
    await Future.delayed(const Duration(milliseconds: 300));

    // Mock data
    setState(() {
      _applications = _getMockApplications();
      _isLoading = false;
    });
  }

  List<RegistrationApplication> _getMockApplications() {
    final now = DateTime.now();
    return [
      RegistrationApplication(
        id: '1',
        oderId: 'user-1',
        professionId: Profession.expertProfessionId,
        profession: Profession.defaultProfessions[1],
        firstName: 'สมชาย',
        lastName: 'ใจดี',
        username: 'somchai_shop',
        phone: '081-234-5678',
        registrationData: {
          'business_name': 'ร้านสมชายพืชผัก',
          'specialty': 'ผักออร์แกนิค',
          'business_phone': '081-234-5678',
          'id_card_image': 'uploaded',
        },
        status: VerificationStatus.pending,
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(hours: 2)),
      ),
      RegistrationApplication(
        id: '2',
        oderId: 'user-2',
        professionId: Profession.clinicProfessionId,
        profession: Profession.defaultProfessions[2],
        firstName: 'หมอ',
        lastName: 'ดี',
        username: 'doctor_dee',
        phone: '082-345-6789',
        registrationData: {
          'clinic_name': 'คลินิกหมอดี',
          'license_number': 'CL-12345',
          'business_phone': '082-345-6789',
          'license_image': 'uploaded',
          'id_card_image': 'uploaded',
        },
        status: VerificationStatus.pending,
        createdAt: now.subtract(const Duration(hours: 5)),
        updatedAt: now.subtract(const Duration(hours: 5)),
      ),
      RegistrationApplication(
        id: '3',
        oderId: 'user-3',
        professionId: Profession.expertProfessionId,
        profession: Profession.defaultProfessions[1],
        firstName: 'วิชัย',
        lastName: 'ช่างฝีมือ',
        username: 'wichai_craft',
        phone: '083-456-7890',
        registrationData: {
          'business_name': 'งานฝีมือวิชัย',
          'specialty': 'เครื่องเงิน',
          'business_phone': '083-456-7890',
          'id_card_image': 'uploaded',
        },
        status: VerificationStatus.approved,
        reviewNote: 'ข้อมูลครบถ้วน',
        reviewedAt: now.subtract(const Duration(days: 1)),
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        title: const Text('ตรวจสอบผู้สมัคร'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.textOnPrimary,
          labelColor: AppColors.textOnPrimary,
          unselectedLabelColor: AppColors.textOnPrimary.withOpacity(0.6),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('รอตรวจสอบ'),
                  const SizedBox(width: 4),
                  _buildBadge(_getPendingCount()),
                ],
              ),
            ),
            const Tab(text: 'อนุมัติแล้ว'),
            const Tab(text: 'ถูกปฏิเสธ'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildApplicationList(),
    );
  }

  Widget _buildBadge(int count) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  int _getPendingCount() {
    return _applications
        .where((a) => a.status == VerificationStatus.pending)
        .length;
  }

  Widget _buildApplicationList() {
    final filteredApps =
        _applications.where((a) => a.status == _selectedStatus).toList();

    if (filteredApps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _selectedStatus == VerificationStatus.pending
                  ? Icons.inbox_outlined
                  : _selectedStatus == VerificationStatus.approved
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
              size: 64,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 16),
            Text(
              _selectedStatus == VerificationStatus.pending
                  ? 'ไม่มีผู้สมัครรอตรวจสอบ'
                  : _selectedStatus == VerificationStatus.approved
                      ? 'ยังไม่มีผู้สมัครที่อนุมัติ'
                      : 'ยังไม่มีผู้สมัครที่ถูกปฏิเสธ',
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredApps.length,
      itemBuilder: (context, index) {
        return _buildApplicationCard(filteredApps[index]);
      },
    );
  }

  Widget _buildApplicationCard(RegistrationApplication application) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showApplicationDetail(application),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Avatar
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        application.firstName.isNotEmpty
                            ? application.firstName[0].toUpperCase()
                            : '?',
                        style: AppTextStyles.heading4.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          application.fullName,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${application.username}',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                application.profession?.name ?? 'ไม่ระบุ',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Status & Action
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildStatusBadge(application.status),
                      const SizedBox(height: 8),
                      Text(
                        _formatTimeAgo(application.createdAt),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Review note if rejected
              if (application.status == VerificationStatus.rejected &&
                  application.reviewNote != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          application.reviewNote!,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Action buttons for pending
              if (application.status == VerificationStatus.pending) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _showRejectDialog(application),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: BorderSide(color: AppColors.error),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('ปฏิเสธ'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _approveApplication(application),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('อนุมัติ'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(VerificationStatus status) {
    Color color;
    String text;
    IconData icon;

    switch (status) {
      case VerificationStatus.pending:
        color = AppColors.warning;
        text = 'รอตรวจสอบ';
        icon = Icons.schedule;
        break;
      case VerificationStatus.approved:
        color = AppColors.success;
        text = 'อนุมัติแล้ว';
        icon = Icons.check_circle;
        break;
      case VerificationStatus.rejected:
        color = AppColors.error;
        text = 'ถูกปฏิเสธ';
        icon = Icons.cancel;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inDays > 0) {
      return '${difference.inDays} วันที่แล้ว';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ชั่วโมงที่แล้ว';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} นาทีที่แล้ว';
    } else {
      return 'เมื่อสักครู่';
    }
  }

  void _showApplicationDetail(RegistrationApplication application) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ApplicationDetailPage(
          application: application,
          onApprove: () {
            _approveApplication(application);
            Navigator.pop(context);
          },
          onReject: (note) {
            _rejectApplication(application, note);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _approveApplication(RegistrationApplication application) async {
    // TODO: Call repository to approve
    setState(() {
      final index = _applications.indexWhere((a) => a.id == application.id);
      if (index != -1) {
        // Update status in local list
        _applications[index] = RegistrationApplication(
          id: application.id,
          oderId: application.oderId,
          professionId: application.professionId,
          profession: application.profession,
          firstName: application.firstName,
          lastName: application.lastName,
          username: application.username,
          phone: application.phone,
          registrationData: application.registrationData,
          status: VerificationStatus.approved,
          reviewNote: 'อนุมัติแล้ว',
          reviewedAt: DateTime.now(),
          createdAt: application.createdAt,
          updatedAt: DateTime.now(),
        );
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('อนุมัติ ${application.fullName} แล้ว'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _showRejectDialog(RegistrationApplication application) {
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ปฏิเสธการสมัคร'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('กำลังปฏิเสธ: ${application.fullName}'),
            const SizedBox(height: 16),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'เหตุผลที่ปฏิเสธ *',
                hintText: 'เช่น ข้อมูลไม่ครบถ้วน, รูปไม่ชัด',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              if (noteController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('กรุณาระบุเหตุผล')),
                );
                return;
              }
              _rejectApplication(application, noteController.text);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('ปฏิเสธ'),
          ),
        ],
      ),
    );
  }

  void _rejectApplication(RegistrationApplication application, String note) async {
    // TODO: Call repository to reject
    setState(() {
      final index = _applications.indexWhere((a) => a.id == application.id);
      if (index != -1) {
        _applications[index] = RegistrationApplication(
          id: application.id,
          oderId: application.oderId,
          professionId: application.professionId,
          profession: application.profession,
          firstName: application.firstName,
          lastName: application.lastName,
          username: application.username,
          phone: application.phone,
          registrationData: application.registrationData,
          status: VerificationStatus.rejected,
          reviewNote: note,
          reviewedAt: DateTime.now(),
          createdAt: application.createdAt,
          updatedAt: DateTime.now(),
        );
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('ปฏิเสธ ${application.fullName} แล้ว'),
        backgroundColor: AppColors.error,
      ),
    );
  }
}

/// หน้าแสดงรายละเอียดผู้สมัคร
class ApplicationDetailPage extends StatelessWidget {
  final RegistrationApplication application;
  final VoidCallback onApprove;
  final Function(String note) onReject;

  const ApplicationDetailPage({
    super.key,
    required this.application,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        title: const Text('รายละเอียดผู้สมัคร'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Avatar
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          application.firstName.isNotEmpty
                              ? application.firstName[0].toUpperCase()
                              : '?',
                          style: AppTextStyles.heading2.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      application.fullName,
                      style: AppTextStyles.heading4.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '@${application.username}',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        application.profession?.name ?? 'ไม่ระบุ',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Registration Data
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ข้อมูลลงทะเบียน',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Divider(height: 24),
                    if (application.phone != null)
                      _buildInfoRow('เบอร์โทร', application.phone!),
                    ...application.registrationData.entries.map((entry) {
                      if (entry.value == 'uploaded') {
                        return _buildImageRow(entry.key);
                      }
                      return _buildInfoRow(
                        _formatFieldKey(entry.key),
                        entry.value.toString(),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Images Section
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'รูปภาพที่อัพโหลด',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Divider(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: application.registrationData.entries
                          .where((e) => e.value == 'uploaded')
                          .map((e) => _buildImagePreview(context, e.key))
                          .toList(),
                    ),
                    if (application.registrationData.entries
                        .where((e) => e.value == 'uploaded')
                        .isEmpty)
                      Text(
                        'ไม่มีรูปภาพ',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textHint,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            if (application.status == VerificationStatus.pending) ...[
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => _showRejectDialog(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: BorderSide(color: AppColors.error, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: Text(
                          'ปฏิเสธ',
                          style: AppTextStyles.button.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: onApprove,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: Text(
                          'อนุมัติ',
                          style: AppTextStyles.button.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageRow(String key) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              _formatFieldKey(key),
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Icon(Icons.check_circle, color: AppColors.success, size: 20),
          const SizedBox(width: 4),
          Text(
            'อัพโหลดแล้ว',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(BuildContext context, String key) {
    return GestureDetector(
      onTap: () {
        // TODO: Show full image
      },
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image,
              color: AppColors.textHint,
              size: 32,
            ),
            const SizedBox(height: 4),
            Text(
              _formatFieldKey(key),
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textHint,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _formatFieldKey(String key) {
    final keyMap = {
      'business_name': 'ชื่อธุรกิจ',
      'clinic_name': 'ชื่อคลินิก',
      'specialty': 'ความเชี่ยวชาญ',
      'business_phone': 'เบอร์โทรธุรกิจ',
      'license_number': 'เลขใบอนุญาต',
      'id_card_image': 'บัตรประชาชน',
      'license_image': 'ใบอนุญาต',
      'profile_image': 'รูปโปรไฟล์',
      'business_image': 'รูปสถานประกอบการ',
    };
    return keyMap[key] ?? key;
  }

  void _showRejectDialog(BuildContext context) {
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ปฏิเสธการสมัคร'),
        content: TextField(
          controller: noteController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'เหตุผลที่ปฏิเสธ *',
            hintText: 'เช่น ข้อมูลไม่ครบถ้วน, รูปไม่ชัด',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              if (noteController.text.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('กรุณาระบุเหตุผล')),
                );
                return;
              }
              Navigator.pop(ctx);
              onReject(noteController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('ปฏิเสธ'),
          ),
        ],
      ),
    );
  }
}
