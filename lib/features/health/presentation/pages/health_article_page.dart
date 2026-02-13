import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../auth/data/models/user_model.dart';
import '../../data/models/health_article_models.dart';
import '../widgets/health_article_skeleton.dart';

/// Health Article Page
/// Feature-rich forum and article viewer with stacked sticky headers and nested comments.
class HealthArticlePage extends StatefulWidget {
  final HealthArticle? article;
  final int? targetPage;
  final String? targetCommentId;
  final String? pendingAction; // 'like' or 'bookmark'
  final String? pendingCommentId;

  const HealthArticlePage({
    super.key,
    this.article,
    this.targetPage,
    this.targetCommentId,
    this.pendingAction,
    this.pendingCommentId,
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
  
  // Data State
  HealthArticle? _article;
  List<HealthArticleProduct> _products = [];
  List<HealthArticleComment> _comments = [];
  int _totalComments = 0;
  int _totalRootComments = 0;
  bool _isLoading = true;
  bool _isCommentsLoading = false;
  final Set<String> _expandedCommentIds = {};

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
      final repository = ServiceLocator.instance.healthArticleRepository;
      
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
        // 2. Fetch Products and Total Comments
        final results = await Future.wait([
          repository.getArticleProducts(article.id),
          repository.getArticleCommentCount(article.id), // All
          repository.getArticleCommentCount(article.id, rootsOnly: true), // Roots for pagination
        ]);
        
        if (mounted) {
          setState(() {
            _article = article;
            _products = results[0] as List<HealthArticleProduct>;
            _totalComments = results[1] as int;
            _totalRootComments = results[2] as int;
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

    // Optimistic UI update
    bool previousIsBookmarked = false;
    setState(() {
      if (commentId != null) {
        final index = _comments.indexWhere((c) => c.id == commentId);
        if (index != -1) {
          final comment = _comments[index];
          previousIsBookmarked = comment.isBookmarked;
          _comments[index] = comment.copyWith(isBookmarked: !comment.isBookmarked);
        }
      } else {
        previousIsBookmarked = _article!.isBookmarked;
        _article = _article!.copyWith(isBookmarked: !_article!.isBookmarked);
      }
    });

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
        // Revert on failure
        setState(() {
          if (commentId != null) {
            final index = _comments.indexWhere((c) => c.id == commentId);
            if (index != -1) {
              _comments[index] = _comments[index].copyWith(isBookmarked: previousIsBookmarked);
            }
          } else {
            _article = _article!.copyWith(isBookmarked: previousIsBookmarked);
          }
        });
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

  /// Show a floating text effect (e.g. "+1 ❤️" or "🔖 บันทึกแล้ว!")
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
                  _buildNavButton('เกี่ยวกับฉัน', _activeSection == 'about', onTap: _showAuthorProfile),
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
                            'เปิดดู ${_article!.viewCount} • ${_totalComments} ความคิดเห็น',
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
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
                Text(
                  _article!.content,
                  maxLines: _isContentExpanded ? null : 5,
                  overflow: _isContentExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, height: 1.6, color: Colors.white.withOpacity(0.8)),
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
    
    return Container(
      key: commentKey,
      margin: EdgeInsets.fromLTRB(isReply ? 60 : 20, 8, 20, 8),
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
                    GestureDetector(
                      onTap: () => _handleReply(comment.id),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.reply, size: 14, color: Color(0xFFF1AE27)),
                          SizedBox(width: 4),
                          Text(
                            'ตอบกลับ', 
                            style: TextStyle(color: Color(0xFFF1AE27), fontSize: 12, fontWeight: FontWeight.bold)
                          ),
                        ],
                      ),
                    ),
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
          // Visibility control button for article author (bottom-right)
          if (_article?.authorId == AuthService.instance.currentUser?.id)
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: () => _toggleCommentVisibility(comment),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        comment.isHidden ? Icons.visibility_off : Icons.visibility,
                        size: 14,
                        color: comment.isHidden ? Colors.red.shade400 : const Color(0xFF4CAF50),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        comment.isHidden ? 'ปิดกั้น' : 'เปิดเผย',
                        style: TextStyle(
                          color: comment.isHidden ? Colors.red.shade400 : const Color(0xFF4CAF50),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
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
              ],
            ),
          ),
          if (isOwnComment)
            Positioned(
              top: 10,
              right: 0,
              child: GestureDetector(
                onTap: () => _showEditDialog(comment),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 14, color: Color(0xFFF1AE27)),
                      SizedBox(width: 4),
                      Text(
                        'แก้ไข',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF1AE27),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
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
                          Text(
                            authCurrentUser?.username ?? 'คุณ',
                            style: const TextStyle(color: Color(0xFFF1AE27), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
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
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                          Text(
                            authCurrentUser?.username ?? 'คุณ',
                            style: const TextStyle(color: Color(0xFFF1AE27), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
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
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
