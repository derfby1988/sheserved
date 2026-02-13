import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';
import 'package:sheserved/services/service_locator.dart';
import 'package:sheserved/services/auth_service.dart';
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
  String _selectedFilter = 'ล่าสุด';
  String _searchQuery = '';
  final List<String> _filters = ['ล่าสุด', 'ยอดนิยม', 'แนะนำ'];
  
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
    
    // Refresh articles when auth state changes
    AuthService.instance.addListener(_loadInitialArticles);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    AuthService.instance.removeListener(_loadInitialArticles);
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
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          if (AuthService.instance.currentUser == null) {
            // Navigate to login and wait for result
            await Navigator.pushNamed(context, '/login');
            
            // Re-check auth state after returning
            if (AuthService.instance.currentUser == null) return;
          }
          _showCreateArticleDialog();
        },
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
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

  void _showCreateArticleDialog() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    bool isSaving = false;
    List<String> images = []; // Placeholder for image paths
    List<String> productLinks = []; // Placeholder for product links
    
    const int maxTitleLength = 100;
    const int maxContentLength = 2000;
    const int maxImages = 5;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.edit_document, color: Colors.white),
                      const SizedBox(width: 12),
                      Text(
                        'สร้างบทความสุขภาพ',
                        style: AppTextStyles.heading5.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                ),

                // Content
                Flexible(
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title Field
                          Text('หัวข้อบทความ', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: titleController,
                            maxLength: maxTitleLength,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: InputDecoration(
                              hintText: 'กรอกหัวข้อบทความ...',
                              counterText: 'คงเหลือ ${maxTitleLength - titleController.text.length} ตัวอักษร',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppColors.primary, width: 2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Content Field
                          Text('เนื้อหาบทความ', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: contentController,
                            maxLength: maxContentLength,
                            maxLines: 8,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: InputDecoration(
                              hintText: 'บอกเล่าสาระสุขภาพดีๆ ของคุณ...',
                              counterText: 'คงเหลือ ${maxContentLength - contentController.text.length} ตัวอักษร',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppColors.primary, width: 2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Images Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('รูปภาพประกอบ (${images.length}/$maxImages)', 
                                  style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                              if (images.length < maxImages)
                                TextButton.icon(
                                  onPressed: () {
                                    // Placeholder for image picker
                                    setDialogState(() {
                                      images.add('https://picsum.photos/seed/${DateTime.now().millisecondsSinceEpoch}/400/300');
                                    });
                                  },
                                  icon: const Icon(Icons.add_a_photo, size: 18),
                                  label: const Text('เพิ่มรูป'),
                                  style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (images.isEmpty)
                            Container(
                              height: 100,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.image_outlined, color: Colors.grey[400]),
                                  const SizedBox(height: 4),
                                  Text('ยังไม่มีรูปภาพ', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                ],
                              ),
                            )
                          else
                            SizedBox(
                              height: 100,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: images.length,
                                itemBuilder: (context, index) => Container(
                                  width: 100,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    image: DecorationImage(image: NetworkImage(images[index]), fit: BoxFit.cover),
                                  ),
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: GestureDetector(
                                      onTap: () => setDialogState(() => images.removeAt(index)),
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                        child: const Icon(Icons.close, size: 16, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),

                          // Product Links Section
                          Text('สินค้าที่เกี่ยวข้อง', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                // Placeholder for product selector
                                setDialogState(() {
                                  productLinks.add('Product ${productLinks.length + 1}');
                                });
                              },
                              icon: const Icon(Icons.link, size: 18),
                              label: const Text('เพิ่มสินค้าที่เกี่ยวข้อง'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.primary),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          if (productLinks.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: productLinks.map((link) => Chip(
                                label: Text(link, style: const TextStyle(fontSize: 11)),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: () => setDialogState(() => productLinks.remove(link)),
                                backgroundColor: AppColors.primaryLight.withOpacity(0.3),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              )).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                // Footer Actions
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                    border: Border(top: BorderSide(color: Colors.grey[200]!)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: isSaving ? null : () => Navigator.pop(context),
                          child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: isSaving ? null : () async {
                            // Validation
                            if (titleController.text.trim().isEmpty || contentController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('กรุณากรอกหัวข้อและเนื้อหาบทความ')),
                              );
                              return;
                            }

                            setDialogState(() => isSaving = true);

                            try {
                              final repository = ServiceLocator.instance.healthArticleRepository;
                              final currentUser = AuthService.instance.currentUser;
                              
                              if (currentUser == null) {
                                Navigator.pop(context);
                                return;
                              }

                              final newArticle = await repository.createArticle(
                                userId: currentUser.id,
                                title: titleController.text.trim(),
                                content: contentController.text.trim(),
                                imageUrl: images.isNotEmpty ? images.first : null,
                              );

                              if (newArticle != null && mounted) {
                                Navigator.pop(context); // Close dialog
                                
                                // Navigate to the new article page
                                if (mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => HealthArticlePage(article: newArticle),
                                    ),
                                  );
                                  
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('เผยแพร่บทความสำเร็จ')),
                                  );
                                  
                                  // Refresh the list in the background
                                  _loadInitialArticles();
                                }
                              } else {
                                if (mounted) {
                                  setDialogState(() => isSaving = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('ไม่สามารถบันทึกข้อมูลได้ กรุณาตรวจสอบการเชื่อมต่อหรือสิทธิ์การใช้งาน'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              if (mounted) {
                                setDialogState(() => isSaving = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('ขออภัย เกิดข้อผิดพลาด: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: isSaving 
                            ? const SizedBox(
                                height: 20, 
                                width: 20, 
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('เผยแพร่บทความ', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            _selectedFilter,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          // Filter Icon
          PopupMenuButton<String>(
            icon: Icon(
              Icons.tune,
              color: AppColors.textSecondary,
              size: 20,
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
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HealthArticlePage(article: article),
          ),
        );
        // Refresh when returning to update like counts/bookmark status
        if (mounted) {
          _loadInitialArticles();
        }
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
                        '${article.commentCount}', 
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

