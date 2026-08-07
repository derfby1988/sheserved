import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../data/models/health_article_models.dart';

/// Comment system header with sort dropdown.
class HealthArticleCommentHeader extends StatelessWidget {
  final String currentSort;
  final ValueChanged<String> onSortChanged;

  const HealthArticleCommentHeader({
    super.key,
    required this.currentSort,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'การแสดงความคิดเห็น',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Color(0xFF4A89C8),
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: currentSort,
                  items: const [
                    DropdownMenuItem(
                      value: 'oldest',
                      child: Text(
                        'เก่าที่สุด',
                        style: TextStyle(fontSize: 13, color: Colors.white),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'newest',
                      child: Text(
                        'ใหม่ที่สุด',
                        style: TextStyle(fontSize: 13, color: Colors.white),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'likes',
                      child: Text(
                        'สนใจมากที่สุด',
                        style: TextStyle(fontSize: 13, color: Colors.white),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'bookmarks',
                      child: Text(
                        'แนะนำมากที่สุด',
                        style: TextStyle(fontSize: 13, color: Colors.white),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null && value != currentSort) {
                      onSortChanged(value);
                    }
                  },
                  dropdownColor: const Color(0xFF5D9CDB),
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: Color(0xFFF1AE27),
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Individual comment item widget with slide actions and interaction buttons.
class HealthArticleCommentItem extends StatelessWidget {
  final HealthArticleComment comment;
  final String displayNumber;
  final String? parentDisplayNumber;
  final bool isOwnComment;
  final bool isArticleAuthor;
  final bool isExpanded;
  final bool isVisibilityLoading;
  final GlobalKey commentKey;
  final GlobalKey? likeIconKey;
  final GlobalKey? bookmarkIconKey;
  final String Function(DateTime) formatThaiDate;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleBookmark;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onToggleVisibility;
  final VoidCallback onShowEditHistory;

  const HealthArticleCommentItem({
    super.key,
    required this.comment,
    required this.displayNumber,
    this.parentDisplayNumber,
    required this.isOwnComment,
    required this.isArticleAuthor,
    required this.isExpanded,
    required this.isVisibilityLoading,
    required this.commentKey,
    this.likeIconKey,
    this.bookmarkIconKey,
    required this.formatThaiDate,
    required this.onToggleExpand,
    required this.onToggleLike,
    required this.onToggleBookmark,
    required this.onReply,
    required this.onEdit,
    required this.onToggleVisibility,
    required this.onShowEditHistory,
  });

  @override
  Widget build(BuildContext context) {
    final isReply = comment.parentId != null;
    final bool canEdit = isOwnComment;
    final bool canHideShow = isArticleAuthor;

    return Container(
      key: commentKey,
      margin: EdgeInsets.fromLTRB(isReply ? 60 : 20, 8, 20, 8),
      child: Slidable(
        key: ValueKey(comment.id),
        endActionPane: (canEdit || canHideShow)
            ? ActionPane(
                motion: const ScrollMotion(),
                extentRatio: (canEdit && canHideShow) ? 0.45 : 0.25,
                children: [
                  if (canHideShow)
                    SlidableAction(
                      onPressed: (context) {
                        if (!isVisibilityLoading) {
                          onToggleVisibility();
                        }
                      },
                      backgroundColor: comment.isHidden
                          ? const Color(0xFF4CAF50)
                          : Colors.red.shade400,
                      foregroundColor: Colors.white,
                      icon: comment.isHidden
                          ? Icons.visibility
                          : Icons.visibility_off,
                      label: comment.isHidden ? 'เปิดเผย' : 'ปิดกั้น',
                      autoClose: true,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  if (canEdit)
                    SlidableAction(
                      onPressed: (context) => onEdit(),
                      backgroundColor: const Color(0xFFF1AE27),
                      foregroundColor: Colors.white,
                      icon: Icons.edit,
                      label: 'แก้ไข',
                      autoClose: true,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                ],
              )
            : null,
        child: Stack(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              decoration: BoxDecoration(
                color: isOwnComment
                    ? Colors.white.withOpacity(0.15)
                    : Colors.white.withOpacity(0.05),
                border: Border.all(
                  color: isOwnComment
                      ? const Color(0xFF5D9CDB).withOpacity(0.5)
                      : Colors.white.withOpacity(0.2),
                  width: isOwnComment ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      if (isArticleAuthor && comment.editCount > 0) {
                        onShowEditHistory();
                      }
                    },
                    child: Text(
                      comment.content,
                      maxLines: isExpanded ? null : 3,
                      overflow: isExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: () {
                          if (isArticleAuthor && comment.editCount > 0) {
                            return Colors.red;
                          }
                          if (isOwnComment) {
                            return const Color(0xFF1A3B5D);
                          }
                          return Colors.white;
                        }(),
                        height: 1.5,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (comment.content.length > 100)
                        TextButton(
                          onPressed: onToggleExpand,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            isExpanded ? 'ย่อกลับ' : 'อ่านเพิ่ม',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(width: 16),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: const BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        child: comment.userImage != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  comment.userImage!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : const Icon(
                                Icons.person,
                                size: 20,
                                color: Colors.white70,
                              ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              comment.username ??
                                  'สมาชิกหมายเลข ${comment.userId.substring(0, 4)}',
                              style: const TextStyle(
                                color: Color(0xFFF1AE27),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  size: 10,
                                  color: Color(0xFFF1AE27),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  formatThaiDate(comment.createdAt),
                                  style: const TextStyle(
                                    color: Color(0xFFF1AE27),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _buildStatIcon(
                        comment.isLiked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        '${comment.likeCount}',
                        color: comment.isLiked
                            ? Colors.pinkAccent
                            : Colors.white,
                        onTap: onToggleLike,
                        iconKey: likeIconKey,
                      ),
                      _buildStatIcon(Icons.chat_bubble_outline, '0'),
                      _buildStatIcon(
                        comment.isBookmarked
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                        '',
                        color: comment.isBookmarked
                            ? const Color(0xFFFFD700)
                            : Colors.white,
                        onTap: onToggleBookmark,
                        iconKey: bookmarkIconKey,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1C40F).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'ความคิดเห็นที่ $displayNumber',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  if (parentDisplayNumber != null) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.reply, size: 12, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(
                      parentDisplayNumber!,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: onReply,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1AE27).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.reply, size: 14, color: Color(0xFFF1AE27)),
                          SizedBox(width: 4),
                          Text(
                            'ตอบกลับ',
                            style: TextStyle(
                              color: Color(0xFFF1AE27),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
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
    );
  }

  Widget _buildStatIcon(
    IconData icon,
    String value, {
    Color color = Colors.white,
    VoidCallback? onTap,
    GlobalKey? iconKey,
  }) {
    return GestureDetector(
      key: iconKey,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 2),
            Text(value, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}
