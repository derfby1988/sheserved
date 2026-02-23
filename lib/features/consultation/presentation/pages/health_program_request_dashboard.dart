import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../../services/service_locator.dart';
import '../../../chat/data/models/chat_models.dart';
import '../../data/repositories/consultation_repository.dart';

// ─── Model: Rich consultation entry with patient info ─────────────────────────
class ConsultationEntry {
  final String id;
  final String patientName;
  final String? patientAvatar;
  final String packageName;
  final double price;
  final String bodyArea;
  final String status;
  final DateTime requestedAt;
  final String roomId;

  ConsultationEntry({
    required this.id,
    required this.patientName,
    this.patientAvatar,
    required this.packageName,
    required this.price,
    required this.bodyArea,
    required this.status,
    required this.requestedAt,
    required this.roomId,
  });

  factory ConsultationEntry.fromMap(Map<String, dynamic> map) {
    final user = map['users'] as Map<String, dynamic>? ?? {};
    final firstName = user['first_name'] as String? ?? '';
    final lastName = user['last_name'] as String? ?? '';
    final patientName = '$firstName $lastName'.trim().isEmpty
        ? 'ผู้ป่วยไม่ระบุชื่อ'
        : '$firstName $lastName'.trim();

    final bodyAreaMap = map['body_area'] as Map<String, dynamic>? ?? {};
    String bodyArea = bodyAreaMap['area'] as String? ??
        bodyAreaMap['label'] as String? ??
        (bodyAreaMap.keys.isNotEmpty ? bodyAreaMap.keys.join(', ') : 'ไม่ระบุ');

    final userId = map['user_id'] as String? ?? 'unknown';
    final shortId =
        userId.length >= 8 ? userId.substring(0, 8) : userId;
    final roomId = 'consult_$shortId';

    return ConsultationEntry(
      id: map['id'] as String,
      patientName: patientName,
      patientAvatar: user['profile_image_url'] as String?,
      packageName: map['package_name'] as String? ?? 'ไม่ระบุแพ็คเกจ',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      bodyArea: bodyArea,
      status: map['status'] as String? ?? 'pending',
      requestedAt: DateTime.parse(map['created_at'] as String),
      roomId: roomId,
    );
  }
}

// ─── Dashboard Page ────────────────────────────────────────────────────────────
class HealthProgramRequestDashboard extends StatefulWidget {
  const HealthProgramRequestDashboard({super.key});

  @override
  State<HealthProgramRequestDashboard> createState() =>
      _HealthProgramRequestDashboardState();
}

