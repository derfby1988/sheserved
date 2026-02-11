import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../services/service_locator.dart';
import '../../data/models/health_article_models.dart';
import '../widgets/health_article_skeleton.dart';

/// Health Article Page
/// Feature-rich forum and article viewer with stacked sticky headers and nested comments.
class HealthArticlePage extends StatefulWidget {
  const HealthArticlePage({super.key});

  @override
  State<HealthArticlePage> createState() => _HealthArticlePageState();
}


class _HealthArticlePageState extends State<HealthArticlePage> {
  late ScrollController _scrollController;
  bool _showStickyTitle = false;
  String _activeSection = 'article';
  int _currentPage = 1;
  
  // Data State
  HealthArticle? _article;
  List<HealthArticleProduct> _products = [];
  List<HealthArticleComment> _comments = [];
  bool _isLoading = true;

  // Keys for Section Navigation
  final GlobalKey _articleHeadKey = GlobalKey();
  final GlobalKey _productsKey = GlobalKey();
  final GlobalKey _commentsKey = GlobalKey();

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
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final repository = ServiceLocator.instance.healthArticleRepository;
      
      // 1. Fetch Latest Article
      final article = await repository.getLatestArticle();
      
      if (article != null) {
        // 2. Fetch Related Data
        // Run in parallel for better performance
        final results = await Future.wait([
          repository.getArticleProducts(article.id),
          repository.getArticleComments(article.id),
        ]);
        
        if (mounted) {
          setState(() {
            _article = article;
            _products = results[0] as List<HealthArticleProduct>;
            _comments = results[1] as List<HealthArticleComment>;
            _isLoading = false;
          });
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

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submitComment(String content, {String? parentId}) async {
    if (content.trim().isEmpty || _article == null) return;
    
    final currentUser = ServiceLocator.instance.currentUser;
    if (currentUser == null) return;

    try {
      if (_article!.id.startsWith('mock-')) {
        // Handle mock submission for development
        final mockComment = HealthArticleComment(
          id: 'mock-c-${DateTime.now().millisecondsSinceEpoch}',
          articleId: _article!.id,
          userId: currentUser.id,
          username: 'คุณ (จำลอง)',
          content: content,
          commentNumber: _comments.length + 1,
          createdAt: DateTime.now(),
        );
        setState(() {
          _comments.insert(0, mockComment);
        });
        return;
      }

      final repository = ServiceLocator.instance.healthArticleRepository;
      final newComment = await repository.postComment(
        articleId: _article!.id,
        userId: currentUser.id,
        content: content,
        parentId: parentId,
        commentNumber: _comments.length + 1,
      );

      if (newComment != null && mounted) {
        setState(() {
          _comments.insert(0, newComment);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ส่งความคิดเห็นเรียบร้อยแล้ว')),
        );
      }
    } catch (e) {
      debugPrint('Error posting comment: $e');
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
      final RenderBox? commentsBox = _commentsKey.currentContext!.findRenderObject() as RenderBox?;
      if (commentsBox != null) {
        final position = commentsBox.localToGlobal(Offset.zero).dy;
        // If comments section top is near the control bar
        if (position < 150) {
          newSection = 'comments';
        } else if (_productsKey.currentContext != null) {
          final RenderBox? productsBox = _productsKey.currentContext!.findRenderObject() as RenderBox?;
          if (productsBox != null) {
            final prodPosition = productsBox.localToGlobal(Offset.zero).dy;
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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // AREA 1: Top Navigation Bar (Fixed)
            _buildArea1TopBar(),
            
            // AREA 2: Fixed Control Bar (Fixed)
            _buildArea2ControlBar(),

            // SCROLLABLE AREA (3, 4, 5) or LOADING/ERROR
            Expanded(
              child: _isLoading 
                ? const HealthArticleSkeleton()
                : _article == null
                  ? const Center(child: Text('ไม่พบบทความ', style: TextStyle(fontSize: 18, color: Colors.grey)))
                  : CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        // AREA 3: Article Head Section
                        SliverToBoxAdapter(
                          key: _articleHeadKey,
                          child: _buildArea3ArticleHead(),
                        ),
      
                        // AREA 4: Stacked Sticky Product Tagging List
                        if (_products.isNotEmpty)
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _ProductSectionDelegate(
                              products: _products,
                              key: _productsKey,
                            ),
                          ),
      
                        // AREA 5: Nested Comment System
                        SliverToBoxAdapter(
                          key: _commentsKey,
                          child: _buildCommentSystemHeader(),
                        ),
                        
                        if (_comments.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Center(child: Text('ยังไม่มีความคิดเห็น', style: TextStyle(color: Colors.grey))),
                            ),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildCommentItem(index),
                              childCount: _comments.length,
                            ),
                          ),
                        
                        // Pagination Section (Only show if comments exist)
                        if (_comments.isNotEmpty)
                          SliverToBoxAdapter(
                            child: _buildPaginationSection(),
                          ),
                        
                        // Bottom Padding
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 80),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      // AREA 6: Floating Back to Top Button
      floatingActionButton: _showStickyTitle 
        ? FloatingActionButton(
            onPressed: () => _scrollController.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut),
            backgroundColor: Colors.white.withOpacity(0.8),
            elevation: 2,
            mini: true,
            child: const Icon(Icons.keyboard_arrow_up, color: AppColors.primary),
          )
        : null,
    );
  }

  Widget _buildArea1TopBar() {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TlzAppTopBar.onPrimary(
        notificationCount: 3,
        searchHintText: 'ค้นหาบทความสุขภาพ...',
        onNotificationTap: () {},
        onCartTap: () {},
      ),
    );
  }

  Widget _buildArea2ControlBar() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          if (_showStickyTitle && _article != null)
            Expanded(
              child: Text(
                _article!.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          // Navigation Shortcuts
          if (_products.isNotEmpty)
            _buildNavButton(
              'สินค้า', 
              _activeSection == 'products' ? Icons.shopping_bag : Icons.shopping_bag_outlined, 
              () => _scrollToSection(_productsKey),
              isActive: _activeSection == 'products',
            ),
          _buildNavButton(
            'คอมเมนต์', 
            _activeSection == 'comments' ? Icons.chat_bubble : Icons.chat_bubble_outline, 
            () => _scrollToSection(_commentsKey),
            isActive: _activeSection == 'comments',
          ),
          _buildNavButton(
            'เกี่ยวกับ', 
            Icons.info, 
            () => _scrollToSection(_articleHeadKey),
            isActive: _activeSection == 'article',
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildNavButton(String label, IconData icon, VoidCallback onTap, {bool isActive = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: isActive ? AppColors.primary : Colors.grey),
        label: Text(
          label, 
          style: TextStyle(
            fontSize: 12, 
            color: isActive ? AppColors.primary : Colors.grey,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          )
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          backgroundColor: isActive ? AppColors.primary.withOpacity(0.05) : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _article!.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.3),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              GestureDetector(
                onTap: _showAuthorProfile,
                child: Hero(
                  tag: 'author_avatar',
                  child: CircleAvatar(
                    radius: 24,
                    backgroundImage: _article!.authorImage != null 
                        ? NetworkImage(_article!.authorImage!) 
                        : const NetworkImage('https://i.pravatar.cc/100'),
                    backgroundColor: Colors.grey.shade200,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _article!.authorName ?? 'ไม่ระบุชื่อ', 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.verified, size: 14, color: AppColors.primary),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDate(_article!.createdAt)} • อ่าน ${_article!.viewCount} • ${_comments.length} คอมเมนต์',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12)
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.bookmark_border, color: AppColors.primary),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            _article!.content,
            style: const TextStyle(fontSize: 16, height: 1.6, color: Color(0xFF444444)),
          ),
          const SizedBox(height: 16),
          // Dynamic Article Image
          if (_article!.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                _article!.imageUrl!,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 200, 
                  color: Colors.grey.shade200,
                  child: const Center(child: Icon(Icons.image_not_supported, color: Colors.grey)),
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildCommentSystemHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'ความคิดเห็น (${_comments.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: 'latest',
              items: const [
                DropdownMenuItem(value: 'latest', child: Text('ล่าสุด', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'popular', child: Text('ยอดนิยม', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'oldest', child: Text('เก่าสุด', style: TextStyle(fontSize: 13))),
              ],
              onChanged: (value) {},
              style: const TextStyle(color: AppColors.primary),
              icon: const Icon(Icons.sort, size: 18, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(int index) {
    if (index >= _comments.length) return const SizedBox.shrink();
    
    final comment = _comments[index];
    final bool isReply = comment.parentId != null;
    
    return Container(
      padding: EdgeInsets.fromLTRB(isReply ? 48 : 20, 12, 20, 12),
      decoration: BoxDecoration(
        color: isReply ? Colors.grey.shade50 : Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: comment.userImage != null 
                    ? NetworkImage(comment.userImage!) 
                    : null,
                child: comment.userImage == null 
                    ? const Icon(Icons.person, size: 20, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comment.username ?? 'ผู้ใช้ทั่วไป', 
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isReply ? AppColors.primary : Colors.black87,
                    ),
                  ),
                  Text(_formatTimeAgo(comment.createdAt), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              const Spacer(),
              const Icon(Icons.more_vert, size: 18, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            comment.content,
            style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildInteractionButton(Icons.favorite_border, '${comment.likeCount}', () {}),
              const SizedBox(width: 20),
              _buildInteractionButton(Icons.chat_bubble_outline, 'ตอบกลับ', () => _handleReply(comment.id)),
              const Spacer(),
              if (!isReply) _buildInteractionButton(Icons.share_outlined, '', () {}),
            ],
          ),
        ],
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

  void _handleReply(String commentId) {
    // Check if user is logged in
    final currentUser = ServiceLocator.instance.currentUser;
    
    if (currentUser == null) {
      // Not logged in: Redirect to Login Page with return argument
      Navigator.pushNamed(
        context, 
        '/login',
        arguments: '/health/article',
      ).then((_) {
        // Check again after returning from login
        if (ServiceLocator.instance.currentUser != null) {
          _showReplyDialog(commentId);
        }
      });
    } else {
      // Logged in: Show Reply Dialog
      _showReplyDialog(commentId);
    }
  }

  void _showReplyDialog(String commentId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ตอบกลับความคิดเห็น'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'เขียนความคิดเห็นของคุณ...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              final content = controller.text;
              Navigator.pop(context);
              if (content.isNotEmpty) {
                _submitComment(content, parentId: commentId);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('ส่ง'),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationSection() {
    if (_comments.isEmpty) return const SizedBox.shrink();
    const int totalPages = 10;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildPageIcon(Icons.first_page, _currentPage > 1, () {
                  setState(() => _currentPage = 1);
                }),
                _buildPageIcon(Icons.chevron_left, _currentPage > 1, () {
                  setState(() => _currentPage--);
                }),
                _buildPageButton('1', _currentPage == 1, () => setState(() => _currentPage = 1)),
                if (_currentPage > 3) _buildPageButton('...', false, null),
                if (_currentPage > 2 && _currentPage < totalPages - 1) 
                  _buildPageButton(_currentPage.toString(), true, null),
                if (_currentPage < totalPages - 2) _buildPageButton('...', false, null),
                _buildPageButton(totalPages.toString(), _currentPage == totalPages, () => setState(() => _currentPage = totalPages)),
                _buildPageIcon(Icons.chevron_right, _currentPage < totalPages, () {
                  setState(() => _currentPage++);
                }),
                _buildPageIcon(Icons.last_page, _currentPage < totalPages, () {
                  setState(() => _currentPage = totalPages);
                }),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'แสดง ${(_currentPage - 1) * 10 + 1}-${_currentPage * 10} จากทั้งหมด ${totalPages * 10} ความคิดเห็น', 
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
              const SizedBox(width: 16),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _currentPage,
                    items: List.generate(totalPages, (index) => index + 1)
                        .map((page) => DropdownMenuItem(
                              value: page,
                              child: Text('หน้า $page', style: const TextStyle(fontSize: 12)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _currentPage = value);
                      }
                    },
                    icon: const Icon(Icons.arrow_drop_down, size: 16),
                    style: const TextStyle(color: AppColors.primary),
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
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: overlapsContent 
          ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
          : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('สินค้าที่เกี่ยวข้อง', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                SizedBox(width: 8),
                Icon(Icons.shopping_bag, size: 14, color: AppColors.primary),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: products.isEmpty 
              ? const Padding(
                  padding: EdgeInsets.only(left: 20),
                  child: Text('ไม่มีสินค้าที่แนะนำ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return _buildProductCard(
                      product.name, 
                      product.imageUrl ?? '', 
                      _getTagColor(product.tagType), 
                      product.tagType == 'author' ? 'ผู้เชี่ยวชาญ' : (product.tagType == 'sponsor' ? 'สปอนเซอร์' : 'ผู้ใช้')
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  Color _getTagColor(String type) {
    switch (type) {
      case 'author': return const Color(0xFF6CB0C5);
      case 'sponsor': return const Color(0xFFF1AE27);
      default: return const Color(0xFFD3856E);
    }
  }

  Widget _buildProductCard(String name, String imageUrl, Color tagColor, String tagLabel) {
    return Container(
      width: 180,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Container(
              width: 6,
              color: tagColor,
            ),
            if (imageUrl.isNotEmpty)
              SizedBox(
                width: 60,
                height: 60,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(imageUrl, fit: BoxFit.cover),
                  ),
                ),
              )
            else
              Container(
                width: 60,
                height: 60,
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shopping_bag, size: 20, color: Colors.grey),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 10, top: 10, bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: tagColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tagLabel,
                        style: TextStyle(fontSize: 9, color: tagColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  double get maxExtent => 120;

  @override
  double get minExtent => 120;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => true;
}
