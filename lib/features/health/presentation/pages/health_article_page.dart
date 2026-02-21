import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:convert';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../auth/data/models/user_model.dart';
import '../../data/models/health_article_models.dart';
import '../../data/repositories/health_article_repository.dart';
import '../widgets/health_article_skeleton.dart';

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
  final Map<String, GlobalKey> _commentKeys = {}; // Keys for individual comments
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
          print('HealthArticlePage: Refreshing article data for ${article.id}...');
          final currentUserId = ServiceLocator.instance.currentUser?.id;
          final freshArticle = await repository.getArticleById(article.id, userId: currentUserId);
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
          repository.getArticleCommentCount(article.id, rootsOnly: true), // Roots for pagination
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
          final containsTarget = comments.any((c) => c.id == widget.targetCommentId);
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

  void _scrollToSpecificComment(String commentId) {
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
          }
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
            likeCount: newIsLiked ? comment.likeCount + 1 : (comment.likeCount - 1).clamp(0, 999999),
          );
          
          // Also optimistically update article's total like count
          _article = _article!.copyWith(
            likeCount: newIsLiked ? _article!.likeCount + 1 : (_article!.likeCount - 1).clamp(0, 999999),
          );
        }
      } else {
        // Article like optimistic update
        previousIsLiked = _article!.isLiked;
        previousCount = _article!.likeCount;
        final newIsLiked = !_article!.isLiked;
        _article = _article!.copyWith(
          isLiked: newIsLiked,
          likeCount: newIsLiked ? _article!.likeCount + 1 : (_article!.likeCount - 1).clamp(0, 999999),
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
               likeCount: previousCount, // This might be slightly off if multiple things happen at once but is safe enough for a revert
             );
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('เกิดข้อผิดพลาด กรุณาลองใหม่'), backgroundColor: Colors.redAccent),
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
          }
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
            const SnackBar(content: Text('เกิดข้อผิดพลาด กรุณาลองใหม่'), backgroundColor: Colors.redAccent),
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
      final renderBox = iconKey!.currentContext!.findRenderObject() as RenderBox;
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
    final slideAnim = Tween<Offset>(begin: Offset.zero, end: const Offset(0, -50)).animate(
      CurvedAnimation(parent: animController, curve: Curves.easeOut),
    );
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

  Future<HealthArticleComment?> _submitComment(String content, {String? parentId}) async {
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

  Future<HealthArticleComment?> _updateComment(String commentId, String content) async {
    if (content.trim().isEmpty) return null;

    try {
      if (commentId.startsWith('mock-')) {
        // Handle mock update
        final commentIndex = _comments.indexWhere((c) => c.id == commentId);
        if (commentIndex != -1) {
          final updatedComment = _comments[commentIndex].copyWith(content: content);
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
    final orphans = _comments.where((c) => !threadedIds.contains(c.id)).toList();
    orphans.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    threaded.addAll(orphans);

    setState(() {
      _comments = threaded;
    });
  }

  void _addDescendants(String parentId, List<HealthArticleComment> targetList) {
    final directReplies = _comments.where((c) => c.parentId == parentId).toList();
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
          final prodRenderObject = _productsKey.currentContext!.findRenderObject();
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
      drawer: const TlzDrawer(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE6B980), // Warm beige/gold top
              Color(0xFF8EBAE3), // Light blue middle
              Color(0xFF5D9CDB), // Main blue bottom
            ],
            stops: [0.0, 0.2, 0.5],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // AREA 1: Top Navigation Bar
              _buildArea1TopBar(),
              
              // AREA 2: Fixed Control Bar
              _buildArea2ControlBar(),

              // SCROLLABLE AREA
              Expanded(
                child: _isLoading 
                  ? const HealthArticleSkeleton()
                  : _article == null
                    ? const Center(child: Text('ไม่พบบทความ', style: TextStyle(fontSize: 18, color: Colors.white)))
                    : CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          // AREA 3: Article Card
                          SliverToBoxAdapter(
                            key: _articleHeadKey,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: _buildArea3ArticleHead(),
                            ),
                          ),
        
                          // AREA 4: Horizontal Product Pills
                          if (_products.isNotEmpty)
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _ProductSectionDelegate(
                                products: _products,
                                key: _productsKey,
                              ),
                            ),
        
                          // AREA 5: Comment Section Header
                          SliverToBoxAdapter(
                            key: _commentsKey,
                            child: _buildCommentSystemHeader(),
                          ),
                          
                          if (_isCommentsLoading)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(40.0),
                              child: Center(child: CircularProgressIndicator(color: Colors.white)),
                            ),
                          )
                        else if (_comments.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Center(child: Text('ยังไม่มีความคิดเห็น', style: TextStyle(color: Colors.white70))),
                            ),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildCommentItem(index),
                              childCount: _comments.length,
                            ),
                          ),
                        
                        // Pagination Section (Only show if total comments > pageSize)
                        if (_totalComments > 10)
                          SliverToBoxAdapter(
                            key: _paginationKey,
                            child: _buildPaginationSection(),
                          ),
                          
                          const SliverToBoxAdapter(
                            child: SizedBox(height: 80),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _showStickyTitle 
        ? FloatingActionButton(
            onPressed: () => _scrollController.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut),
            backgroundColor: const Color(0xFF6CB0C5).withOpacity(0.9),
            elevation: 4,
            child: const Icon(Icons.arrow_upward, color: Colors.white),
          )
        : null,
    );
  }

  Widget _buildArea1TopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TlzAppTopBar.onPrimary(
        onMenuPressed: () => Scaffold.of(context).openDrawer(),
        notificationCount: 1,

        onNotificationTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('การแจ้งเตือนจะเปิดใช้งานเร็วๆ นี้')),
        ),
        onCartTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ตะกร้าสินค้าจะเปิดใช้งานเร็วๆ นี้')),
        ),
        middle: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _showStickyTitle && _article != null
            ? Container(
                key: const ValueKey('sticky_title'),
                padding: const EdgeInsets.only(left: 8),
                alignment: Alignment.centerLeft,
                child: Text(
                  _article!.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white, 
                    fontWeight: FontWeight.bold, 
                    fontSize: 15,
                  ),
                ),
              )
            : TlzAnimatedSearchBar.onPrimary(
                key: const ValueKey('search_bar'),
                hintText: 'ค้นหายา ร้านยา หมอ...',
                onQRTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('QR Scanner จะเปิดใช้งานเร็วๆ นี้')),
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildArea2ControlBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 44, // Increased slightly for better tap target
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFFC4E0A5), size: 24),
            onPressed: () => Navigator.pop(context),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            constraints: const BoxConstraints(),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true, // Scroll from right to left or keep right-aligned
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildNavButton('หัวข้อ', _activeSection == 'article', onTap: () => _scrollToSection(_articleHeadKey)),
                  _buildNavButton('สินค้า', _activeSection == 'products', onTap: () => _scrollToSection(_productsKey)),
                  _buildNavButton('ความคิดเห็น', _activeSection == 'comments', onTap: () => _scrollToSection(_commentsKey)),
                  _buildNavButton('ที่บันทึกไว้', _activeSection == 'bookmarks', onTap: _showBookmarksDialog),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton(String label, bool isActive, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withOpacity(0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.black87.withOpacity(0.7),
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  void _showBookmarksDialog() {
    if (!AuthService.instance.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบเพื่อดูรายการที่บันทึกไว้')),
      );
      Navigator.pushNamed(
        context, 
        '/login',
        arguments: {
          'route': '/health/article',
          'arguments': {
            'article': _article,
            'openBookmarks': true,
          },
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
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w500),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Widget _buildArea3ArticleHead() {
    if (_article == null) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF6CB0C5).withOpacity(0.8),
        borderRadius: BorderRadius.circular(32),
      ),
      clipBehavior: Clip.antiAlias,
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
                            onTap: () => setState(() => _isTitleExpanded = !_isTitleExpanded),
                            child: Text(
                              _article!.title,
                              maxLines: _isTitleExpanded ? null : 2,
                              overflow: _isTitleExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'เปิดดู ${_article!.viewCount} • ${_totalComments} ความคิดเห็น • ${_article!.bookmarkCount} ท่านสนใจบทความนี้',
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                          if (AuthService.instance.currentUser?.id == _article!.authorId)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: TextButton.icon(
                                onPressed: _showEditArticleDialog,
                                icon: const Icon(Icons.edit, size: 16, color: Color(0xFFF1AE27)),
                                label: const Text('แก้ไขบทความ', style: TextStyle(fontSize: 12, color: Color(0xFFF1AE27))),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  alignment: Alignment.centerLeft,
                                ),
                              ),
                            ),
                          if (_article!.editCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'แก้ไขแล้ว',
                                  style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SizedBox(width: 12),
                    Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.access_time, size: 14, color: Colors.white70),
                            const SizedBox(width: 4),
                            Text(
                              _formatThaiDate(_article!.createdAt),
                              style: const TextStyle(fontSize: 12, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _showAuthorProfile,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white70,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: _article!.authorImage != null 
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(24), 
                                  child: Image.network(_article!.authorImage!, fit: BoxFit.cover)
                                )
                              : const Icon(Icons.person, color: Colors.grey),
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
                    );
                    
                    // Simple check if it's block-based (JSON)
                    bool isBlockBased = _article!.content.trim().startsWith('[') && _article!.content.trim().endsWith(']');
                    
                    if (_isContentExpanded) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _renderArticleContent(_article!.content, contentStyle),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => setState(() => _isContentExpanded = false),
                            child: const Text(
                              'ย่อเนื้อหา',
                              style: TextStyle(
                                color: Color(0xFFF1AE27),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // When collapsed, we show first few lines of the first text block or content
                        _renderArticleContent(_article!.content, contentStyle, maxLines: 3),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => setState(() => _isContentExpanded = true),
                          child: const Text(
                            'แสดงเนื้อหาทั้งหมด...',
                            style: TextStyle(
                              color: Color(0xFFF1AE27),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
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
                    onTap: () => _handleReply(null),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.reply, size: 16, color: Color(0xFFF1AE27)),
                          SizedBox(width: 4),
                          Text(
                            'ตอบกลับ', 
                            style: TextStyle(color: Color(0xFFF1AE27), fontSize: 13, fontWeight: FontWeight.bold)
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 24,
            child: Container(
              key: _getIconKey('bm-article'),
              child: RibbonBookmark(
                isBookmarked: _article?.isBookmarked ?? false,
                onTap: () => _onToggleBookmark(),
                height: 30,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _renderArticleContent(String content, TextStyle style, {int? maxLines}) {
    try {
      final List<dynamic> blocks = jsonDecode(content);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks.take(maxLines != null ? 1 : blocks.length).map((block) {
          final type = block['type'];
          final val = block['content'] as String;

          if (type == 'text') {
            final history = _articleEditHistory.isNotEmpty ? _articleEditHistory.first : null;
            String? oldText;
            if (history != null) {
              try {
                final oldBlocks = jsonDecode(history.oldContent) as List;
                // Find corresponding text block index
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
              child: _RichTextRenderer(
                text: val, 
                style: style, 
                maxLines: maxLines,
                oldText: oldText,
              ),
            );
          } else if (type == 'image') {
            final alignment = block['alignment'] ?? 'full';
            final height = (block['height'] ?? 200).toDouble();
            
            Alignment widgetAlignment;
            double widgetWidthFactor;
            switch (alignment) {
              case 'left': widgetAlignment = Alignment.centerLeft; widgetWidthFactor = 0.6; break;
              case 'right': widgetAlignment = Alignment.centerRight; widgetWidthFactor = 0.6; break;
              case 'center': widgetAlignment = Alignment.center; widgetWidthFactor = 0.8; break;
              default: widgetAlignment = Alignment.center; widgetWidthFactor = 1.0;
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
                    image: DecorationImage(image: NetworkImage(val), fit: BoxFit.cover),
                  ),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }).toList(),
      );
    } catch (e) {
      // Legacy or plain text
      return Text(
        content,
        style: style,
        maxLines: maxLines,
        overflow: maxLines != null ? TextOverflow.ellipsis : null,
      );
    }
  }

  String _formatThaiDate(DateTime date) {
    const months = [
      'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'
    ];
    const days = [
      'อาทิตย์', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์'
    ];
    
    // Thai year is Buddhist Era (BE) which is AD + 543
    final thaiYearBE = date.year + 543;
    final yearString = thaiYearBE.toString().substring(2);
    final dayName = days[date.weekday % 7];
    
    return '$dayName ${date.day} ${months[date.month - 1]} $yearString';
  }

  Widget _buildCommentSystemHeader() {
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
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF4A89C8)),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _currentSort,
                  items: const [
                    DropdownMenuItem(value: 'oldest', child: Text('เก่าที่สุด', style: TextStyle(fontSize: 13, color: Colors.white))),
                    DropdownMenuItem(value: 'newest', child: Text('ใหม่ที่สุด', style: TextStyle(fontSize: 13, color: Colors.white))),
                    DropdownMenuItem(value: 'likes', child: Text('สนใจมากที่สุด', style: TextStyle(fontSize: 13, color: Colors.white))),
                    DropdownMenuItem(value: 'bookmarks', child: Text('แนะนำมากที่สุด', style: TextStyle(fontSize: 13, color: Colors.white))),
                  ],
                  onChanged: (value) {
                    if (value != null && value != _currentSort) {
                      setState(() => _currentSort = value);
                      _fetchComments(1); // Reset to page 1 on sort change
                    }
                  },
                  dropdownColor: const Color(0xFF5D9CDB),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20, color: Color(0xFFF1AE27)),
                  style: const TextStyle(color: Colors.white), // Ensure text is visible in dropdown button
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(int index) {
    if (index >= _comments.length) return const SizedBox.shrink();
    
    final comment = _comments[index];
    final commentKey = _commentKeys.putIfAbsent(comment.id, () => GlobalKey());
    
    final isOwnComment = AuthService.instance.currentUser?.id == comment.userId;
    final isReply = comment.parentId != null;
    final displayNumber = _getCommentDisplayNumber(comment);
    
    // Get parent display number for "Reply to X" text
    String? parentDisplayNumber;
    if (isReply) {
      try {
        final parent = _comments.firstWhere((c) => c.id == comment.parentId);
        parentDisplayNumber = _getCommentDisplayNumber(parent);
      } catch (e) {
        parentDisplayNumber = null;
      }
    }
    
    final bool canEdit = isOwnComment;
    final bool canHideShow = _article?.authorId == AuthService.instance.currentUser?.id;

    return Container(
      key: commentKey,
      margin: EdgeInsets.fromLTRB(isReply ? 60 : 20, 8, 20, 8),
      child: Slidable(
        key: ValueKey(comment.id),
        endActionPane: (canEdit || canHideShow) ? ActionPane(
          motion: const ScrollMotion(),
          extentRatio: (canEdit && canHideShow) ? 0.45 : 0.25,
          children: [
            if (canHideShow)
              SlidableAction(
                onPressed: (context) {
                  if (!_visibilityLoadingIds.contains(comment.id)) {
                    _toggleCommentVisibility(comment);
                  }
                },
                backgroundColor: comment.isHidden ? const Color(0xFF4CAF50) : Colors.red.shade400,
                foregroundColor: Colors.white,
                icon: comment.isHidden ? Icons.visibility : Icons.visibility_off,
                label: comment.isHidden ? 'เปิดเผย' : 'ปิดกั้น',
                autoClose: true,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            if (canEdit)
              SlidableAction(
                onPressed: (context) => _showEditDialog(comment),
                backgroundColor: const Color(0xFFF1AE27),
                foregroundColor: Colors.white,
                icon: Icons.edit,
                label: 'แก้ไข',
                autoClose: true,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
          ],
        ) : null,
        child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            decoration: BoxDecoration(
              color: isOwnComment 
                  ? Colors.white.withOpacity(0.15) // Slightly brighter for own comment
                  : Colors.white.withOpacity(0.05),
              border: Border.all(
                color: isOwnComment 
                    ? const Color(0xFF5D9CDB).withOpacity(0.5) // Blue border for own comment
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
                    // Show edit history if user is article author and comment has been edited
                    final isArticleAuthor = _article?.authorId == AuthService.instance.currentUser?.id;
                    if (isArticleAuthor && comment.editCount > 0) {
                      _showEditHistoryDialog(comment);
                    }
                  },
                  child: Text(
                    comment.content,
                    maxLines: _expandedCommentIds.contains(comment.id) ? null : 3,
                    overflow: _expandedCommentIds.contains(comment.id) ? TextOverflow.visible : TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: () {
                        // Red if article author and comment has been edited
                        final isArticleAuthor = _article?.authorId == AuthService.instance.currentUser?.id;
                        if (isArticleAuthor && comment.editCount > 0) {
                          return Colors.red;
                        }
                        // Blue if own comment
                        if (isOwnComment) {
                          return const Color(0xFF1A3B5D);
                        }
                        // White otherwise
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
                        onPressed: () {
                          setState(() {
                            if (_expandedCommentIds.contains(comment.id)) {
                              _expandedCommentIds.remove(comment.id);
                            } else {
                              _expandedCommentIds.add(comment.id);
                            }
                          });
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _expandedCommentIds.contains(comment.id) ? 'ย่อกลับ' : 'อ่านเพิ่ม', 
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)
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
                            child: Image.network(comment.userImage!, fit: BoxFit.cover),
                          )
                        : const Icon(Icons.person, size: 20, color: Colors.white70),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comment.username ?? 'สมาชิกหมายเลข ${comment.userId.substring(0, 4)}',
                            style: const TextStyle(color: Color(0xFFF1AE27), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.access_time, size: 10, color: Color(0xFFF1AE27)),
                              const SizedBox(width: 4),
                              Text(
                                _formatThaiDate(comment.createdAt),
                                style: const TextStyle(color: Color(0xFFF1AE27), fontSize: 10),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _buildStatIcon(
                      comment.isLiked ? Icons.favorite : Icons.favorite_border, 
                      '${comment.likeCount}',
                      color: comment.isLiked ? Colors.pinkAccent : Colors.white,
                      onTap: () => _onToggleLike(comment.id),
                      iconKey: _getIconKey('like-${comment.id}'),
                    ),
                    _buildStatIcon(Icons.chat_bubble_outline, '0'),
                    _buildStatIcon(
                      comment.isBookmarked ? Icons.bookmark : Icons.bookmark_border, 
                      '',
                      color: comment.isBookmarked ? const Color(0xFFFFD700) : Colors.white,
                      onTap: () => _onToggleBookmark(commentId: comment.id),
                      iconKey: _getIconKey('bm-${comment.id}'),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1C40F).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'ความคิดเห็นที่ $displayNumber',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ),
                if (parentDisplayNumber != null) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.reply, size: 12, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(
                    parentDisplayNumber,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _handleReply(comment.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                          style: TextStyle(color: Color(0xFFF1AE27), fontSize: 11, fontWeight: FontWeight.bold)
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

  Widget _buildStatIcon(IconData icon, String value, {Color color = Colors.white, VoidCallback? onTap, GlobalKey? iconKey}) {
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

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays} วันที่แล้ว';
    if (diff.inHours > 0) return '${diff.inHours} ชม. ที่แล้ว';
    if (diff.inMinutes > 0) return '${diff.inMinutes} นาทีที่แล้ว';
    return 'เมื่อสักครู่';
  }

  Widget _buildInteractionButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ],
        ],
      ),
    );
  }

  void _handleReply(String? commentId) {
    // Check if user is logged in
    final currentUser = ServiceLocator.instance.currentUser;
    
    if (currentUser == null) {
      // Not logged in: Redirect to Login Page using replacement to avoid Redundant Stack
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
          }
        },
      );
    } else {
      // Logged in: Show Reply Dialog
      _showReplyDialog(commentId);
    }
  }

  void _showReplyDialog(String? commentId) {
    final controller = TextEditingController();
    HealthArticleComment? parentComment;
    if (commentId != null) {
      parentComment = _comments.firstWhere((c) => c.id == commentId);
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
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          enabled: !isSubmitting,
                          style: const TextStyle(color: Colors.black, fontSize: 15),
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'เขียนความคิดเห็นของคุณที่นี่...',
                            hintStyle: TextStyle(color: Colors.black.withOpacity(0.4), fontSize: 14),
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
                                  child: Image.network(authCurrentUser!.profileImageUrl!, fit: BoxFit.cover),
                                )
                              : const Icon(Icons.person, size: 20, color: Colors.white70),
                          ),
                          Expanded(
                            child: Text(
                              authCurrentUser?.username ?? 'คุณ',
                              style: const TextStyle(color: Color(0xFFF1AE27), fontSize: 12, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: isSubmitting ? null : () => Navigator.pop(context),
                            child: const Text('ยกเลิก', style: TextStyle(color: Colors.white54)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isSubmitting ? null : () async {
                              final content = controller.text;
                              if (content.trim().isNotEmpty) {
                                setDialogState(() => isSubmitting = true);
                                try {
                                  final newComment = await _submitComment(content, parentId: commentId);
                                  if (mounted && newComment != null) {
                                    Navigator.pop(context);
                                    
                                    if (commentId == null) {
                                      // Article Reply: Go to the page where the newest comment is
                                      final totalRootPages = (_totalRootComments / 10).ceil();
                                      
                                      if (_currentSort == 'oldest' && _currentPage != totalRootPages) {
                                        await _changePage(totalRootPages);
                                      } else if (_currentSort == 'newest' && _currentPage != 1) {
                                        await _changePage(1);
                                      }
                                    }
                                    
                                    // Precisely scroll to the new comment
                                    _scrollToSpecificComment(newComment.id);
                                  }
                                } catch (e) {
                                  setDialogState(() => isSubmitting = false);
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF1AE27),
                              foregroundColor: Colors.black87,
                              disabledBackgroundColor: const Color(0xFFF1AE27).withOpacity(0.5),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            child: isSubmitting 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87))
                              : const Text('ส่งคำตอบ', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  void _showEditDialog(HealthArticleComment comment) {
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
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          enabled: !isSubmitting,
                          style: const TextStyle(color: Colors.black, fontSize: 15),
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'เขียนความคิดเห็นของคุณที่นี่...',
                            hintStyle: TextStyle(color: Colors.black.withOpacity(0.4), fontSize: 14),
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
                                  child: Image.network(authCurrentUser!.profileImageUrl!, fit: BoxFit.cover),
                                )
                              : const Icon(Icons.person, size: 20, color: Colors.white70),
                          ),
                        Expanded(
                          child: Text(
                            authCurrentUser?.username ?? 'คุณ',
                            style: const TextStyle(color: Color(0xFFF1AE27), fontSize: 12, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                          TextButton(
                            onPressed: isSubmitting ? null : () => Navigator.pop(context),
                            child: const Text('ยกเลิก', style: TextStyle(color: Colors.white54)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isSubmitting ? null : () async {
                              final content = controller.text;
                              if (content.trim().isNotEmpty) {
                                setDialogState(() => isSubmitting = true);
                                try {
                                  final updatedComment = await _updateComment(comment.id, content);
                                  if (mounted && updatedComment != null) {
                                    Navigator.pop(context);
                                    _scrollToSpecificComment(comment.id);
                                  }
                                } catch (e) {
                                  setDialogState(() => isSubmitting = false);
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF1AE27),
                              foregroundColor: Colors.black87,
                              disabledBackgroundColor: const Color(0xFFF1AE27).withOpacity(0.5),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            child: isSubmitting 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87))
                              : const Text('บันทึกการแก้ไข', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
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
              comment.isHidden ? 'เปิดเผยความคิดเห็นแล้ว' : 'ปิดกั้นความคิดเห็นแล้ว'
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

  void _showEditHistoryDialog(HealthArticleComment comment) async {
    final repository = ServiceLocator.instance.healthArticleRepository;
    final history = await repository.getCommentEditHistory(comment.id);

    if (!mounted) return;

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
              // Header
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
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              // Edit history list
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
                      return _buildEditHistoryItem(edit);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditHistoryItem(CommentEditHistory edit) {
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
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
              ),
              const Spacer(),
              Text(
                _formatThaiDate(edit.editedAt),
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Old content
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.remove_circle_outline, size: 14, color: Colors.red),
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
          // New content
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.add_circle_outline, size: 14, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    edit.newContent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildPaginationSection() {
    final int totalPages = (_totalRootComments / 10).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildPageIcon(Icons.first_page, _currentPage > 1, () => _changePage(1)),
                _buildPageIcon(Icons.chevron_left, _currentPage > 1, () => _changePage(_currentPage - 1)),
                
                // First Page
                _buildPageButton('1', _currentPage == 1, () => _changePage(1)),
                
                if (_currentPage > 3) _buildPageButton('...', false, null),
                
                // Pages around current
                ...List.generate(3, (index) {
                  final page = _currentPage - 1 + index;
                  if (page <= 1 || page >= totalPages) return const SizedBox.shrink();
                  return _buildPageButton(page.toString(), _currentPage == page, () => _changePage(page));
                }),
                
                if (_currentPage < totalPages - 2) _buildPageButton('...', false, null),
                
                // Last Page
                if (totalPages > 1)
                  _buildPageButton(totalPages.toString(), _currentPage == totalPages, () => _changePage(totalPages)),
                
                _buildPageIcon(Icons.chevron_right, _currentPage < totalPages, () => _changePage(_currentPage + 1)),
                _buildPageIcon(Icons.last_page, _currentPage < totalPages, () => _changePage(totalPages)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'แสดง ${(_currentPage - 1) * 10 + 1}-${(_currentPage * 10).clamp(0, _totalRootComments)} จากทั้งหมด $_totalRootComments หัวข้อสนทนา ($_totalComments ความคิดเห็น)', 
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 16),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _currentPage,
                    dropdownColor: const Color(0xFF5D9CDB),
                    items: List.generate(totalPages, (index) => index + 1)
                        .map((page) => DropdownMenuItem(
                              value: page,
                              child: Text('หน้า $page', style: const TextStyle(fontSize: 12, color: Colors.white)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) _changePage(value);
                    },
                    icon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageIcon(IconData icon, bool enabled, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(12),
              color: enabled ? Colors.white : Colors.grey.shade50,
            ),
            child: Icon(
              icon, 
              size: 20, 
              color: enabled ? Colors.black87 : Colors.grey.shade300,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageButton(String text, bool isActive, VoidCallback? onTap) {
    final bool isEllipsis = text == '...';
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEllipsis ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive ? AppColors.primary : Colors.transparent,
              border: isActive 
                  ? null 
                  : Border.all(color: isEllipsis ? Colors.transparent : Colors.grey.shade200),
              borderRadius: BorderRadius.circular(12),
              boxShadow: isActive ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ] : null,
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isActive ? Colors.white : (isEllipsis ? Colors.grey : Colors.black87),
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditArticleDialog() {
    if (_article == null) return;
    
    // Check if the current user is the author
    final isAuthor = AuthService.instance.currentUser?.id == _article!.authorId;
    if (!isAuthor) return;

    if (_article!.editCount >= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('คุณได้ทำการแก้ไขบทความไปแล้ว 1 ครั้ง ไม่สามารถแก้ไขได้อีก'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          title: const Text('แก้ไขบทความ', style: TextStyle(color: Color(0xFF1A3B5D), fontWeight: FontWeight.bold)),
          content: const Text(
            'คุณได้รับอนุญาติให้แก้ไขเฉพาะข้อความได้เพียงครั้งเดียวเท่านั้น โดยจะมีการแจ้งเตือนการแก้ไขไปที่เจ้าของสินค้าที่ฝากไว้กับร้านคุณ',
            style: TextStyle(color: Colors.black87, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก', style: TextStyle(color: Colors.black54)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _openEditArticleScreen(); // Screen to edit texts
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF1AE27),
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('ดำเนินการต่อ', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _openEditArticleScreen() {
    if (_article == null) return;
    
    List<dynamic> parsedBlocks;
    try {
      parsedBlocks = jsonDecode(_article!.content);
    } catch (e) {
      parsedBlocks = [{'type': 'text', 'content': _article!.content}];
    }

    final List<TextEditingController> controllers = [];
    final originalBlocks = parsedBlocks;

    for (var block in originalBlocks) {
      if (block['type'] == 'text') {
        controllers.add(TextEditingController(text: block['content']));
      }
    }

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
                title: const Text('แก้ไขข้อความบทความ', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                actions: [
                  TextButton(
                    onPressed: isSubmitting ? null : () async {
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
                      final success = await _repository.editArticleText(
                        article: _article!,
                        newContent: newContentJson,
                      );
                      
                      if (success) {
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('บันทึกการแก้ไขสำเร็จ', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
                          );
                          _loadData(); // Reload to fetch fresh history and diffs
                        }
                      } else {
                        setModalState(() => isSubmitting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                    child: isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFFF1AE27), strokeWidth: 2))
                      : const Text('บันทึก', style: TextStyle(color: Color(0xFFF1AE27), fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
              body: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: originalBlocks.length,
                itemBuilder: (context, index) {
                  final block = originalBlocks[index];
                  if (block['type'] == 'text') {
                    // Find which controller corresponds to this block
                    int controllerIndex = 0;
                    for (int i = 0; i < index; i++) {
                      if (originalBlocks[i]['type'] == 'text') controllerIndex++;
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
                        style: const TextStyle(color: Colors.black, fontSize: 14, height: 1.6),
                        decoration: InputDecoration(
                          hintText: 'พิมพ์ข้อความ...',
                          hintStyle: TextStyle(color: Colors.black.withOpacity(0.3)),
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
                        image: DecorationImage(image: NetworkImage(block['content']), fit: BoxFit.cover),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Text('(ไม่สามารถแก้ไขรูปภาพได้)', style: TextStyle(color: Colors.white70)),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        );
      },
    );
  }

  void _showDiffDialog(String current, String original) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A3B5D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('ประวัติการแก้ไข', style: TextStyle(color: Color(0xFFF1AE27), fontWeight: FontWeight.bold)),
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
                const Text('ข้อความเดิม:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(original, style: const TextStyle(color: Colors.white, fontSize: 14)),
                ),
                const SizedBox(height: 16),
                const Text('ข้อความปัจจุบัน:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(current, style: const TextStyle(color: Colors.white, fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด', style: TextStyle(color: Color(0xFFF1AE27))),
          ),
        ],
      ),
    );
  }
}

class _ProductSectionDelegate extends SliverPersistentHeaderDelegate {
  final List<HealthArticleProduct> products;
  final Key? key;

  _ProductSectionDelegate({required this.products, this.key});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      key: key,
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: products.isEmpty ? 3 : products.length,
        itemBuilder: (context, index) {
          final colors = [const Color(0xFFCDE4F5), const Color(0xFFFEF3D3), const Color(0xFFFDE4D3)];
          final textColors = [const Color(0xFF5D9CDB), const Color(0xFFF1AE27), const Color(0xFFD3856E)];
          
          String label = 'รายการ ${index + 1}';
          if (index < products.length) label = products[index].name;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: const BoxConstraints(maxWidth: 160),
            decoration: BoxDecoration(
              color: colors[index % colors.length].withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColors[index % textColors.length],
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  double get maxExtent => 60;

  @override
  double get minExtent => 60;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => true;
}

class _RibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF1AE27)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(size.width / 2, size.height * 0.8);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _RichTextRenderer extends StatelessWidget {
  final String text;
  final String? oldText;
  final TextStyle style;
  final int? maxLines;

  const _RichTextRenderer({
    required this.text, 
    required this.style, 
    this.maxLines,
    this.oldText,
  });

  @override
  Widget build(BuildContext context) {
    if (oldText != null && oldText != text) {
      final diffs = diff(oldText!, text);
      cleanupSemantic(diffs);
      
      List<InlineSpan> spans = [];
      for (var d in diffs) {
        if (d.operation == 0) { // Unchanged
          spans.add(TextSpan(text: d.text, style: style));
        } else if (d.operation == 1) { // Added/New
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: () {
                final state = context.findAncestorStateOfType<_HealthArticlePageState>();
                state?._showDiffDialog(text, oldText!);
              },
              child: Text(
                d.text,
                style: style.copyWith(
                  color: style.color?.withOpacity(0.5) ?? Colors.grey,
                ),
              ),
            ),
          ));
        }
      }
      
      return Text.rich(
        TextSpan(children: spans),
        style: style,
        maxLines: maxLines,
        overflow: maxLines != null ? TextOverflow.ellipsis : null,
      );
    }

    List<TextSpan> spans = [];
    
    // A more robust parser that handles non-nested tags
    final regExp = RegExp(r'(\*\*.*?\*\*|<u>.*?</u>|<mark>.*?</mark>)');
    int lastMatchEnd = 0;
    
    final matches = regExp.allMatches(text).toList();
    
    if (matches.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: maxLines != null ? TextOverflow.ellipsis : null,
      );
    }

    for (final match in matches) {
      // Add text before match
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start), style: style));
      }
      
      final matchText = match.group(0)!;
      if (matchText.startsWith('**')) {
        spans.add(TextSpan(
          text: matchText.substring(2, matchText.length - 2),
          style: style.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (matchText.startsWith('<u>')) {
        spans.add(TextSpan(
          text: matchText.substring(3, matchText.length - 4),
          style: style.copyWith(decoration: TextDecoration.underline),
        ));
      } else if (matchText.startsWith('<mark>')) {
        spans.add(TextSpan(
          text: matchText.substring(6, matchText.length - 7),
          style: style.copyWith(
            backgroundColor: const Color(0xFFF1AE27).withOpacity(0.4),
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ));
      }
      
      lastMatchEnd = match.end;
    }
    
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd), style: style));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
    );
  }
}

class BookmarkedArticlesDialog extends StatefulWidget {
  const BookmarkedArticlesDialog({super.key});

  @override
  State<BookmarkedArticlesDialog> createState() => _BookmarkedArticlesDialogState();
}

class _BookmarkedArticlesDialogState extends State<BookmarkedArticlesDialog> {
  bool _isLoading = true;
  List<HealthArticle> _articles = [];

  @override
  void initState() {
    super.initState();
    _fetchBookmarks();
  }

  Future<void> _fetchBookmarks() async {
    final user = ServiceLocator.instance.currentUser;
    if (user != null) {
      final repo = ServiceLocator.instance.healthArticleRepository;
      final articles = await repo.getBookmarkedArticles(user.id);
      if (mounted) {
        setState(() {
          _articles = articles;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year + 543}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'บทความที่บันทึกไว้',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                )
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_articles.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('ยังไม่มีบทความที่บันทึกไว้', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: Scrollbar(
                  thumbVisibility: _articles.length > 5,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _articles.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final article = _articles[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        title: Text(
                          article.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            'วันที่สร้างบทความ: ${_formatDate(article.createdAt)}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => HealthArticlePage(article: article),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
