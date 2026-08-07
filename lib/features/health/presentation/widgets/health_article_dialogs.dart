import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../pharmacy/data/models/medication_models.dart';
import '../../data/models/health_article_models.dart';
import '../../data/repositories/health_article_repository.dart';

/// Collection of dialog methods for the health article page.
/// All methods are static and take the necessary context and data as parameters.
class HealthArticleDialogs {
  /// Reply dialog for commenting on an article or replying to a comment.
  static void showReplyDialog(
    BuildContext context, {
    String? commentId,
    required List<HealthArticleComment> comments,
    required Future<HealthArticleComment?> Function(String content, {String? parentId}) onSubmit,
    required Future<void> Function(String commentId) onScrollToComment,
    required int totalRootComments,
    required String currentSort,
    required int currentPage,
    required Future<void> Function(int) changePage,
  }) {
    final controller = TextEditingController();
    HealthArticleComment? parentComment;
    if (commentId != null) {
      parentComment = comments.firstWhere((c) => c.id == commentId);
    }

    final UserModel? authCurrentUser = AuthService.instance.currentUser;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A3B5D).withOpacity(0.95),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        commentId != null
                            ? 'ตอบกลับความคิดเห็นของ ${parentComment?.username ?? 'สมาชิก'}'
                            : 'แสดงความคิดเห็นต่อบทความนี้',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          enabled: !isSubmitting,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 15,
                          ),
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'เขียนความคิดเห็นของคุณที่นี่...',
                            hintStyle: TextStyle(
                              color: Colors.black.withOpacity(0.4),
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: const BoxDecoration(
                              color: Colors.white24,
                              shape: BoxShape.circle,
                            ),
                            child: authCurrentUser?.profileImageUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.network(
                                      authCurrentUser!.profileImageUrl!,
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
                            child: Text(
                              authCurrentUser?.username ?? 'คุณ',
                              style: const TextStyle(
                                color: Color(0xFFF1AE27),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text(
                              'ยกเลิก',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final content = controller.text;
                                    if (content.trim().isNotEmpty) {
                                      setDialogState(() => isSubmitting = true);
                                      try {
                                        final newComment = await onSubmit(
                                          content,
                                          parentId: commentId,
                                        );
                                        if (context.mounted && newComment != null) {
                                          Navigator.pop(context);

                                          if (commentId == null) {
                                            final totalRootPages =
                                                (totalRootComments / 10)
                                                    .ceil();

                                            if (currentSort == 'oldest' &&
                                                currentPage !=
                                                    totalRootPages) {
                                              await changePage(totalRootPages);
                                            } else if (currentSort ==
                                                    'newest' &&
                                                currentPage != 1) {
                                              await changePage(1);
                                            }
                                          }

                                          onScrollToComment(newComment.id);
                                        }
                                      } catch (e) {
                                        setDialogState(
                                          () => isSubmitting = false,
                                        );
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF1AE27),
                              foregroundColor: Colors.black87,
                              disabledBackgroundColor: const Color(
                                0xFFF1AE27,
                              ).withOpacity(0.5),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black87,
                                    ),
                                  )
                                : const Text(
                                    'ส่งคำตอบ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1C40F),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      commentId != null
                          ? 'ตอบกลับ คห.ที่ ${parentComment?.commentNumber}'
                          : 'ตอบกลับบทความ',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Edit dialog for editing an existing comment.
  static void showEditDialog(
    BuildContext context, {
    required HealthArticleComment comment,
    required Future<HealthArticleComment?> Function(String commentId, String content) onUpdate,
    required Future<void> Function(String commentId) onScrollToComment,
  }) {
    final controller = TextEditingController(text: comment.content);
    final UserModel? authCurrentUser = AuthService.instance.currentUser;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A3B5D).withOpacity(0.95),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'แก้ไขความคิดเห็นของคุณ',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          enabled: !isSubmitting,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 15,
                          ),
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'เขียนความคิดเห็นของคุณที่นี่...',
                            hintStyle: TextStyle(
                              color: Colors.black.withOpacity(0.4),
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: const BoxDecoration(
                              color: Colors.white24,
                              shape: BoxShape.circle,
                            ),
                            child: authCurrentUser?.profileImageUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.network(
                                      authCurrentUser!.profileImageUrl!,
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
                            child: Text(
                              authCurrentUser?.username ?? 'คุณ',
                              style: const TextStyle(
                                color: Color(0xFFF1AE27),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text(
                              'ยกเลิก',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final content = controller.text;
                                    if (content.trim().isNotEmpty) {
                                      setDialogState(() => isSubmitting = true);
                                      try {
                                        final updatedComment =
                                            await onUpdate(
                                              comment.id,
                                              content,
                                            );
                                        if (context.mounted && updatedComment != null) {
                                          Navigator.pop(context);
                                          onScrollToComment(comment.id);
                                        }
                                      } catch (e) {
                                        setDialogState(
                                          () => isSubmitting = false,
                                        );
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF1AE27),
                              foregroundColor: Colors.black87,
                              disabledBackgroundColor: const Color(
                                0xFFF1AE27,
                              ).withOpacity(0.5),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black87,
                                    ),
                                  )
                                : const Text(
                                    'บันทึกการแก้ไข',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1C40F),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'แก้ไขคำตอบ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Edit history dialog showing past edits of a comment.
  static Future<void> showEditHistoryDialog(
    BuildContext context, {
    required HealthArticleComment comment,
    required String Function(DateTime) formatThaiDate,
  }) async {
    final repository = ServiceLocator.instance.healthArticleRepository;
    final history = await repository.getCommentEditHistory(comment.id);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 500),
          decoration: BoxDecoration(
            color: const Color(0xFF1A3B5D),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1AE27).withOpacity(0.2),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.history, color: Color(0xFFF1AE27)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'ประวัติการแก้ไข',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Text(
                    'ไม่มีประวัติการแก้ไข',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final edit = history[index];
                      return _buildEditHistoryItem(edit, formatThaiDate);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildEditHistoryItem(
    CommentEditHistory edit,
    String Function(DateTime) formatThaiDate,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1AE27),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'ครั้งที่ ${edit.editNumber}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                formatThaiDate(edit.editedAt),
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.remove_circle_outline,
                  size: 14,
                  color: Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    edit.oldContent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.add_circle_outline,
                  size: 14,
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    edit.newContent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Edit article dialog - confirmation before editing article text.
  static void showEditArticleDialog(
    BuildContext context, {
    required HealthArticle article,
    required VoidCallback onProceed,
  }) {
    final isAuthor = AuthService.instance.currentUser?.id == article.authorId;
    if (!isAuthor) return;

    if (article.editCount >= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'คุณได้ทำการแก้ไขบทความไปแล้ว 1 ครั้ง ไม่สามารถแก้ไขได้อีก',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.white,
          title: const Text(
            'แก้ไขบทความ',
            style: TextStyle(
              color: Color(0xFF1A3B5D),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'คุณได้รับอนุญาติให้แก้ไขเฉพาะข้อความได้เพียงครั้งเดียวเท่านั้น โดยจะมีการแจ้งเตือนการแก้ไขไปที่เจ้าของสินค้าที่ฝากไว้กับร้านคุณ',
            style: TextStyle(color: Colors.black87, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'ยกเลิก',
                style: TextStyle(color: Colors.black54),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                onProceed();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF1AE27),
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'ดำเนินการต่อ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Full-screen article editor dialog.
  static void showEditArticleScreen(
    BuildContext context, {
    required HealthArticle article,
    required List<HealthArticleProduct> products,
    required HealthArticleRepository repository,
    required VoidCallback onDataChanged,
  }) {
    List<dynamic> parsedBlocks;
    try {
      parsedBlocks = jsonDecode(article.content);
    } catch (e) {
      parsedBlocks = [
        {'type': 'text', 'content': article.content},
      ];
    }

    final List<TextEditingController> controllers = [];
    final originalBlocks = parsedBlocks;

    for (var block in originalBlocks) {
      if (block['type'] == 'text') {
        controllers.add(TextEditingController(text: block['content']));
      }
    }

    List<String> currentTags = products
        .where((p) => p.taggedById == article.authorId)
        .map((p) => p.name)
        .toList();

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'EditArticle',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        bool isSubmitting = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.black),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Text(
                  'แก้ไขข้อความบทความ',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            setModalState(() => isSubmitting = true);

                            int textIndex = 0;
                            final List<Map<String, dynamic>> newBlocks = [];
                            for (var block in originalBlocks) {
                              if (block['type'] == 'text') {
                                newBlocks.add({
                                  ...block as Map<String, dynamic>,
                                  'content': controllers[textIndex].text,
                                });
                                textIndex++;
                              } else {
                                newBlocks.add(block as Map<String, dynamic>);
                              }
                            }

                            final newContentJson = jsonEncode(newBlocks);
                            final success = await repository.editArticleText(
                              article: article,
                              newContent: newContentJson,
                            );

                            if (AuthService.instance.currentUser != null) {
                              await repository.editArticleProducts(
                                articleId: article.id,
                                userId: AuthService.instance.currentUser!.id,
                                products: currentTags
                                    .map(
                                      (p) => {
                                        'name': p,
                                        'tag_type': 'medication',
                                      },
                                    )
                                    .toList(),
                              );
                            }

                            if (success) {
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'บันทึกการแก้ไขสำเร็จ',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                                onDataChanged();
                              }
                            } else {
                              setModalState(() => isSubmitting = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'เกิดข้อผิดพลาดในการบันทึก',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Color(0xFFF1AE27),
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'บันทึก',
                            style: TextStyle(
                              color: Color(0xFFF1AE27),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ],
              ),
              body: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: originalBlocks.length,
                      itemBuilder: (context, index) {
                        final block = originalBlocks[index];
                        if (block['type'] == 'text') {
                          int controllerIndex = 0;
                          for (int i = 0; i < index; i++) {
                            if (originalBlocks[i]['type'] == 'text')
                              controllerIndex++;
                          }
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: TextField(
                              controller: controllers[controllerIndex],
                              maxLines: null,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                height: 1.6,
                              ),
                              decoration: InputDecoration(
                                hintText: 'พิมพ์ข้อความ...',
                                hintStyle: TextStyle(
                                  color: Colors.black.withOpacity(0.3),
                                ),
                                contentPadding: const EdgeInsets.all(16),
                                border: InputBorder.none,
                              ),
                            ),
                          );
                        } else if (block['type'] == 'image') {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            height: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              image: DecorationImage(
                                image: NetworkImage(block['content']),
                                fit: BoxFit.contain,
                              ),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                '(ไม่สามารถแก้ไขรูปภาพได้)',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Colors.grey[200]!)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'แก้ไขแท็กยาของคุณ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ...currentTags.map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFCDE4F5),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF5D9CDB,
                                    ).withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      tag,
                                      style: const TextStyle(
                                        color: Color(0xFF5D9CDB),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () => setModalState(
                                        () => currentTags.remove(tag),
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Color(0xFF5D9CDB),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                showAddTagDialog(context, (tag) {
                                  if (!currentTags.contains(tag)) {
                                    setModalState(() => currentTags.add(tag));
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add,
                                      size: 14,
                                      color: Colors.black54,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'เพิ่มยา',
                                      style: TextStyle(
                                        color: Colors.black54,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Request tag dialog for asking to tag a product in the article.
  static Future<void> showRequestTagDialog(
    BuildContext context, {
    required String articleId,
    required VoidCallback onRefreshProducts,
  }) async {
    if (AuthService.instance.currentUser == null) {
      await Navigator.pushNamed(context, '/login');
      if (AuthService.instance.currentUser == null) return;
    }

    List<MedicationModel> searchResults = [];
    bool isSearching = false;
    bool isSubmitting = false;
    final searchController = TextEditingController();
    String searchQuery = '';

    final popularTags = [
      'พาราเซตามอล',
      'วิตามิน ซี',
      'โอเมก้า 3',
      'แคลเซียม',
      'สังกะสี (Zinc)',
      'ไอบูโพรเฟน',
      'ยาแก้แพ้',
      'หน้ากากอนามัย',
    ];

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> performSearch(String query) async {
                if (query.isEmpty) {
                  setModalState(() {
                    searchResults = [];
                    isSearching = false;
                  });
                  return;
                }
                setModalState(() => isSearching = true);
                try {
                  final pharmacyRepo =
                      ServiceLocator.instance.pharmacyRepository;
                  final results = await pharmacyRepo.getMedications(
                    searchQuery: query,
                    pageSize: 10,
                  );
                  setModalState(() {
                    searchResults = results;
                    isSearching = false;
                  });
                } catch (e) {
                  setModalState(() => isSearching = false);
                }
              }

              Future<void> submitRequest(MedicationModel medication) async {
                setModalState(() => isSubmitting = true);
                try {
                  final success = await ServiceLocator
                      .instance
                      .healthArticleRepository
                      .requestArticleProduct(
                        articleId: articleId,
                        userId: AuthService.instance.userId!,
                        name: medication.tradeName,
                        url: null,
                        imageUrl: medication.imageUrl,
                      );

                  if (!context.mounted) return;

                  if (success) {
                    onRefreshProducts();
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'ส่งคำขอระบุแท็กแล้ว รอเจ้าของบทความอนุมัติ',
                        ),
                      ),
                    );
                  } else {
                    setModalState(() => isSubmitting = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'บันทึกคำขอไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  setModalState(() => isSubmitting = false);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
                }
              }

              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                backgroundColor: Colors.white,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'ขอระบุแท็กยาและผลิตภัณฑ์สุขภาพ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              fontFamily: 'SukhumvitSet',
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'ค้นหายาหรือผลิตภัณฑ์ที่ต้องการระบุในบทความนี้',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                          fontFamily: 'SukhumvitSet',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: searchController,
                        onChanged: (val) {
                          setModalState(() => searchQuery = val);
                          performSearch(val);
                        },
                        style: const TextStyle(fontFamily: 'SukhumvitSet'),
                        decoration: InputDecoration(
                          hintText: 'พิมพ์ชื่อยา หรือ ยี่ห้อ...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    searchController.clear();
                                    searchQuery = '';
                                    performSearch('');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: isSearching
                            ? const Center(child: CircularProgressIndicator())
                            : searchQuery.isEmpty
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'ยายอดนิยม',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      fontFamily: 'SukhumvitSet',
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: popularTags.map((tag) {
                                      return InkWell(
                                        onTap: () {
                                          setModalState(() {
                                            searchController.text = tag;
                                            searchQuery = tag;
                                          });
                                          performSearch(tag);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: Colors.grey[300]!,
                                            ),
                                          ),
                                          child: Text(
                                            tag,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontFamily: 'SukhumvitSet',
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  const Spacer(),
                                  Center(
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.search,
                                          size: 48,
                                          color: Colors.grey[200],
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'พิมพ์เพื่อค้นหาสินค้าที่ต้องการ',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 13,
                                            fontFamily: 'SukhumvitSet',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                ],
                              )
                            : searchResults.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 48,
                                      color: Colors.grey[300],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'ไม่พบสินค้าชื่อ "$searchQuery"',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontFamily: 'SukhumvitSet',
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: searchResults.length,
                                itemBuilder: (context, idx) {
                                  final med = searchResults[idx];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: med.imageUrl != null
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.network(
                                                med.imageUrl!,
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          : const Icon(Icons.medication),
                                    ),
                                    title: Text(
                                      med.tradeName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'SukhumvitSet',
                                      ),
                                    ),
                                    subtitle: Text(
                                      med.genericName ?? '',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'SukhumvitSet',
                                      ),
                                    ),
                                    trailing: isSubmitting
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : TextButton(
                                            onPressed: () => submitRequest(med),
                                            child: const Text(
                                              'ระบุแท็ก',
                                              style: TextStyle(
                                                fontFamily: 'SukhumvitSet',
                                              ),
                                            ),
                                          ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Add tag dialog for selecting medications to tag in the article.
  static void showAddTagDialog(
    BuildContext context,
    Function(String) onAdd,
  ) {
    String searchQuery = '';
    List<MedicationModel> searchResults = [];
    List<String> selectedTags = [];
    bool isSearching = false;

    final popularTags = [
      'พาราเซตามอล',
      'วิตามิน ซี',
      'โอเมก้า 3',
      'แคลเซียม',
      'สังกะสี (Zinc)',
      'ไอบูโพรเฟน',
    ];

    showDialog(
      context: context,
      builder: (context) {
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              void performSearch(String query) async {
                if (query.isEmpty) {
                  setModalState(() {
                    searchResults = [];
                    isSearching = false;
                  });
                  return;
                }
                setModalState(() => isSearching = true);
                try {
                  final pharmacyRepo =
                      ServiceLocator.instance.pharmacyRepository;
                  final results = await pharmacyRepo.getMedications(
                    searchQuery: query,
                    pageSize: 10,
                  );
                  setModalState(() {
                    searchResults = results;
                    isSearching = false;
                  });
                } catch (e) {
                  setModalState(() => isSearching = false);
                }
              }

              void toggleTag(String tagName) {
                setModalState(() {
                  if (selectedTags.contains(tagName)) {
                    selectedTags.remove(tagName);
                  } else {
                    selectedTags.add(tagName);
                  }
                });
              }

              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  constraints: const BoxConstraints(
                    maxHeight: 600,
                    minHeight: 400,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'เพิ่มแท็กยา (Medications)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      if (selectedTags.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E3A8A).withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF1E3A8A).withOpacity(0.2),
                            ),
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: selectedTags
                                .map(
                                  (tag) => Chip(
                                    label: Text(
                                      tag,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    onDeleted: () => toggleTag(tag),
                                    backgroundColor: Colors.white,
                                    deleteIconColor: Colors.red,
                                    side: BorderSide(
                                      color: const Color(
                                        0xFF1E3A8A,
                                      ).withOpacity(0.3),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      TextField(
                        onChanged: (val) {
                          searchQuery = val;
                          performSearch(val);
                        },
                        decoration: InputDecoration(
                          hintText: 'ค้นหาชื่อยา หรือชื่อสามัญ',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                            horizontal: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: isSearching
                            ? const Center(child: CircularProgressIndicator())
                            : searchQuery.isEmpty
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ยายอดนิยม',
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: popularTags.map((tag) {
                                      final isSelected = selectedTags.contains(
                                        tag,
                                      );
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () => toggleTag(tag),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF1E3A8A)
                                                : Colors.grey[100],
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: isSelected
                                                  ? const Color(0xFF1E3A8A)
                                                  : Colors.grey[300]!,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isSelected)
                                                const Icon(
                                                  Icons.check,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                              if (isSelected)
                                                const SizedBox(width: 4),
                                              Text(
                                                tag,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: isSelected
                                                      ? Colors.white
                                                      : Colors.black87,
                                                  fontWeight: isSelected
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              )
                            : searchResults.isEmpty
                            ? const Center(
                                child: Text(
                                  'ไม่พบข้อมูลยา',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            : ListView.builder(
                                itemCount: searchResults.length,
                                itemBuilder: (context, index) {
                                  final med = searchResults[index];
                                  final isSelected = selectedTags.contains(
                                    med.tradeName,
                                  );
                                  return Card(
                                    elevation: 0,
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: isSelected
                                            ? const Color(0xFF1E3A8A)
                                            : Colors.grey[200]!,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 4,
                                          ),
                                      leading: CircleAvatar(
                                        backgroundColor: isSelected
                                            ? const Color(
                                                0xFF1E3A8A,
                                              ).withOpacity(0.1)
                                            : Colors.grey[100],
                                        child: Icon(
                                          Icons.medication,
                                          color: isSelected
                                              ? const Color(0xFF1E3A8A)
                                              : Colors.grey[600],
                                        ),
                                      ),
                                      title: Text(
                                        med.tradeName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(
                                        med.genericName ?? 'ไม่ระบุชื่อสามัญ',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      trailing: isSelected
                                          ? const Icon(
                                              Icons.check_circle,
                                              color: const Color(0xFF1E3A8A),
                                            )
                                          : const Icon(
                                              Icons.add_circle_outline,
                                              color: Colors.grey,
                                            ),
                                      onTap: () => toggleTag(med.tradeName),
                                    ),
                                  );
                                },
                              ),
                      ),
                      if (selectedTags.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 16),
                          child: ElevatedButton(
                            onPressed: () {
                              for (final tag in selectedTags) {
                                onAdd(tag);
                              }
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(
                                0xFF1E3A8A,
                              ),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'เพิ่ม ${selectedTags.length} แท็ก',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
