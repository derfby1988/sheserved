import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
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

  String get _genderPref =>
      widget.groupData['gender_preference']?.toString() ?? 'ทุกเพศ';

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

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('ไม่สามารถแปลงไฟล์ภาพ PNG ได้');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.photo_library_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('บันทึกโปสเตอร์เชิญชวนสำเร็จ พร้อมส่งต่อให้เพื่อนแล้ว!'),
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
    final isSessionInvite = widget.sessionData != null;
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

    // Modern Luxury Theme Tokens
    const bgSheet = Color(0xFF090D16);
    const cardSurface = Color(0xFF131B2E);
    const cardBorder = Color(0xFF263554);
    const accentMint = Color(0xFF6DD5B1);
    const accentGold = Color(0xFFFFB300);

    return Container(
      decoration: const BoxDecoration(
        color: bgSheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // Header Title with Subtle Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accentMint.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
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
            const SizedBox(height: 6),
            Text(
              'แชร์หรือส่งต่อโปสเตอร์ VIP Pass ให้เพื่อนเพื่อเข้าร่วมก๊วน',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // ── MODERN VIP TICKET / POSTER CARD ──
            RepaintBoundary(
              key: _posterKey,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [cardSurface, Color(0xFF0F1523)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  border: Border.all(
                    color: cardBorder,
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentMint.withValues(alpha: 0.08),
                      blurRadius: 30,
                      spreadRadius: 2,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Pass Header Ribbon
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: accentMint,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'SHESERVED SPORT PASS',
                                style: TextStyle(
                                  color: accentMint,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _requiresApproval
                                  ? accentGold.withValues(alpha: 0.15)
                                  : accentMint.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _requiresApproval ? 'ก๊วนปิด (รออนุมัติ)' : 'ก๊วนเปิด (เข้าทันที)',
                              style: TextStyle(
                                color: _requiresApproval ? accentGold : accentMint,
                                fontSize: 10.5,
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
                          // Group Avatar / Sport Icon Circle
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  accentMint.withValues(alpha: 0.3),
                                  Colors.transparent,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: accentMint.withValues(alpha: 0.6),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accentMint.withValues(alpha: 0.25),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: Center(
                              child: _groupLogoUrl != null && _groupLogoUrl!.isNotEmpty
                                  ? ClipOval(
                                      child: Image.network(
                                        _groupLogoUrl!,
                                        width: 58,
                                        height: 58,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, error, stackTrace) => Icon(
                                          _getSportIcon(_sportType),
                                          color: accentMint,
                                          size: 30,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      _getSportIcon(_sportType),
                                      color: accentMint,
                                      size: 30,
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
                          ),
                          const SizedBox(height: 10),

                          // Sport & Feature Chips Row
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _buildMetaPill(
                                icon: _getSportIcon(_sportType),
                                text: _sportType,
                                color: accentMint,
                              ),
                              _buildMetaPill(
                                icon: Icons.people_alt_rounded,
                                text: _genderPref,
                                color: const Color(0xFF60A5FA),
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
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: accentGold.withValues(alpha: 0.3),
                                ),
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
                                        Text(
                                          sessionTimeText,
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.8),
                                            fontSize: 12.5,
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
                          // QR Container with Bracket Framing
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
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

                          // Scan Callout
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 15,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'สแกน QR Code เพื่อเปิดก๊วนในแอป Sheserved',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 12,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
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
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label: const Text(
                      'คัดลอกลิงก์',
                      style: TextStyle(fontWeight: FontWeight.w600),
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
                          color: accentMint.withValues(alpha: 0.3),
                          blurRadius: 14,
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
                      label: const Text(
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
              ],
            ),
          ],
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
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
                        ? Colors.white.withValues(alpha: 0.15)
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
                border: Border.all(color: cardBorder, width: 1.2),
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
                border: Border.all(color: cardBorder, width: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
