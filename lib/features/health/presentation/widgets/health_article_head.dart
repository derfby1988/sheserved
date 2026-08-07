import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/auth_service.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../data/models/health_article_models.dart';
import 'health_article_misc.dart';

/// Article head section (Area 3) showing title, author, content, and bookmark.
class HealthArticleHead extends StatefulWidget {
  final HealthArticle? article;
  final int totalComments;
  final bool isTitleExpanded;
  final bool isContentExpanded;
  final List<ArticleEditHistory> editHistory;
  final VoidCallback onToggleTitleExpand;
  final VoidCallback onToggleContentExpand;
  final VoidCallback onReply;
  final VoidCallback onEditArticle;
  final VoidCallback onToggleBookmark;
  final VoidCallback onManageTagRequests;
  final GlobalKey bookmarkKey;
  final String Function(DateTime) formatThaiDate;

  const HealthArticleHead({
    super.key,
    required this.article,
    required this.totalComments,
    required this.isTitleExpanded,
    required this.isContentExpanded,
    required this.editHistory,
    required this.onToggleTitleExpand,
    required this.onToggleContentExpand,
    required this.onReply,
    required this.onEditArticle,
    required this.onToggleBookmark,
    required this.onManageTagRequests,
    required this.bookmarkKey,
    required this.formatThaiDate,
  });

  @override
  State<HealthArticleHead> createState() => _HealthArticleHeadState();
}