class _HealthProgramRequestDashboardState
    extends State<HealthProgramRequestDashboard>
    with SingleTickerProviderStateMixin {
  ConsultationRepository get _repo =>
      ServiceLocator.instance.consultationRepository;

  List<ConsultationEntry> _all = [];
  List<ConsultationEntry> _filtered = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterStatus = 'all';

  static const _tabs = [
    {'value': 'all', 'label': 'ทั้งหมด'},
    {'value': 'pending', 'label': 'รอดำเนินการ'},
    {'value': 'in_progress', 'label': 'กำลังดำเนินการ'},
    {'value': 'completed', 'label': 'เสร็จสิ้น'},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final raw = await _repo.getAllRequestsWithUserInfo();
      final entries = raw.map(ConsultationEntry.fromMap).toList();
      if (mounted) {
        setState(() {
          _all = entries;
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Dashboard error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    _filtered = _all.where((e) {
      final matchStatus =
          _filterStatus == 'all' || e.status == _filterStatus;
      final q = _searchQuery.toLowerCase();
      final matchSearch = q.isEmpty ||
          e.patientName.toLowerCase().contains(q) ||
          e.packageName.toLowerCase().contains(q) ||
          e.bodyArea.toLowerCase().contains(q);
      return matchStatus && matchSearch;
    }).toList();
  }

  int get _total => _all.length;
  int get _pending => _all.where((e) => e.status == 'pending').length;
  int get _inProgress => _all.where((e) => e.status == 'in_progress').length;
  int get _completed => _all.where((e) => e.status == 'completed').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F0),
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [_buildAppBar()],
        body: _isLoading ? _buildLoading() : _buildBody(),
      ),
    );
  }

  // ─── Sliver App Bar ────
  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      stretch: true,
      backgroundColor: const Color(0xFF2D6A1F),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          onPressed: _loadData,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: const Text(
          'ร้องขอโปรแกรมรักษาสุขภาพ',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4A8B2C), Color(0xFF2D6A1F), Color(0xFF1A4D10)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 85, 16, 55),
            child: Row(
              children: [
                _statChip('ทั้งหมด', _total, Icons.list_alt, Colors.white),
                const SizedBox(width: 8),
                _statChip('รอดำเนินการ', _pending,
                    Icons.pending_outlined, Colors.orangeAccent),
                const SizedBox(width: 8),
                _statChip('กำลังดำเนินการ', _inProgress,
                    Icons.forum_outlined, Colors.lightBlueAccent),
                const SizedBox(width: 8),
                _statChip('เสร็จสิ้น', _completed,
                    Icons.check_circle_outline, Colors.greenAccent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statChip(String label, int count, IconData icon, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: accent, size: 16),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('$count',
                  style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8), fontSize: 9),
                  textAlign: TextAlign.center,
                  maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF4A8B2C)),
            SizedBox(height: 16),
            Text('กำลังโหลดรายการ...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );

  Widget _buildBody() {
    return Column(
      children: [
        _buildSearchFilter(),
        Expanded(
          child: _filtered.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: const Color(0xFF4A8B2C),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) => _buildCard(_filtered[i], i),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSearchFilter() {
    return Container(
      color: const Color(0xFFF0F4F0),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          // Search bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
            ),
            child: TextField(
              onChanged: (v) {
                setState(() => _searchQuery = v);
                _applyFilter();
              },
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              decoration: InputDecoration(
                hintText: 'ค้นหาผู้ป่วย แพ็คเกจ บริเวณอาการ...',
                hintStyle:
                    TextStyle(fontSize: 13, color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.search,
                    color: Color(0xFF4A8B2C), size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Status tabs
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final tab = _tabs[i];
                final active = _filterStatus == tab['value'];
                return GestureDetector(
                  onTap: () {
                    setState(() => _filterStatus = tab['value']!);
                    _applyFilter();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF4A8B2C)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active
                            ? const Color(0xFF4A8B2C)
                            : Colors.grey.shade300,
                      ),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                  color:
                                      const Color(0xFF4A8B2C).withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2))
                            ]
                          : [],
                    ),
                    child: Text(
                      tab['label']!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCard(ConsultationEntry e, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + index * 60),
      curve: Curves.easeOut,
      builder: (ctx, v, child) => Opacity(
          opacity: v,
          child:
              Transform.translate(offset: Offset(0, 20 * (1 - v)), child: child)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  _avatar(e),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.patientName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF1A1A1A))),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('d MMM yyyy  HH:mm').format(e.requestedAt),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  _statusBadge(e.status),
                ],
              ),
            ),

            // Info section
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBF8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _infoRow(Icons.spa_outlined, 'แพ็คเกจ',
                      e.packageName, const Color(0xFF4A8B2C)),
                  const SizedBox(height: 8),
                  _infoRow(Icons.location_on_outlined, 'บริเวณที่พบอาการ',
                      e.bodyArea, Colors.orange),
                  const SizedBox(height: 8),
                  _infoRow(Icons.payments_outlined, 'ราคา',
                      '${e.price.toInt()} บาท', Colors.blue),
                ],
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: _actionBtn(
                      icon: Icons.edit_note_rounded,
                      label: 'อัปเดตสถานะ',
                      textColor: Colors.grey.shade700,
                      bgColor: Colors.grey.shade100,
                      onTap: () => _showStatusSheet(e),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _actionBtn(
                      icon: Icons.chat_rounded,
                      label: 'เข้าห้องแชทผู้ป่วย',
                      textColor: Colors.white,
                      bgColor: const Color(0xFF4A8B2C),
                      onTap: () => _openChat(e),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(ConsultationEntry e) {
    if (e.patientAvatar != null && e.patientAvatar!.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(e.patientAvatar!),
        backgroundColor: const Color(0xFF4A8B2C).withOpacity(0.1),
      );
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: const Color(0xFF4A8B2C).withOpacity(0.15),
      child: Text(
        e.patientName.isNotEmpty ? e.patientName[0].toUpperCase() : 'P',
        style: const TextStyle(
            color: Color(0xFF2D6A1F),
            fontWeight: FontWeight.bold,
            fontSize: 18),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final cfg = _statusConfig(status);
    final color = cfg['color'] as Color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(cfg['label'] as String,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 10),
        Text('$label: ',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color textColor,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: bgColor == const Color(0xFF4A8B2C)
              ? [
                  BoxShadow(
                      color: const Color(0xFF4A8B2C).withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'ไม่พบผลการค้นหา "$_searchQuery"'
                : 'ยังไม่มีคำร้องขอ',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text('รูดหน้าลงเพื่อโหลดข้อมูลใหม่',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        ],
      ),
    );
  }

  void _showStatusSheet(ConsultationEntry entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text('อัปเดตสถานะ: ${entry.patientName}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
            ...['pending', 'in_progress', 'completed'].map((s) {
              final cfg = _statusConfig(s);
              final color = cfg['color'] as Color;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle)),
                title: Text(cfg['label'] as String),
                trailing: entry.status == s
                    ? const Icon(Icons.check, color: Color(0xFF4A8B2C))
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  await _repo.updateStatus(entry.id, s);
                  _loadData();
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _openChat(ConsultationEntry entry) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (ctx, anim, _) =>
            ExpertChatRoomPage(entry: entry),
        transitionsBuilder: (ctx, anim, _, child) => SlideTransition(
          position: Tween<Offset>(
                  begin: const Offset(1, 0), end: Offset.zero)
              .animate(CurvedAnimation(
                  parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  Map<String, dynamic> _statusConfig(String status) {
    switch (status) {
      case 'in_progress':
        return {'label': 'กำลังดำเนินการ', 'color': Colors.blue};
      case 'completed':
        return {'label': 'เสร็จสิ้น', 'color': const Color(0xFF4A8B2C)};
      default:
        return {'label': 'รอดำเนินการ', 'color': Colors.orange};
    }
  }
}

// ─── Expert Chat Room Page ──────────────────────────────────────────────────────
class ExpertChatRoomPage extends StatefulWidget {
  final ConsultationEntry entry;
  const ExpertChatRoomPage({super.key, required this.entry});

  @override
  State<ExpertChatRoomPage> createState() => _ExpertChatRoomPageState();
}

class _ExpertChatRoomPageState extends State<ExpertChatRoomPage> {
  final _chatRepo = ServiceLocator.instance.chatRepository;
  final _currentUser = ServiceLocator.instance.currentUser;

  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<_LocalMsg> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final chatMessages =
          await _chatRepo.getMessages(widget.entry.roomId);
      if (mounted) {
        final myId = _currentUser?.id;
        setState(() {
          _messages = chatMessages.map((m) => _LocalMsg(
                content: m.content,
                isMe: m.senderId == myId,
                sentAt: m.createdAt,
                type: m.type,
              )).toList();
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() {
      _isSending = true;
      _messages.add(_LocalMsg(
          content: text, isMe: true, sentAt: DateTime.now(), type: 'text'));
    });
    _msgController.clear();
    _scrollToBottom();

    try {
      final message = ChatMessage(
        id: const Uuid().v4(),
        roomId: widget.entry.roomId,
        senderId: _currentUser?.id ?? 'expert',
        content: text,
        createdAt: DateTime.now(),
        type: 'text',
        status: MessageStatus.sent,
      );
      await _chatRepo.sendMessage(message);
    } catch (e) {
      debugPrint('ExpertChat: send error $e');
    }

    if (mounted) setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D6A1F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white.withOpacity(0.2),
              child: Text(
                widget.entry.patientName.isNotEmpty
                    ? widget.entry.patientName[0].toUpperCase()
                    : 'P',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.entry.patientName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  Text(widget.entry.packageName,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded,
                color: Colors.white, size: 22),
            onPressed: _showPatientSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Patient info banner
          _buildBanner(),

          // Messages
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF4A8B2C)))
                : _messages.isEmpty
                    ? _buildEmptyChat()
                    : ListView.builder(
                        controller: _scrollController,
                        padding:
                            const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) =>
                            _buildBubble(_messages[i]),
                      ),
          ),

          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.medical_services_outlined,
              color: Color(0xFF4A8B2C), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  children: [
                    TextSpan(
                        text: widget.entry.patientName,
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                    const TextSpan(text: ' · '),
                    TextSpan(
                        text: widget.entry.packageName,
                        style:
                            const TextStyle(color: Color(0xFF4A8B2C))),
                    const TextSpan(text: ' · '),
                    TextSpan(
                        text: widget.entry.bodyArea,
                        style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.w500)),
                  ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_LocalMsg msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment:
            msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: msg.isMe
                ? const Color(0xFF4A8B2C)
                : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
              bottomRight: Radius.circular(msg.isMe ? 4 : 16),
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Column(
            crossAxisAlignment: msg.isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!msg.isMe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    widget.entry.patientName,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4A8B2C)),
                  ),
                ),
              Text(
                msg.content,
                style: TextStyle(
                    color:
                        msg.isMe ? Colors.white : Colors.black87,
                    fontSize: 14,
                    height: 1.4),
              ),
              const SizedBox(height: 3),
              Text(
                DateFormat('HH:mm').format(msg.sentAt),
                style: TextStyle(
                    fontSize: 9,
                    color: msg.isMe
                        ? Colors.white.withOpacity(0.6)
                        : Colors.grey.shade400),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF4A8B2C).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chat_bubble_outline,
                color: Color(0xFF4A8B2C), size: 36),
          ),
          const SizedBox(height: 16),
          const Text('เริ่มต้นการสนทนากับผู้ป่วย',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF2D6A1F))),
          const SizedBox(height: 6),
          Text('พิมพ์คำแนะนำได้เลยด้านล่างครับ',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildInput() {
    final hasText = _msgController.text.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -3))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7F5),
                borderRadius: BorderRadius.circular(23),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                controller: _msgController,
                style: const TextStyle(color: Colors.black87, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'ให้คำแนะนำด้านสุขภาพ...',
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sendMessage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                color: hasText
                    ? const Color(0xFF4A8B2C)
                    : Colors.grey.shade300,
                shape: BoxShape.circle,
                boxShadow: hasText
                    ? [
                        BoxShadow(
                            color:
                                const Color(0xFF4A8B2C).withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ]
                    : [],
              ),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  void _showPatientSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            const Text('ข้อมูลผู้ป่วย',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            _infoTile(Icons.person_outline, 'ชื่อ-นามสกุล',
                widget.entry.patientName),
            _infoTile(Icons.spa_outlined, 'แพ็คเกจที่เลือก',
                widget.entry.packageName),
            _infoTile(Icons.location_on_outlined, 'บริเวณที่พบอาการ',
                widget.entry.bodyArea),
            _infoTile(Icons.payments_outlined, 'ค่าใช้จ่าย',
                '${widget.entry.price.toInt()} บาท'),
            _infoTile(
                Icons.calendar_today_outlined,
                'วันที่ร้องขอ',
                DateFormat('d MMMM yyyy  HH:mm')
                    .format(widget.entry.requestedAt)),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF4A8B2C).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Icon(icon, color: const Color(0xFF4A8B2C), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Local message model ────────────────────────────────────────────────────────
class _LocalMsg {
  final String content;
  final bool isMe;
  final DateTime sentAt;
  final String type;

  _LocalMsg({
    required this.content,
    required this.isMe,
    required this.sentAt,
    required this.type,
  });
}
