import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/features/sport_club/services/sport_club_deep_link_service.dart';

/// Modern VIP Sport Pass Invite Poster Sheet
class GroupInvitePosterSheet extends StatefulWidget {
  final Map<String, dynamic> groupData;
  final Map<String, dynamic>? sessionData;

  const GroupInvitePosterSheet({
    super.key,
    required this.groupData,
    this.sessionData,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> groupData,
    Map<String, dynamic>? sessionData,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GroupInvitePosterSheet(
        groupData: groupData,
        sessionData: sessionData,
      ),
    );
  }

  @override
  State<GroupInvitePosterSheet> createState() => _GroupInvitePosterSheetState();
}

class _GroupInvitePosterSheetState extends State<GroupInvitePosterSheet> {
  final GlobalKey _posterKey = GlobalKey();
  bool _isSaving = false;

  String get _groupId =>
      widget.groupData['id']?.toString() ??
      widget.groupData['group_id']?.toString() ??
      '';

  String? get _sessionId => widget.sessionData?['id']?.toString();

  String get _inviteUrl => SportClubDeepLinkService.buildGroupInviteUrl(
        _groupId,
        sessionId: _sessionId,
      );

  String get _groupName =>
      widget.groupData['name']?.toString() ??
      widget.groupData['title']?.toString() ??
      'ก๊วนกีฬา Sheserved';

  String get _sportType =>
      widget.groupData['sport_type']?.toString() ??
      widget.groupData['sport']?.toString() ??
      'กีฬา';

  String? get _groupLogoUrl =>
      widget.groupData['image_url']?.toString() ??
      widget.groupData['banner_url']?.toString();

  bool get _requiresApproval =>
      widget.groupData['requires_owner_approval'] == true;

  String get _sportTypeThai {
    final raw = _sportType.trim();
    final lower = raw.toLowerCase();
    if (lower.contains('badminton') || lower.contains('แบด')) return 'แบดมินตัน';
    if (lower.contains('football') || lower.contains('บอล') || lower.contains('soccer')) return 'ฟุตบอล';
    if (lower.contains('basketball') || lower.contains('บาส')) return 'บาสเกตบอล';
    if (lower.contains('tennis') || lower.contains('เทนนิส')) return 'เทนนิส';
    if (lower.contains('table_tennis') || lower.contains('ปิงปอง')) return 'ปิงปอง';
    if (lower.contains('running') || lower.contains('run') || lower.contains('วิ่ง')) return 'วิ่ง';
    if (lower.contains('swimming') || lower.contains('ว่ายน้ำ')) return 'ว่ายน้ำ';
    if (lower.contains('volleyball') || lower.contains('วอลเลย์')) return 'วอลเลย์บอล';
    if (lower.contains('pickleball') || lower.contains('พิคเคิล')) return 'พิคเคิลบอล';
    if (lower.contains('gym') || lower.contains('fitness') || lower.contains('ฟิตเนส')) return 'ฟิตเนส';
    if (raw.isEmpty || raw == 'กีฬา') return 'กีฬา';
    return raw;
  }

  String get _genderPrefThai {
    final raw = widget.groupData['gender_preference']?.toString().toLowerCase().trim();
    switch (raw) {
      case 'male':
      case 'ผู้ชาย':
        return 'เฉพาะผู้ชาย';
      case 'female':
      case 'ผู้หญิง':
        return 'เฉพาะผู้หญิง';
      case 'any':
      case 'all':
      case 'ทุกเพศ':
      case null:
      default:
        return 'เปิดรับทุกเพศ';
    }
  }