class _HealthArticleHeadState extends State<HealthArticleHead> {
  @override
  Widget build(BuildContext context) {
    if (widget.article == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF6CB0C5).withOpacity(0.6),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: widget.onToggleTitleExpand,
                                  child: Text(
                                    widget.article!.title,
                                    maxLines: widget.isTitleExpanded ? null : 2,
                                    overflow: widget.isTitleExpanded
                                        ? TextOverflow.visible
                                        : TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontFamily: 'SukhumvitSet',
                                      shadows: [
                                        Shadow(
                                          color: Colors.black26,
                                          offset: Offset(0, 2),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'เปิดดู ${widget.article!.viewCount} • ${widget.totalComments} ความคิดเห็น • ${widget.article!.bookmarkCount} ท่านสนใจ',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                    fontFamily: 'SukhumvitSet',
                                  ),
                                ),
                                if (AuthService.instance.currentUser?.id ==
                                    widget.article!.authorId)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: TextButton.icon(
                                      onPressed: widget.onEditArticle,
                                      icon: const Icon(
                                        Icons.edit,
                                        size: 16,
                                        color: Color(0xFFF1AE27),
                                      ),
                                      label: const Text(
                                        'แก้ไขบทความ',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFF1AE27),
                                          fontFamily: 'SukhumvitSet',
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 0,
                                          vertical: 0,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        alignment: Alignment.centerLeft,
                                      ),
                                    ),
                                  ),
                                if (widget.article!.editCount > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white24,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'แก้ไขแล้ว',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'SukhumvitSet',
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.access_time,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.formatThaiDate(
                                      widget.article!.createdAt,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontFamily: 'SukhumvitSet',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: _showAuthorProfile,
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: Colors.white70,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: widget.article!.authorImage != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            26,
                                          ),
                                          child: Image.network(
                                            widget.article!.authorImage!,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.person,
                                          color: Colors.grey,
                                          size: 30,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final contentStyle = TextStyle(
                            fontSize: 16,
                            height: 1.6,
                            color: Colors.white.withOpacity(0.8),
                            fontFamily: 'SukhumvitSet',
                          );

                          if (widget.isContentExpanded) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _renderArticleContent(
                                  widget.article!.content,
                                  contentStyle,
                                ),
                                if (AuthService.instance.currentUser?.id ==
                                    widget.article!.authorId)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: TextButton.icon(
                                      onPressed: widget.onManageTagRequests,
                                      icon: const Icon(
                                        Icons.notifications_active_outlined,
                                        size: 16,
                                        color: Colors.redAccent,
                                      ),
                                      label: const Text(
                                        'คำขอแท็กสินค้าใหม่',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.redAccent,
                                          fontFamily: 'SukhumvitSet',
                                          fontWeight:
                                              FontWeight.w900,
                                        ),
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        alignment: Alignment.centerLeft,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                GestureDetector(
                                  onTap: widget.onToggleContentExpand,
                                  child: const Text(
                                    'ย่อเนื้อหา',
                                    style: TextStyle(
                                      color: Color(0xFFF1AE27),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      fontFamily: 'SukhumvitSet',
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _renderArticleContent(
                                widget.article!.content,
                                contentStyle,
                                maxLines: 3,
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: widget.onToggleContentExpand,
                                child: const Text(
                                  'แสดงเนื้อหาทั้งหมด...',
                                  style: TextStyle(
                                    color: Color(0xFFF1AE27),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    fontFamily: 'SukhumvitSet',
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: GestureDetector(
                          onTap: widget.onReply,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.reply,
                                  size: 16,
                                  color: Color(0xFFF1AE27),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'ตอบกลับ',
                                  style: TextStyle(
                                    color: Color(0xFFF1AE27),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'SukhumvitSet',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 24,
                  child: Container(
                    key: widget.bookmarkKey,
                    child: RibbonBookmark(
                      isBookmarked: widget.article?.isBookmarked ?? false,
                      onTap: widget.onToggleBookmark,
                      height: 30,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _renderArticleContent(
    String content,
    TextStyle style, {
    int? maxLines,
  }) {
    try {
      final List<dynamic> blocks = jsonDecode(content);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks.take(maxLines != null ? 1 : blocks.length).map((
          block,
        ) {
          final type = block['type'];
          final val = block['content'] as String;

          if (type == 'text') {
            final history = widget.editHistory.isNotEmpty
                ? widget.editHistory.first
                : null;
            String? oldText;
            if (history != null) {
              try {
                final oldBlocks = jsonDecode(history.oldContent) as List;
                int textIndex = 0;
                for (int i = 0; i < blocks.indexOf(block); i++) {
                  if (blocks[i]['type'] == 'text') textIndex++;
                }

                int currentIdx = 0;
                for (var ob in oldBlocks) {
                  if (ob['type'] == 'text') {
                    if (currentIdx == textIndex) {
                      oldText = ob['content'];
                      break;
                    }
                    currentIdx++;
                  }
                }
              } catch (_) {}
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: RichTextRenderer(
                text: val,
                style: style,
                maxLines: maxLines,
                oldText: oldText,
                onDiffTap: (current, original) =>
                    _showDiffDialog(current, original),
              ),
            );
          } else if (type == 'image') {
            final alignment = block['alignment'] ?? 'full';
            final height = (block['height'] ?? 200).toDouble();

            Alignment widgetAlignment;
            double widgetWidthFactor;
            switch (alignment) {
              case 'left':
                widgetAlignment = Alignment.centerLeft;
                widgetWidthFactor = 0.6;
                break;
              case 'right':
                widgetAlignment = Alignment.centerRight;
                widgetWidthFactor = 0.6;
                break;
              case 'center':
                widgetAlignment = Alignment.center;
                widgetWidthFactor = 0.8;
                break;
              default:
                widgetAlignment = Alignment.center;
                widgetWidthFactor = 1.0;
            }

            return Align(
              alignment: widgetAlignment,
              child: FractionallySizedBox(
                widthFactor: widgetWidthFactor,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  height: height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    image: DecorationImage(
                      image: NetworkImage(val),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }).toList(),
      );
    } catch (e) {
      return Text(
        content,
        style: style,
        maxLines: maxLines,
        overflow: maxLines != null ? TextOverflow.ellipsis : null,
      );
    }
  }

  void _showAuthorProfile() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 50,
                backgroundImage: NetworkImage('https://i.pravatar.cc/200'),
              ),
              const SizedBox(height: 16),
              const Text(
                'พญ. สมศรี สวยงาม',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Text(
                'ผู้เชี่ยวชาญด้านเวชศาสตร์ป้องกัน',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'มีประสบการณ์การทำงานด้านสุขภาพสตรีมากกว่า 15 ปี เน้นการดูแลสุขภาพแบบองค์รวมและการป้องกันก่อนเกิดโรค',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('ติดตาม'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDiffDialog(String current, String original) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A3B5D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'ประวัติการแก้ไข',
          style: TextStyle(
            color: Color(0xFFF1AE27),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
            maxWidth: MediaQuery.of(context).size.width,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ข้อความเดิม:',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    original,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'ข้อความปัจจุบัน:',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    current,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'ปิด',
              style: TextStyle(color: Color(0xFFF1AE27)),
            ),
          ),
        ],
      ),
    );
  }
}
