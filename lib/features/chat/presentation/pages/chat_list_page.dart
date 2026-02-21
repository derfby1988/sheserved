import 'package:flutter/material.dart';
import '../../../../services/service_locator.dart';
import '../../../../shared/widgets/tlz_app_top_bar.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/chat_models.dart';
import 'chat_room_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final _chatRepository = services.chatRepository;
  final _currentUser = services.currentUser;
  bool _isLoading = true;
  List<ChatRoom> _rooms = [];
  List<ChatRoom> _filteredRooms = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    if (_currentUser == null) return;
    
    setState(() => _isLoading = true);
    final rooms = await _chatRepository.getChatRooms(_currentUser!.id);
    
    if (mounted) {
      setState(() {
        _rooms = rooms;
        _filteredRooms = rooms;
        _isLoading = false;
      });
    }
  }

  void _onSearch(String query, List<Map<String, dynamic>> results) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredRooms = _rooms;
      } else {
        _filteredRooms = _rooms.where((room) {
          final lastMsg = room.lastMessage?.toLowerCase() ?? '';
          return lastMsg.contains(_searchQuery);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: TlzAppTopBar.onLight(
                onMenuPressed: () => Scaffold.of(context).openDrawer(),
                searchHintText: 'ค้นหาการสนทนา...',
                onSearch: _onSearch,
                notificationCount: 0,
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredRooms.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredRooms.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final room = _filteredRooms[index];
                            return _ChatRoomTile(
                              room: room,
                              currentUserId: _currentUser?.id ?? '',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatRoomPage(roomId: room.id),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, '/chat-contacts'),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.message, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'ยังไม่มีการสนทนา',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'เริ่มคุยกับผู้เชี่ยวชาญหรือเพื่อนๆ เลย!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, '/chat-contacts'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('หาผู้เชี่ยวชาญ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _ChatRoomTile extends StatefulWidget {
  final ChatRoom room;
  final String currentUserId;
  final VoidCallback onTap;

  const _ChatRoomTile({
    required this.room,
    required this.currentUserId,
    required this.onTap,
  });

  @override
  State<_ChatRoomTile> createState() => _ChatRoomTileState();
}

class _ChatRoomTileState extends State<_ChatRoomTile> {
  List<ChatParticipant> _participants = [];

  @override
  void initState() {
    super.initState();
    _loadOtherUserInfo();
  }

  Future<void> _loadOtherUserInfo() async {
    final otherIds = widget.room.participantIds.where((id) => id != widget.currentUserId).toList();
    if (otherIds.isEmpty) return;

    final infos = <ChatParticipant>[];
    for (var id in otherIds) {
      final info = await ServiceLocator.instance.chatRepository.getParticipantInfo(id);
      if (info != null) infos.add(info);
    }

    if (mounted) {
      setState(() => _participants = infos);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: widget.onTap,
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: AppColors.primary.withOpacity(0.1),
        backgroundImage: (_participants.isNotEmpty && _participants.first.profileImageUrl != null)
            ? NetworkImage(_participants.first.profileImageUrl!)
            : null,
        child: (_participants.isEmpty || _participants.first.profileImageUrl == null)
            ? Icon(_participants.length > 1 ? Icons.group : Icons.person, color: AppColors.primary, size: 32)
            : null,
      ),
      title: Text(
        _participants.length > 1 
            ? 'กลุ่ม (${_participants.length + 1})'
            : _participants.isNotEmpty 
                ? _participants.first.fullName 
                : 'กำลังโหลด...',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      subtitle: Text(
        widget.room.lastMessage ?? 'เริ่มส่งข้อความทักทาย...',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey[600]),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatTime(widget.room.updatedAt),
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    if (now.day == date.day && now.month == date.month && now.year == date.year) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day}/${date.month}';
  }
}