  String get _approvalStatusThai =>
      _requiresApproval ? 'ต้องรออนุมัติ' : 'เข้าได้ทันที';

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _inviteUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('คัดลอกลิงก์เชิญเรียบร้อยแล้ว'),
          ],
        ),
        backgroundColor: AppColors.secondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }

  Future<void> _savePosterImage() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final boundary =
          _posterKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('ไม่สามารถ Render การ์ดภาพได้');
      }

      // Add a small delay to ensure rendering is complete
      await Future.delayed(const Duration(milliseconds: 100));

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('ไม่สามารถแปลงไฟล์ภาพ PNG ได้');
      }

      final uint8List = byteData.buffer.asUint8List();

      bool hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        hasAccess = await Gal.requestAccess(toAlbum: true);
      }

      if (hasAccess) {
        await Gal.putImageBytes(uint8List);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.photo_library_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text('บันทึกโปสเตอร์เชิญชวนลงในอัลบั้มสำเร็จแล้ว!'),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        );
      } else {
        // Fallback to OS Share
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/sheserved_invite_${DateTime.now().millisecondsSinceEpoch}.png');
        await file.writeAsBytes(uint8List);
        
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'มาร่วม${isSessionInvite ? 'รอบนัดกิจกรรม' : 'ก๊วนกีฬา'} Sheserved ด้วยกันเถอะ!\n$_inviteUrl',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ไม่สามารถบันทึกภาพได้: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool get isSessionInvite => widget.sessionData != null;

  IconData _getSportIcon(String sport) {
    final s = sport.toLowerCase();
    if (s.contains('badminton') || s.contains('แบด')) return Icons.sports_tennis_rounded;
    if (s.contains('football') || s.contains('บอล')) return Icons.sports_soccer_rounded;
    if (s.contains('basketball') || s.contains('บาส')) return Icons.sports_basketball_rounded;
    if (s.contains('run') || s.contains('วิ่ง')) return Icons.directions_run_rounded;
    if (s.contains('swim') || s.contains('ว่าย')) return Icons.pool_rounded;
    if (s.contains('tennis') || s.contains('เทนนิส')) return Icons.sports_tennis_rounded;
    return Icons.sports_handball_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final sessionTitle = widget.sessionData?['title']?.toString() ??
        widget.sessionData?['name']?.toString() ??
        'รอบกิจกรรมพิเศษ';

    String? sessionTimeText;
    if (isSessionInvite &&
        widget.sessionData?['starts_at'] != null &&
        widget.sessionData?['ends_at'] != null) {
      try {
        final start = DateTime.parse(widget.sessionData!['starts_at'].toString()).toLocal();
        final end = DateTime.parse(widget.sessionData!['ends_at'].toString()).toLocal();
        sessionTimeText = formatThaiSessionRange(start, end);
      } catch (_) {}
    }

    final placeName = widget.sessionData?['place_name']?.toString();

    // Modern Frosted Glass Theme Tokens
    const bgSheet = Color(0xFF0A101D);
    const cardBorder = Color(0xFF263554);
    const accentMint = Color(0xFF6DD5B1);
    const accentGold = Color(0xFFFFB300);
    const accentBlue = Color(0xFF60A5FA);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: bgSheet.withValues(alpha: 0.88),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.16),
                width: 1.2,
              ),
            ),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle Bar
                Center(
                  child: Container(
                    width: 44,
                    height: 4.5,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),

                // Header Title with Glowing Badge (Protected with FittedBox)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: accentMint.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: accentMint.withValues(alpha: 0.25),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.share_rounded,
                            size: 16,
                            color: accentMint,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isSessionInvite ? 'แชร์รอบนัดกิจกรรม' : 'เชิญเข้าร่วมก๊วนกีฬา',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'แชร์หรือส่งต่อโปสเตอร์ VIP Pass ให้เพื่อนเพื่อเข้าร่วมก๊วน',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // ── MODERN VIP TICKET / GLASS POSTER CARD ──
                RepaintBoundary(
                  key: _posterKey,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      children: [
                        // Glass Midnight Base
                        Positioned.fill(
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF0F192E), Color(0xFF080D18)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),
                        // Ambient Glow Orb 1 (Top Left / Mint Neon)
                        Positioned(
                          top: -40,
                          left: -40,
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  accentMint.withValues(alpha: 0.25),
                                  accentMint.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Ambient Glow Orb 2 (Bottom Right / Indigo Glow)
                        Positioned(
                          bottom: -40,
                          right: -40,
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  const Color(0xFF6366F1).withValues(alpha: 0.22),
                                  const Color(0xFF6366F1).withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Frosted Glass Layer Container
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.10),
                                Colors.white.withValues(alpha: 0.03),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accentMint.withValues(alpha: 0.10),
                                blurRadius: 30,
                                spreadRadius: 1,
                                offset: const Offset(0, 10),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Top Pass Header Ribbon (Protected from overflow)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.white.withValues(alpha: 0.08),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: accentMint,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: accentMint.withValues(alpha: 0.7),
                                                  blurRadius: 6,
                                                  spreadRadius: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Flexible(
                                            child: Text(
                                              'บัตรผ่านก๊วนกีฬา',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: accentMint,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.white.withValues(alpha: 0.15),
                                              ),
                                            ),
                                            child: const Text(
                                              'VIP',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                      decoration: BoxDecoration(
                                        color: _requiresApproval
                                            ? accentGold.withValues(alpha: 0.18)
                                            : accentMint.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _requiresApproval
                                              ? accentGold.withValues(alpha: 0.45)
                                              : accentMint.withValues(alpha: 0.45),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        _approvalStatusThai,
                                        style: TextStyle(
                                          color: _requiresApproval ? accentGold : accentMint,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Card Body Content
                              Padding(
                                padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                                child: Column(
                                  children: [
                                    // Group Avatar / Glowing Glass Circle
                                    Container(
                                      width: 68,
                                      height: 68,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          colors: [
                                            accentMint.withValues(alpha: 0.25),
                                            Colors.white.withValues(alpha: 0.05),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        border: Border.all(
                                          color: accentMint.withValues(alpha: 0.7),
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: accentMint.withValues(alpha: 0.3),
                                            blurRadius: 20,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: _groupLogoUrl != null && _groupLogoUrl!.isNotEmpty
                                            ? ClipOval(
                                                child: Image.network(
                                                  _groupLogoUrl!,
                                                  width: 60,
                                                  height: 60,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, error, stackTrace) => Icon(
                                                    _getSportIcon(_sportType),
                                                    color: accentMint,
                                                    size: 32,
                                                  ),
                                                ),
                                              )
                                            : Icon(
                                                _getSportIcon(_sportType),
                                                color: accentMint,
                                                size: 32,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    // Group Name
                                    Text(
                                      _groupName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 21,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.2,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 10),

                                    // Sport & Feature Chips Row (in Thai)
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        _buildMetaPill(
                                          icon: _getSportIcon(_sportType),
                                          text: _sportTypeThai,
                                          color: accentMint,
                                        ),
                                        _buildMetaPill(
                                          icon: Icons.people_alt_rounded,
                                          text: _genderPrefThai,
                                          color: accentBlue,
                                        ),
                                      ],
                                    ),

                                    // Session Card (When sharing a specific session)
                                    if (isSessionInvite) ...[
                                      const SizedBox(height: 16),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: accentGold.withValues(alpha: 0.35),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: accentGold.withValues(alpha: 0.08),
                                              blurRadius: 12,
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.event_note_rounded,
                                                    size: 16, color: accentGold),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    sessionTitle,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (sessionTimeText != null) ...[
                                              const SizedBox(height: 6),
                                              Row(
                                                children: [
                                                  Icon(Icons.schedule_rounded,
                                                      size: 14,
                                                      color: Colors.white.withValues(alpha: 0.6)),
                                                  const SizedBox(width: 6),
                                                  Flexible(
                                                    child: Text(
                                                      sessionTimeText,
                                                      style: TextStyle(
                                                        color: Colors.white.withValues(alpha: 0.8),
                                                        fontSize: 12.5,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            if (placeName != null && placeName.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(Icons.place_rounded,
                                                      size: 14,
                                                      color: Colors.white.withValues(alpha: 0.6)),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      placeName,
                                                      style: TextStyle(
                                                        color: Colors.white.withValues(alpha: 0.7),
                                                        fontSize: 12,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              // ── TICKET NOTCH & DASHED DIVIDER ──
                              _buildTicketDivider(cardBorder: cardBorder, bgSheet: bgSheet),

                              // QR Code Section
                              Padding(
                                padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
                                child: Column(
                                  children: [
                                    // QR Container with Glass Halo
                                    Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(22),
                                        boxShadow: [
                                          BoxShadow(
                                            color: accentMint.withValues(alpha: 0.22),
                                            blurRadius: 24,
                                            offset: const Offset(0, 4),
                                          ),
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.4),
                                            blurRadius: 16,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: QrImageView(
                                        data: _inviteUrl,
                                        version: QrVersions.auto,
                                        size: 164.0,
                                        backgroundColor: Colors.white,
                                        eyeStyle: const QrEyeStyle(
                                          eyeShape: QrEyeShape.square,
                                          color: Color(0xFF0F172A),
                                        ),
                                        dataModuleStyle: const QrDataModuleStyle(
                                          dataModuleShape: QrDataModuleShape.square,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    // Scan Callout with FittedBox to prevent ANY overflow
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.qr_code_scanner_rounded,
                                              size: 16,
                                              color: accentMint,
                                            ),
                                            const SizedBox(width: 7),
                                            Text(
                                              'สแกน QR Code เพื่อเปิดก๊วนในแอป Sheserved',
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.8),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── ACTION BUTTONS ──
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyLink,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.22),
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'คัดลอกลิงก์',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [accentMint, Color(0xFF45B095)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accentMint.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _savePosterImage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: const Color(0xFF0F172A),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF0F172A),
                                  ),
                                )
                              : const Icon(Icons.file_download_outlined, size: 19),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'บันทึกโปสเตอร์',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaPill({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketDivider({
    required Color cardBorder,
    required Color bgSheet,
  }) {
    return SizedBox(
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Dashed Line
          Positioned(
            left: 20,
            right: 20,
            child: Row(
              children: List.generate(
                26,
                (index) => Expanded(
                  child: Container(
                    height: 1.2,
                    color: index.isEven
                        ? Colors.white.withValues(alpha: 0.18)
                        : Colors.transparent,
                  ),
                ),
              ),
            ),
          ),
          // Left Notch
          Positioned(
            left: -10,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: bgSheet,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1.2,
                ),
              ),
            ),
          ),
          // Right Notch
          Positioned(
            right: -10,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: bgSheet,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
