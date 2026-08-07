import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../data/models/health_article_models.dart';
import '../../data/repositories/health_article_repository.dart';
import '../widgets/health_article_skeleton.dart';
import '../widgets/health_article_top_bar.dart';
import '../widgets/health_article_head.dart';
import '../widgets/health_article_comment_item.dart';
import '../widgets/health_article_dialogs.dart';
import '../widgets/health_article_pagination.dart';
import '../widgets/health_article_misc.dart';
import 'article_tag_requests_page.dart';

/// Health Article Page
/// Feature-rich forum and article viewer with stacked sticky headers and nested comments.
class HealthArticlePage extends StatefulWidget {
  final HealthArticle? article;
  final int? targetPage;
  final String? targetCommentId;
  final String? pendingAction; // 'like' or 'bookmark'
  final String? pendingCommentId;
  final bool openBookmarks;

  const HealthArticlePage({
    super.key,
    this.article,
    this.targetPage,
    this.targetCommentId,
    this.pendingAction,
    this.pendingCommentId,
    this.openBookmarks = false,
  });

  @override
  State<HealthArticlePage> createState() => _HealthArticlePageState();
}

class _HealthArticlePageState extends State<HealthArticlePage>
    with TickerProviderStateMixin {
  late ScrollController _scrollController;
  bool _showStickyTitle = false;
  bool _isNavBarVisible = true;
  String _activeSection = 'article';
  int _currentPage = 1;
  bool _isContentExpanded = false;
  bool _isTitleExpanded = false;
  String _currentSort = 'oldest';

  late HealthArticleRepository _repository;

  // Data State
  HealthArticle? _article;
  List<HealthArticleProduct> _products = [];
  List<HealthArticleComment> _comments = [];
  int _totalComments = 0;
  int _totalRootComments = 0;
  List<ArticleEditHistory> _articleEditHistory = [];
  bool _isLoading = true;
  bool _isCommentsLoading = false;
  final Set<String> _expandedCommentIds = {};
  final Set<String> _visibilityLoadingIds = {};

  // Animation state for visual feedback
  final Map<String, AnimationController> _likeAnimControllers = {};
  final Map<String, GlobalKey> _iconKeys = {}; // Keys for icon positions
  OverlayEntry? _floatingOverlay;

  // Keys for Section Navigation
  final GlobalKey _articleHeadKey = GlobalKey();
  final GlobalKey _productsKey = GlobalKey();
  final GlobalKey _commentsKey = GlobalKey();
  final GlobalKey _paginationKey = GlobalKey();
  final Map<String, GlobalKey> _commentKeys =
      {}; // Keys for individual comments
  bool _hasInitialScrolled = false;

  void _scrollToSection(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _repository = ServiceLocator.instance.healthArticleRepository;

    // Listen for auth state changes to refresh article data
    AuthService.instance.addListener(_loadData);

    _loadData();
  }

  Future<void> _loadData() async {
    // Show loading state if we are doing a full reload
    if (mounted && _article == null) {
      setState(() => _isLoading = true);
    } else if (mounted) {
      // If we already have an article, we still want to show loading
      // when refreshing from login to update counts/bookmarks
      setState(() => _isLoading = true);
    }
    try {
      final repository = _repository;

      // 1. Fetch Article (either passed or latest)
      // 1. Fetch Article (either passed or latest)
      HealthArticle? article = widget.article;

      if (article != null) {
        // Use passed article initially for fast UI
        if (mounted) {
          setState(() => _article = article);
        }

        // Then re-fetch to get latest interaction status (isBookmarked, etc.)
        try {
          print(
            'HealthArticlePage: Refreshing article data for ${article.id}...',
          );
          final currentUserId = ServiceLocator.instance.currentUser?.id;
          final freshArticle = await repository.getArticleById(
            article.id,
            userId: currentUserId,
          );
          if (freshArticle != null) {
            article = freshArticle;
          }
        } catch (e) {
          print('HealthArticlePage: Error refreshing article: $e');
        }
      } else {
        print('HealthArticlePage: Fetching latest article...');
        final currentUserId = ServiceLocator.instance.currentUser?.id;
        article = await repository.getLatestArticle(userId: currentUserId);
      }

      if (article != null) {
        // 2. Fetch Products and Total Comments and Edit History
        final results = await Future.wait<dynamic>([
          repository.getArticleProducts(article.id),
          repository.getArticleCommentCount(article.id), // All
          repository.getArticleCommentCount(
            article.id,
            rootsOnly: true,
          ), // Roots for pagination
          repository.getArticleEditHistory(article.id), // Add history fetch
        ]);

        if (mounted) {
          setState(() {
            _article = article;
            _products = results[0] as List<HealthArticleProduct>;
            _totalComments = results[1] as int;
            _totalRootComments = results[2] as int;
            _articleEditHistory = results[3] as List<ArticleEditHistory>;
          });

          // 3. Fetch Initial Page of Comments (or target page)
          final initialPage = widget.targetPage ?? 1;
          await _fetchComments(initialPage);

          if (mounted) {
            setState(() => _isLoading = false);

            // If target comment is provided, scroll to it after content is built
            if (widget.targetCommentId != null && !_hasInitialScrolled) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToTargetComment();

                // If there's a pending action, execute it
                if (widget.pendingAction != null) {
                  if (widget.pendingAction == 'like') {
                    _onToggleLike(widget.pendingCommentId);
                  } else if (widget.pendingAction == 'bookmark') {
                    _onToggleBookmark(commentId: widget.pendingCommentId);
                  } else if (widget.pendingAction == 'reply') {
                    _handleReply(widget.pendingCommentId!);
                  }
                }
              });
            } else if (widget.pendingAction != null) {
              // If no scroll needed but action exists (e.g. article bookmark)
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (widget.pendingAction == 'like') {
                  _onToggleLike(widget.pendingCommentId);
                } else if (widget.pendingAction == 'bookmark') {
                  _onToggleBookmark(commentId: widget.pendingCommentId);
                }
              });
            }

            // 4. Auto-open bookmarks dialog if requested
            if (widget.openBookmarks) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showBookmarksDialog();
              });
            }
          }
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Error loading article data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchProducts() async {
    if (_article == null) return;
    try {
      final products = await _repository.getArticleProducts(_article!.id);
      if (mounted) {
        setState(() => _products = products);
      }
    } catch (e) {
      debugPrint('Error fetching products: $e');
    }
  }

  Future<void> _fetchComments(int page) async {
    if (_article == null) return;

    setState(() => _isCommentsLoading = true);

    try {
      final repository = ServiceLocator.instance.healthArticleRepository;
      final currentUser = ServiceLocator.instance.currentUser;

      // Check if current user is the article author
      final isArticleAuthor = _article!.authorId == currentUser?.id;

      final comments = await repository.getArticleComments(
        _article!.id,
        currentUserId: currentUser?.id,
        isArticleAuthor: isArticleAuthor,
        page: page,
        pageSize: 10,
        sort: _currentSort,
      );

      if (mounted) {
        setState(() {
          _comments = comments;
          _currentPage = page;
          _applyLocalThreading();
          _isCommentsLoading = false;
        });

        // If we just loaded the page containing the target comment, scroll to it
        if (widget.targetCommentId != null && !_hasInitialScrolled) {
          final containsTarget = comments.any(
            (c) => c.id == widget.targetCommentId,
          );
          if (containsTarget) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToTargetComment();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching comments: $e');
      if (mounted) {
        setState(() => _isCommentsLoading = false);
      }
    }
  }

  void _scrollToTargetComment() {
    if (widget.targetCommentId == null) return;

    // First, try to find the key in current context
    final key = _commentKeys[widget.targetCommentId];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(seconds: 1),
        curve: Curves.easeInOut,
      );
      setState(() => _hasInitialScrolled = true);
    } else {
      // If not visible yet, scroll to the comments section first to bring it into view and force building
      _scrollToSection(_commentsKey);

      // Wait for it to build then try again
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          final retryKey = _commentKeys[widget.targetCommentId];
          if (retryKey != null && retryKey.currentContext != null) {
            Scrollable.ensureVisible(
              retryKey.currentContext!,
              duration: const Duration(seconds: 1),
              curve: Curves.easeInOut,
            );
            setState(() => _hasInitialScrolled = true);
          }
        }
      });
    }
  }

  Future<void> _changePage(int page) async {
    if (page == _currentPage || page < 1) return;
    await _fetchComments(page);
    _scrollToSection(_commentsKey);
  }

  Future<void> _scrollToSpecificComment(String commentId) async {
    // Give a small delay to ensure the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _commentKeys[commentId];
      if (key != null && key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      } else {
        // Retry once after a short delay if not found
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            final retryKey = _commentKeys[commentId];
            if (retryKey != null && retryKey.currentContext != null) {
              Scrollable.ensureVisible(
                retryKey.currentContext!,
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeInOut,
              );
            }
          }
        });
      }
    });
  }

  Future<void> _onToggleLike(String? commentId) async {
    if (_article == null) return;

    final currentUser = ServiceLocator.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบเพื่อกดไลก์')),
      );

      Navigator.pushReplacementNamed(
        context,
        '/login',
        arguments: {
          'route': '/health/article',
          'arguments': {
            'article': _article,
            'targetPage': _currentPage,
            'targetCommentId': commentId,
            'pendingAction': 'like',
            'pendingCommentId': commentId,
          },
        },
      );
      return;
    }

    // Optimistic UI update
    bool previousIsLiked = false;
    int previousCount = 0;
    setState(() {
      if (commentId != null) {
        final index = _comments.indexWhere((c) => c.id == commentId);
        if (index != -1) {
          final comment = _comments[index];
          previousIsLiked = comment.isLiked;
          previousCount = comment.likeCount;
          final newIsLiked = !comment.isLiked;
          _comments[index] = comment.copyWith(
            isLiked: newIsLiked,
            likeCount: newIsLiked
                ? comment.likeCount + 1
                : (comment.likeCount - 1).clamp(0, 999999),
          );

          // Also optimistically update article's total like count
          _article = _article!.copyWith(
            likeCount: newIsLiked
                ? _article!.likeCount + 1
                : (_article!.likeCount - 1).clamp(0, 999999),
          );
        }
      } else {
        // Article like optimistic update
        previousIsLiked = _article!.isLiked;
        previousCount = _article!.likeCount;
        final newIsLiked = !_article!.isLiked;
        _article = _article!.copyWith(
          isLiked: newIsLiked,
          likeCount: newIsLiked
              ? _article!.likeCount + 1
              : (_article!.likeCount - 1).clamp(0, 999999),
        );
      }
    });

    try {
      final repository = ServiceLocator.instance.healthArticleRepository;
      final result = await repository.toggleInteraction(
        articleId: _article!.id,
        commentId: commentId,
        userId: currentUser.id,
        type: 'like',
      );

      if (mounted && result['success'] == true) {
        // Update with real count from DB
        setState(() {
          if (commentId != null) {
            final index = _comments.indexWhere((c) => c.id == commentId);
            if (index != -1) {
              _comments[index] = _comments[index].copyWith(
                isLiked: result['isActive'] as bool,
                likeCount: result['newCount'] as int,
              );

              // After a comment like update, we should also refresh the article's total likes
              // but we don't have the new total in 'result' if we liked a comment.
              // However, since we updated it optimistically, we can just leave it or
              // ideally fetch the new total. For now, let's just ensure we update the article
              // if we liked the article directly.
            }
          } else {
            // Update article with the NEW TOTAL returned by repository
            _article = _article!.copyWith(
              isLiked: result['isActive'] as bool,
              likeCount: result['newCount'] as int,
            );
          }
        });

        // Show visual effect over the icon
        final iconKey = _iconKeys['like-${commentId ?? "article"}'];
        if (result['isActive'] == true) {
          _showHeartBounceEffect(commentId);
          _showFloatingText(iconKey, '❤️', Colors.pinkAccent);
        } else {
          _showFloatingText(iconKey, '-❤️', Colors.white54);
        }
      } else if (mounted && result['success'] == false) {
        // Revert on failure
        setState(() {
          if (commentId != null) {
            final index = _comments.indexWhere((c) => c.id == commentId);
            if (index != -1) {
              _comments[index] = _comments[index].copyWith(
                isLiked: previousIsLiked,
                likeCount: previousCount,
              );
            }
          }

          // Revert article total if needed
          if (commentId != null || commentId == null) {
            _article = _article!.copyWith(
              isLiked: commentId == null ? previousIsLiked : _article!.isLiked,
              likeCount:
                  previousCount, // This might be slightly off if multiple things happen at once but is safe enough for a revert
            );
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('เกิดข้อผิดพลาด กรุณาลองใหม่'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error toggling like: $e');
    }
  }

  Future<void> _onToggleBookmark({String? commentId}) async {
    if (_article == null) return;

    final currentUser = ServiceLocator.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบเพื่อบุ๊กมาร์ก')),
      );

      Navigator.pushReplacementNamed(
        context,
        '/login',
        arguments: {
          'route': '/health/article',
          'arguments': {
            'article': _article,
            'targetPage': _currentPage,
            'targetCommentId': commentId,
            'pendingAction': 'bookmark',
            'pendingCommentId': commentId,
          },
        },
      );
      return;
    }

    // State will be updated after successful API response

    try {
      final repository = ServiceLocator.instance.healthArticleRepository;
      final result = await repository.toggleInteraction(
        articleId: _article!.id,
        commentId: commentId,
        userId: currentUser.id,
        type: 'bookmark',
      );

      if (mounted && result['success'] == true) {
        // Update with real state from DB
        setState(() {
          if (commentId != null) {
            final index = _comments.indexWhere((c) => c.id == commentId);
            if (index != -1) {
              _comments[index] = _comments[index].copyWith(
                isBookmarked: result['isActive'] as bool,
              );
            }
          } else {
            _article = _article!.copyWith(
              isBookmarked: result['isActive'] as bool,
              bookmarkCount: result['newCount'] as int,
            );
          }
        });

        // Show visual effect over the icon
        final iconKey = _iconKeys['bm-${commentId ?? "article"}'];
        if (result['isActive'] == true) {
          _showFloatingText(iconKey, '🔖', const Color(0xFFFFD700));
        } else {
          _showFloatingText(iconKey, '-1', Colors.white54);
        }
      } else if (mounted && result['success'] == false) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('เกิดข้อผิดพลาด กรุณาลองใหม่'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error toggling bookmark: $e');
    }
  }

  /// Show a bouncing heart animation on the like icon for a comment
  void _showHeartBounceEffect(String? commentId) {
    final key = commentId ?? 'article';
    // Dispose old controller if exists
    _likeAnimControllers[key]?.dispose();

    final controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _likeAnimControllers[key] = controller;

    // Trigger animation: scale up then back to normal
    controller.forward().then((_) {
      if (mounted) {
        controller.reverse();
      }
    });
  }

  /// Show a floating text effect (e.g. "+❤️" or "🔖 บันทึกแล้ว!")
  /// [iconKey] is the GlobalKey of the icon that was tapped
  void _showFloatingText(GlobalKey? iconKey, String text, Color textColor) {
    // Remove any existing overlay
    _floatingOverlay?.remove();
    _floatingOverlay = null;

    final overlay = Overlay.of(context);

    // Find position of the tapped icon, or fall back to screen center
    final screenSize = MediaQuery.of(context).size;
    Offset position;

    if (iconKey?.currentContext != null) {
      final renderBox =
          iconKey!.currentContext!.findRenderObject() as RenderBox;
      final pos = renderBox.localToGlobal(Offset.zero);
      // Center over the icon
      position = Offset(pos.dx + renderBox.size.width / 2, pos.dy);
    } else {
      position = Offset(screenSize.width / 2, screenSize.height * 0.4);
    }

    final animController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    final fadeAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: animController, curve: const Interval(0.5, 1.0)),
    );
    final slideAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -50),
    ).animate(CurvedAnimation(parent: animController, curve: Curves.easeOut));
    final scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.6), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.6, end: 1.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: animController, curve: Curves.easeOut));

    _floatingOverlay = OverlayEntry(
      builder: (context) => AnimatedBuilder(
        animation: animController,
        builder: (context, child) => Positioned(
          left: position.dx - 40,
          top: position.dy - 10 + slideAnim.value.dy,
          child: IgnorePointer(
            child: Opacity(
              opacity: fadeAnim.value,
              child: Transform.scale(
                scale: scaleAnim.value,
                child: Container(
                  width: 80,
                  alignment: Alignment.center,
                  child: Text(
                    text,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.8),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_floatingOverlay!);
    animController.forward().then((_) {
      _floatingOverlay?.remove();
      _floatingOverlay = null;
      animController.dispose();
    });
  }

  /// Helper to get or create a GlobalKey for a specific icon
  GlobalKey _getIconKey(String id) {
    return _iconKeys.putIfAbsent(id, () => GlobalKey());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    // Clean up animation controllers
    for (final controller in _likeAnimControllers.values) {
      controller.dispose();
    }
    _likeAnimControllers.clear();
    _floatingOverlay?.remove();
    _floatingOverlay = null;
    AuthService.instance.removeListener(_loadData);
    super.dispose();
  }

  Future<HealthArticleComment?> _submitComment(
    String content, {
    String? parentId,
  }) async {
    if (content.trim().isEmpty || _article == null) return null;

    final currentUser = ServiceLocator.instance.currentUser;
    if (currentUser == null) return null;

    try {
      if (_article!.id.startsWith('mock-')) {
        // Handle mock submission for development
        final mockComment = HealthArticleComment(
          id: 'mock-c-${DateTime.now().millisecondsSinceEpoch}',
          articleId: _article!.id,
          userId: currentUser.id,
          username: 'คุณ (จำลอง)',
          content: content,
          // Since we changed to Ascending (Oldest First), the new number is total + 1
          commentNumber: _totalComments + 1,
          createdAt: DateTime.now(),
        );
        setState(() {
          // If we are showing "Oldest First", the new comment should be at the END.
          // But to give immediate feedback, we might want to reload or just append.
          // Appending is safer for "Chat like" view, but if paginated, it belongs on last page.
          // For simplicity, let's append it here and increment total.
          _comments.add(mockComment);
          _totalComments++;
        });
        return mockComment;
      }

      final repository = ServiceLocator.instance.healthArticleRepository;
      final newComment = await repository.postComment(
        articleId: _article!.id,
        userId: currentUser.id,
        content: content,
        parentId: parentId,
        commentNumber: _totalComments + 1,
      );

      if (newComment != null && mounted) {
        setState(() {
          _totalComments++;
          if (parentId == null) {
            _totalRootComments++;
          }

          _comments.add(newComment);
          _applyLocalThreading();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ส่งความคิดเห็นเรียบร้อยแล้ว')),
        );
        return newComment;
      }
      return null;
    } catch (e) {
      debugPrint('Error posting comment: $e');
      return null;
    }
  }

  Future<HealthArticleComment?> _updateComment(
    String commentId,
    String content,
  ) async {
    if (content.trim().isEmpty) return null;

    try {
      if (commentId.startsWith('mock-')) {
        // Handle mock update
        final commentIndex = _comments.indexWhere((c) => c.id == commentId);
        if (commentIndex != -1) {
          final updatedComment = _comments[commentIndex].copyWith(
            content: content,
          );
          setState(() {
            _comments[commentIndex] = updatedComment;
          });
          return updatedComment;
        }
        return null;
      }

      final repository = ServiceLocator.instance.healthArticleRepository;
      final updatedComment = await repository.updateComment(
        commentId: commentId,
        content: content,
      );

      if (updatedComment != null && mounted) {
        setState(() {
          final index = _comments.indexWhere((c) => c.id == commentId);
          if (index != -1) {
            _comments[index] = updatedComment;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('แก้ไขความคิดเห็นเรียบร้อยแล้ว')),
        );
        return updatedComment;
      }
      return null;
    } catch (e) {
      debugPrint('Error updating comment: $e');
      return null;
    }
  }

  void _applyLocalThreading() {
    if (_comments.isEmpty) return;

    // Get all root comments
    final roots = _comments.where((c) => c.parentId == null).toList();

    // Sort roots based on current sort criteria
    if (_currentSort == 'newest') {
      roots.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } else if (_currentSort == 'likes') {
      roots.sort((a, b) => b.likeCount.compareTo(a.likeCount));
    } else if (_currentSort == 'bookmarks') {
      // Assuming we have a bookmarkCount or similar if needed, else fallback
      roots.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } else {
      // Default: oldest
      roots.sort((a, b) => a.commentNumber.compareTo(b.commentNumber));
    }

    final threaded = <HealthArticleComment>[];
    for (var root in roots) {
      threaded.add(root);
      // Recursively add all descendants in cronological order
      _addDescendants(root.id, threaded);
    }

    // Include any remaining comments (orphans)
    final threadedIds = threaded.map((e) => e.id).toSet();
    final orphans = _comments
        .where((c) => !threadedIds.contains(c.id))
        .toList();
    orphans.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    threaded.addAll(orphans);

    setState(() {
      _comments = threaded;
    });
  }

  void _addDescendants(String parentId, List<HealthArticleComment> targetList) {
    final directReplies = _comments
        .where((c) => c.parentId == parentId)
        .toList();
    directReplies.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (var reply in directReplies) {
      targetList.add(reply);
      _addDescendants(reply.id, targetList);
    }
  }

  String _getCommentDisplayNumber(HealthArticleComment comment) {
    if (comment.parentId == null) {
      return '${comment.commentNumber}';
    }

    try {
      // Find the ultimate root parent
      HealthArticleComment? root;
      String? currentParentId = comment.parentId;

      while (currentParentId != null) {
        final parent = _comments.firstWhere((c) => c.id == currentParentId);
        if (parent.parentId == null) {
          root = parent;
          break;
        }
        currentParentId = parent.parentId;
      }

      if (root == null) return '0-0';

      // Find all descendants of this root to calculate sequence number
      final descendants = <HealthArticleComment>[];
      _addDescendants(root.id, descendants);

      final sequenceIndex = descendants.indexWhere((c) => c.id == comment.id);
      return '${root.commentNumber}-${sequenceIndex + 1}';
    } catch (e) {
      return '0-0';
    }
  }

  void _onScroll() {
    if (!mounted) return;

    final offset = _scrollController.offset;

    // 1. Sticky Title Logic
    final showTitle = offset > 150; // threshold for showing sticky title
    if (showTitle != _showStickyTitle) {
      setState(() {
        _showStickyTitle = showTitle;
      });
    }

    // 2. Active Section Identification
    String newSection = 'article';

    // Determine current section based on scroll offset or context positions
    if (_commentsKey.currentContext != null) {
      final renderObject = _commentsKey.currentContext!.findRenderObject();
      if (renderObject is RenderBox) {
        final position = renderObject.localToGlobal(Offset.zero).dy;
        // If comments section top is near the control bar
        if (position < 150) {
          newSection = 'comments';
        } else if (_productsKey.currentContext != null) {
          final prodRenderObject = _productsKey.currentContext!
              .findRenderObject();
          if (prodRenderObject is RenderBox) {
            final prodPosition = prodRenderObject.localToGlobal(Offset.zero).dy;
            if (prodPosition < 150) {
              newSection = 'products';
            }
          }
        }
      }
    }

    if (newSection != _activeSection) {
      setState(() {
        _activeSection = newSection;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      drawer: const TlzDrawer(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE6B980),
              Color(0xFF8EBAE3),
              Color(0xFF5D9CDB),
            ],
            stops: [0.0, 0.2, 0.5],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              HealthArticleTopBar(
                showStickyTitle: _showStickyTitle,
                articleTitle: _article?.title,
              ),
              HealthArticleControlBar(
                activeSection: _activeSection,
                onArticleTap: () => _scrollToSection(_articleHeadKey),
                onProductsTap: () => _scrollToSection(_productsKey),
                onCommentsTap: () => _scrollToSection(_commentsKey),
                onBookmarksTap: _showBookmarksDialog,
              ),
              Expanded(
                child: _isLoading
                    ? const HealthArticleSkeleton()
                    : _article == null
                    ? const Center(
                        child: Text(
                          'ไม่พบบทความ',
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                      )
                    : NotificationListener<UserScrollNotification>(
                      onNotification: (notification) {
                        if (notification.direction == ScrollDirection.reverse) {
                          if (_isNavBarVisible) {
                            setState(() => _isNavBarVisible = false);
                          }
                        } else if (notification.direction == ScrollDirection.forward) {
                          if (!_isNavBarVisible) {
                            setState(() => _isNavBarVisible = true);
                          }
                        }
                        return false;
                      },
                      child: CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          SliverToBoxAdapter(
                            key: _articleHeadKey,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: HealthArticleHead(
                                article: _article,
                                totalComments: _totalComments,
                                isTitleExpanded: _isTitleExpanded,
                                isContentExpanded: _isContentExpanded,
                                editHistory: _articleEditHistory,
                                onToggleTitleExpand: () => setState(
                                  () => _isTitleExpanded = !_isTitleExpanded,
                                ),
                                onToggleContentExpand: () => setState(
                                  () => _isContentExpanded = !_isContentExpanded,
                                ),
                                onReply: () => _handleReply(null),
                                onEditArticle: () => HealthArticleDialogs
                                    .showEditArticleDialog(
                                  context,
                                  article: _article!,
                                  onProceed: () => HealthArticleDialogs
                                      .showEditArticleScreen(
                                    context,
                                    article: _article!,
                                    products: _products,
                                    repository: _repository,
                                    onDataChanged: _loadData,
                                  ),
                                ),
                                onToggleBookmark: () =>
                                    _onToggleBookmark(),
                                onManageTagRequests: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const ArticleTagRequestsPage(),
                                  ),
                                ),
                                bookmarkKey: _getIconKey('bm-article'),
                                formatThaiDate: _formatThaiDate,
                              ),
                            ),
                          ),
                          Builder(
                            builder: (context) {
                              final isAuthor =
                                  AuthService.instance.userId ==
                                  _article?.authorId;
                              final visibleProducts = _products
                                  .where((p) => p.isApproved || isAuthor)
                                  .toList();

                              if (visibleProducts.isEmpty)
                                return const SliverToBoxAdapter(
                                  child: SizedBox.shrink(),
                                );

                              return SliverPersistentHeader(
                                pinned: true,
                                delegate: ProductSectionDelegate(
                                  products: visibleProducts,
                                  authorId: _article!.authorId,
                                  onRequestTag: () => HealthArticleDialogs
                                      .showRequestTagDialog(
                                    context,
                                    articleId: _article!.id,
                                    onRefreshProducts: _fetchProducts,
                                  ),
                                ),
                                key: _productsKey,
                              );
                            },
                          ),
                          SliverToBoxAdapter(
                            key: _commentsKey,
                            child: HealthArticleCommentHeader(
                              currentSort: _currentSort,
                              onSortChanged: (value) {
                                setState(() => _currentSort = value);
                                _fetchComments(1);
                              },
                            ),
                          ),
                          if (_isCommentsLoading)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(40.0),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            )
                          else if (_comments.isEmpty)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(32.0),
                                child: Center(
                                  child: Text(
                                    'ยังไม่มีความคิดเห็น',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                              ),
                            )
                          else
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final comment = _comments[index];
                                  final isOwnComment = comment.userId ==
                                      AuthService.instance.currentUser?.id;
                                  final isArticleAuthor =
                                      _article?.authorId ==
                                      AuthService.instance.currentUser?.id;
                                  return HealthArticleCommentItem(
                                    comment: comment,
                                    displayNumber: _getCommentDisplayNumber(
                                      comment,
                                    ),
                                    parentDisplayNumber: comment.parentId !=
                                            null
                                        ? _getParentDisplayNumber(comment)
                                        : null,
                                    isOwnComment: isOwnComment,
                                    isArticleAuthor: isArticleAuthor,
                                    isExpanded: _expandedCommentIds.contains(
                                      comment.id,
                                    ),
                                    isVisibilityLoading:
                                        _visibilityLoadingIds.contains(
                                      comment.id,
                                    ),
                                    commentKey: _commentKeys.putIfAbsent(
                                      comment.id,
                                      () => GlobalKey(),
                                    ),
                                    likeIconKey: _getIconKey(
                                      'like-${comment.id}',
                                    ),
                                    bookmarkIconKey: _getIconKey(
                                      'bm-${comment.id}',
                                    ),
                                    formatThaiDate: _formatThaiDate,
                                    onToggleExpand: () => setState(() {
                                      if (_expandedCommentIds.contains(
                                        comment.id,
                                      )) {
                                        _expandedCommentIds.remove(comment.id);
                                      } else {
                                        _expandedCommentIds.add(comment.id);
                                      }
                                    }),
                                    onToggleLike: () =>
                                        _onToggleLike(comment.id),
                                    onToggleBookmark: () =>
                                        _onToggleBookmark(commentId: comment.id),
                                    onReply: () => _handleReply(comment.id),
                                    onEdit: () => HealthArticleDialogs
                                        .showEditDialog(
                                      context,
                                      comment: comment,
                                      onUpdate: _updateComment,
                                      onScrollToComment:
                                          _scrollToSpecificComment,
                                    ),
                                    onToggleVisibility: () =>
                                        _toggleCommentVisibility(comment),
                                    onShowEditHistory: () =>
                                        HealthArticleDialogs
                                            .showEditHistoryDialog(
                                      context,
                                      comment: comment,
                                      formatThaiDate: _formatThaiDate,
                                    ),
                                  );
                                },
                                childCount: _comments.length,
                              ),
                            ),
                          if (_totalComments > 10)
                            SliverToBoxAdapter(
                              key: _paginationKey,
                              child: HealthArticlePagination(
                                currentPage: _currentPage,
                                totalRootComments: _totalRootComments,
                                totalComments: _totalComments,
                                onPageChanged: _changePage,
                              ),
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 120)),
                        ],
                      ),
                    ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: TlzBottomNavigationBar(
        isVisible: _isNavBarVisible,
        currentIndex: -1,
        onIndexChanged: (index) {
          if (index == 2) return;
          Navigator.pushReplacementNamed(
            context,
            '/main-app',
            arguments: {'index': index},
          );
        },
        onAddPressed: () async {
          if (AuthService.instance.currentUser == null) {
            Navigator.pushNamed(context, '/login', arguments: '/emergency-live');
            return;
          }
          Navigator.pushNamed(context, '/emergency-live');
        },
      ),
      floatingActionButton: _showStickyTitle
          ? FloatingActionButton(
              onPressed: () => _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
              ),
              backgroundColor: const Color(0xFF6CB0C5).withOpacity(0.9),
              elevation: 4,
              child: const Icon(Icons.arrow_upward, color: Colors.white),
            )
          : null,
    );
  }

  String? _getParentDisplayNumber(HealthArticleComment comment) {
    try {
      final parent = _comments.firstWhere((c) => c.id == comment.parentId);
      return _getCommentDisplayNumber(parent);
    } catch (e) {
      return null;
    }
  }

  void _showBookmarksDialog() {
    if (!AuthService.instance.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาเข้าสู่ระบบเพื่อดูรายการที่บันทึกไว้'),
        ),
      );
      Navigator.pushNamed(
        context,
        '/login',
        arguments: {
          'route': '/health/article',
          'arguments': {'article': _article, 'openBookmarks': true},
        },
      );
      return;
    }

    setState(() {
      _activeSection = 'bookmarks';
    });
    showDialog(
      context: context,
      builder: (context) => const BookmarkedArticlesDialog(),
    );
  }

  void _handleReply(String? commentId) {
    final currentUser = ServiceLocator.instance.currentUser;

    if (currentUser == null) {
      Navigator.pushReplacementNamed(
        context,
        '/login',
        arguments: {
          'route': '/health/article',
          'arguments': {
            'article': _article,
            'targetPage': _currentPage,
            'targetCommentId': commentId,
            'pendingAction': 'reply',
            'pendingCommentId': commentId,
          },
        },
      );
    } else {
      HealthArticleDialogs.showReplyDialog(
        context,
        commentId: commentId,
        comments: _comments,
        onSubmit: _submitComment,
        onScrollToComment: _scrollToSpecificComment,
        totalRootComments: _totalRootComments,
        currentSort: _currentSort,
        currentPage: _currentPage,
        changePage: _changePage,
      );
    }
  }

  String _formatThaiDate(DateTime date) {
    const months = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    const days = [
      'อาทิตย์',
      'จันทร์',
      'อังคาร',
      'พุธ',
      'พฤหัสบดี',
      'ศุกร์',
      'เสาร์',
    ];

    final thaiYearBE = date.year + 543;
    final yearString = thaiYearBE.toString().substring(2);
    final dayName = days[date.weekday % 7];

    return '$dayName ${date.day} ${months[date.month - 1]} $yearString';
  }


  Future<void> _toggleCommentVisibility(HealthArticleComment comment) async {
    if (_visibilityLoadingIds.contains(comment.id)) return;

    setState(() {
      _visibilityLoadingIds.add(comment.id);
    });

    try {
      final repository = ServiceLocator.instance.healthArticleRepository;
      final success = await repository.toggleCommentVisibility(
        commentId: comment.id,
        isHidden: !comment.isHidden,
      );

      if (success && mounted) {
        setState(() {
          final index = _comments.indexWhere((c) => c.id == comment.id);
          if (index != -1) {
            _comments[index] = comment.copyWith(isHidden: !comment.isHidden);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              comment.isHidden
                  ? 'เปิดเผยความคิดเห็นแล้ว'
                  : 'ปิดกั้นความคิดเห็นแล้ว',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error toggling visibility: $e');
    } finally {
      if (mounted) {
        setState(() {
          _visibilityLoadingIds.remove(comment.id);
        });
      }
    }
  }
}
