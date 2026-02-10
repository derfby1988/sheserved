import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';
import 'article_detail_page.dart';

/// Articles Page - บทความเพื่อสุขภาพ
/// แสดงรายการบทความแนะนำโดยผู้เชี่ยวชาญ
class ArticlesPage extends StatefulWidget {
  const ArticlesPage({super.key});

  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage> {
  String _selectedFilter = 'ทั้งหมด';
  final List<String> _filters = ['ทั้งหมด', 'ยอดนิยม', 'ล่าสุด', 'แนะนำ'];

  // Mock data for articles
  final List<Map<String, dynamic>> _articles = [
    {
      'id': '1',
      'title': 'Head',
      'views': 'xxx View',
      'items': '3 Item',
      'detail': 'detail..........................................',
      'likes': 609,
      'comments': 120,
    },
    {
      'id': '2',
      'title': 'Head',
      'views': 'xxx View',
      'items': '3 Item',
      'detail': 'detail..........................................',
      'likes': 609,
      'comments': 120,
    },
    {
      'id': '3',
      'title': 'Head',
      'views': 'xxx View',
      'items': '3 Item',
      'detail': 'detail..........................................',
      'likes': 609,
      'comments': 120,
    },
    {
      'id': '4',
      'title': 'Head',
      'views': 'xxx View',
      'items': '3 Item',
      'detail': 'detail..........................................',
      'likes': 609,
      'comments': 120,
    },
  ];

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
              child: _buildArticlesGrid(context),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          // Filter Icon
          PopupMenuButton<String>(
            icon: Icon(
              Icons.tune,
              color: AppColors.textSecondary,
            ),
            onSelected: (value) {
              setState(() {
                _selectedFilter = value;
              });
            },
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.7,
        ),
        itemCount: _articles.length,
        itemBuilder: (context, index) {
          return _buildArticleCard(context, _articles[index]);
        },
      ),
    );
  }

  Widget _buildArticleCard(BuildContext context, Map<String, dynamic> article) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ArticleDetailPage(article: article),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
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
            
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 80), // Space for circles
                  
                  // Stats Row
                  Row(
                    children: [
                      Icon(
                        Icons.favorite_border,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${article['likes']}',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.chat_bubble,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${article['comments']}',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Title
                  Text(
                    article['title'],
                    style: AppTextStyles.heading5.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // Views & Items
                  Text(
                    '${article['views']}  ${article['items']}',
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.orange,
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Detail
                  Text(
                    article['detail'],
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white.withOpacity(0.8),
                    ),
                    maxLines: 3,
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
