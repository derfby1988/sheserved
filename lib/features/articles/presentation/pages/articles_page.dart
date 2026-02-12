import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';
import 'package:sheserved/services/service_locator.dart';
import 'package:sheserved/features/health/data/models/health_article_models.dart';
import 'package:sheserved/features/health/presentation/pages/health_article_page.dart';
// import 'article_detail_page.dart'; // Unused

/// Articles Page - บทความเพื่อสุขภาพ
/// แสดงรายการบทความแนะนำโดยผู้เชี่ยวชาญ
class ArticlesPage extends StatefulWidget {
  const ArticlesPage({super.key});

  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage> {
  String _selectedFilter = 'ทั้งหมด';
  String _searchQuery = '';
  final List<String> _filters = ['ทั้งหมด', 'ยอดนิยม', 'ล่าสุด', 'แนะนำ'];
  
  final List<HealthArticle> _articles = [];
  final ScrollController _scrollController = ScrollController();
  
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  static const int _pageSize = 12;

  @override
  void initState() {
    super.initState();
    _loadInitialArticles();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoadingMore && _hasMore) {
        _loadMoreArticles();
      }
    }
  }

  Future<void> _loadInitialArticles() async {
    setState(() {
      _isLoading = true;
      _articles.clear();
      _page = 1;
      _hasMore = true;
    });

    try {
      final currentUserId = ServiceLocator.instance.currentUser?.id;
      final articles = await ServiceLocator.instance.healthArticleRepository.getAllArticles(
        category: _selectedFilter,
        searchQuery: _searchQuery,
        page: _page,
        pageSize: _pageSize,
        userId: currentUserId,
      );

      if (mounted) {
        setState(() {
          _articles.addAll(articles);
          _isLoading = false;
          if (articles.length < _pageSize) {
            _hasMore = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล: $e')),
        );
      }
    }
  }

  Future<void> _loadMoreArticles() async {
    setState(() => _isLoadingMore = true);

    try {
      _page++;
      final currentUserId = ServiceLocator.instance.currentUser?.id;
      final articles = await ServiceLocator.instance.healthArticleRepository.getAllArticles(
        category: _selectedFilter,
        searchQuery: _searchQuery,
        page: _page,
        pageSize: _pageSize,
        userId: currentUserId,
      );

      if (mounted) {
        setState(() {
          _articles.addAll(articles);
          _isLoadingMore = false;
          if (articles.length < _pageSize) {
            _hasMore = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onFilterChanged(String? value) {
    if (value != null && value != _selectedFilter) {
      setState(() {
        _selectedFilter = value;
      });
      _loadInitialArticles();
    }
  }

  void _onSearch(String query, List<Map<String, dynamic>> results) {
    if (query != _searchQuery) {
      setState(() {
        _searchQuery = query;
      });
      _loadInitialArticles();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const TlzDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            _buildTopNavigationBar(context),
            
            // Green Header with title
            _buildHeader(context),
            
            // Filter Bar
            _buildFilterBar(context),
            
            // Articles Grid
            Expanded(
              child: _isLoading 
                  ? _buildSkeletonGrid()
                  : _buildArticlesGrid(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopNavigationBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.background,
      child: TlzAppTopBar.onPrimary(
        notificationCount: 1,
        searchHintText: 'ค้นหาบทความ...',
        onQRTap: () {},
        onNotificationTap: () {},
        onCartTap: () {},
        onSearch: _onSearch,
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.primary,
      ),
      child: Row(
        children: [
          // Back Button
          GestureDetector(
            onTap: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Navigator.pushReplacementNamed(context, '/');
              }
            },
            child: const Icon(
              Icons.arrow_back,
              color: Colors.white,
              size: 24,
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Title
          Expanded(
            child: Text(
              'แนะนำโดยผู้เชี่ยวชาญ',
              style: AppTextStyles.heading4.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          const SizedBox(width: 40), // Balance for back button
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              'หมวดหมู่: $_selectedFilter',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Filter Icon
          PopupMenuButton<String>(
            icon: Icon(
              Icons.tune,
              color: AppColors.textSecondary,
            ),
            onSelected: _onFilterChanged,
            itemBuilder: (context) => _filters.map((filter) {
              return PopupMenuItem<String>(
                value: filter,
                child: Text(filter),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildArticlesGrid(BuildContext context) {
    if (_articles.isEmpty) {
      return const Center(child: Text('ไม่พบข้อมูลบทความ'));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: RefreshIndicator(
        onRefresh: _loadInitialArticles,
        child: GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.7,
          ),
          itemCount: _articles.length + (_isLoadingMore ? 2 : 0),
          itemBuilder: (context, index) {
            if (index < _articles.length) {
              return _buildArticleCard(context, _articles[index]);
            } else {
              return _buildSkeletonCard();
            }
          },
        ),
      ),
    );
  }

  Widget _buildSkeletonGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.7,
        ),
        itemCount: 8,
        itemBuilder: (context, index) => _buildSkeletonCard(),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildArticleCard(BuildContext context, HealthArticle article) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HealthArticlePage(article: article),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          image: article.imageUrl != null 
            ? DecorationImage(
                image: CachedNetworkImageProvider(article.imageUrl!),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.3),
                  BlendMode.darken,
                ),
              )
            : null,
        ),
        child: Stack(
          children: [
            if (article.imageUrl == null) ...[
              // Decorative Circles
              Positioned(
                top: 20,
                left: 20,
                child: _buildDecorativeCircle(60, AppColors.primary.withOpacity(0.3)),
              ),
              Positioned(
                top: 10,
                right: 40,
                child: _buildDecorativeCircle(70, AppColors.primary.withOpacity(0.2)),
              ),
              Positioned(
                top: 30,
                right: 20,
                child: _buildDecorativeCircleOutline(50),
              ),
            ],
            
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  
                  // Stats Row
                  Row(
                    children: [
                      const Icon(
                        Icons.favorite_border,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${article.likeCount}',
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.chat_bubble_outline,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${article.viewCount}', 
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Title
                  Text(
                    article.title,
                    style: AppTextStyles.heading5.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // Views & Author
                  Text(
                    '${article.viewCount} views • ${article.authorName ?? 'Expert'}',
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.orangeAccent,
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Detail (Content preview)
                  Text(
                    article.content,
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white.withOpacity(0.8),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDecorativeCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildDecorativeCircleOutline(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.5),
          width: 2,
        ),
      ),
    );
  }
}

