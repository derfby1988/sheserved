import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/service_locator.dart';
import '../../../auth/data/models/user_model.dart';
import '../pages/chat_room_page.dart';

class ContactListPage extends StatefulWidget {
  const ContactListPage({super.key});

  @override
  State<ContactListPage> createState() => _ContactListPageState();
}

class _ContactListPageState extends State<ContactListPage> {
  final _searchController = TextEditingController();
  List<ExpertProfile> _experts = [];
  List<ClinicProfile> _clinics = [];
  bool _isLoading = true;
  bool _isGroupMode = false;
  final Set<String> _selectedUserIds = {};

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _fetchContacts() async {
    setState(() => _isLoading = true);
    try {
      final experts = await ServiceLocator.instance.userRepository.getAllExpertProfiles();
      final clinics = await ServiceLocator.instance.userRepository.getAllClinicProfiles();
      
      setState(() {
        _experts = experts;
        _clinics = clinics;
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startChat(String otherUserId) async {
    final currentUserId = ServiceLocator.instance.currentUser?.id;
    if (currentUserId == null) return;

    final room = await ServiceLocator.instance.chatRepository.getOrCreateRoom([
      currentUserId,
      otherUserId,
    ]);

    if (room != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ChatRoomPage(roomId: room.id),
        ),
      );
    }
  }

  Future<void> _createGroup() async {
    final currentUserId = ServiceLocator.instance.currentUser?.id;
    if (currentUserId == null || _selectedUserIds.isEmpty) return;

    final allParticipants = [currentUserId, ..._selectedUserIds.toList()];
    
    final room = await ServiceLocator.instance.chatRepository.getOrCreateRoom(allParticipants);

    if (room != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ChatRoomPage(roomId: room.id),
        ),
      );
    }
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isGroupMode ? 'เลือกสมาชิกกลุ่ม (${_selectedUserIds.length})' : 'เริ่มสนทนาใหม่'),
        elevation: 0,
        actions: [
          if (!_isGroupMode)
            TextButton(
              onPressed: () => setState(() => _isGroupMode = true),
              child: const Text('สร้างกลุ่ม', style: TextStyle(color: Colors.white)),
            )
          else
            TextButton(
              onPressed: _selectedUserIds.isEmpty ? null : _createGroup,
              child: Text(
                'สร้าง (${_selectedUserIds.length})',
                style: TextStyle(color: _selectedUserIds.isEmpty ? Colors.white38 : Colors.white),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'ค้นหาชื่อหมอหรือคลินิก...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      if (_experts.isNotEmpty) ...[
                         const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text('ผู้เชี่ยวชาญ / ทีมงาน', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                        ),
                        ..._experts.map((expert) => _ContactTile(
                              title: expert.businessName ?? 'ไม่ระบุชื่อ',
                              subtitle: expert.specialty ?? 'ผู้เชี่ยวชาญ',
                              specialty: expert.specialty,
                              isVerified: expert.verificationStatus == VerificationStatus.verified,
                              isSelected: _selectedUserIds.contains(expert.userId),
                              isGroupMode: _isGroupMode,
                              onTap: () {
                                if (_isGroupMode) {
                                  _toggleSelection(expert.userId);
                                } else {
                                  _startChat(expert.userId);
                                }
                              },
                            )),
                      ],
                      if (_clinics.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text('คลินิก / ศูนย์บริการ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                        ),
                        ..._clinics.map((clinic) => _ContactTile(
                              title: clinic.clinicName ?? 'ไม่ระบุชื่อคลินิก',
                              subtitle: clinic.serviceType ?? 'ศูนย์บริการสุขภาพ',
                              isSelected: _selectedUserIds.contains(clinic.userId),
                              isGroupMode: _isGroupMode,
                              onTap: () {
                                if (_isGroupMode) {
                                  _toggleSelection(clinic.userId);
                                } else {
                                  _startChat(clinic.userId);
                                }
                              },
                            )),
                      ],
                      if (_experts.isEmpty && _clinics.isEmpty)
                        const Center(child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Text('ไม่พบรายชื่อที่ติดต่อได้'),
                        )),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isSelected;
  final bool isGroupMode;
  final String? specialty;
  final bool isVerified;

  const _ContactTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isSelected = false,
    this.isGroupMode = false,
    this.specialty,
    this.isVerified = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primary.withOpacity(0.1),
            child: const Icon(Icons.person, color: AppColors.primary),
          ),
          if (isSelected)
            const Positioned(
              right: 0,
              bottom: 0,
              child: CircleAvatar(
                radius: 8,
                backgroundColor: Colors.white,
                child: Icon(Icons.check_circle, color: Colors.green, size: 16),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (isVerified) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified, color: Colors.blue, size: 16),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (specialty != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  specialty!,
                  style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
      trailing: isGroupMode 
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => onTap(),
              activeColor: AppColors.primary,
            )
          : const Icon(Icons.chevron_right, color: Colors.grey),
    );
  }
}
